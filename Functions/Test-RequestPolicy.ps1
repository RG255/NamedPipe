Function Test-RequestPolicy
{
	<#
		.SYNOPSIS
		Decides whether a pipe request string is allowed to run, using a default-deny AST allowlist.

		.DESCRIPTION
		The elevated pipe server executes request strings via [ScriptBlock]::Create(...).Invoke().
		By itself that runs arbitrary code, which is a local privilege-escalation surface (see
		PIPE-INJECTION-HARDENING-PLAN.md). This function is the gate: called by Get-SBResult BEFORE
		execution when a request policy is configured, it parses the request into an Abstract Syntax
		Tree and permits it ONLY if every node is of an allowed shape:

		- a call to a command whose bare name is in Policy.AllowedCommands (no '&' / '.' invocation
		  operator, no dynamic/computed command name), and
		- the surrounding pipeline/structure and simple literal/variable/array/hashtable argument
		  values, and NOTHING else.

		The design is DEFAULT-DENY on node types: any AST node whose type is not on the allow list is
		rejected. This is deliberately stricter than blocklisting known-bad constructs, because a
		blocklist always has holes - e.g. `$ExecutionContext.SessionState.LanguageMode = 'FullLanguage'`
		is a plain assignment that slips past "no Add-Type / no method calls / no type literals" but is
		rejected here simply because AssignmentStatementAst is not on the allow list. Unknown attacks
		fail closed.

		This does NOT run the request and has no side effects. It is pure (string + policy in, verdict
		out) and self-contained (only .NET AST types), so it can be unit-tested in isolation.

		.PARAMETER Request
		The assembled command string that WOULD be executed (command + its escaped parameters), i.e.
		the exact text Get-SBResult passes to [ScriptBlock]::Create. Validating the assembled text (not
		just the bare command) means injected parameter values are seen too.

		.PARAMETER Policy
		Hashtable describing what is permitted:
		- AllowedCommands  [string[]] : bare command names that may be called (default: none = deny all
		  command calls). Case-insensitive.
		- AllowComputedArguments [bool] : when $true, permit expandable ("double quoted") strings that
		  contain embedded $(...) subexpressions. Default $false (strict): argument values must be
		  literals/variables, never computed. Note this does NOT open up arithmetic/format/sub-expression
		  arguments - those remain blocked; it only relaxes embedded-expression strings.

		.OUTPUTS
		PSCustomObject with:
		- Allowed [bool]
		- Reason  [string]  - human-readable explanation (the blocking reasons, or why it passed)

		.EXAMPLE
		Test-RequestPolicy -Request "Invoke-VHDAction -MountDisk 'True' -VHDLocation 'W:\x.vhdx'" `
			-Policy @{ AllowedCommands = @('Invoke-VHDAction') }
		Allowed = $true.

		.EXAMPLE
		Test-RequestPolicy -Request "Add-Type -TypeDefinition `$c; [Evil]::Run()" `
			-Policy @{ AllowedCommands = @('Invoke-VHDAction') }
		Allowed = $false (command not allowed + type/member expression).
	#>
	[CmdletBinding()]
	[OutputType([PSCustomObject])]
	Param (
		[Parameter(Mandatory, HelpMessage = 'The assembled request/command string to validate')]
		[AllowEmptyString()]
		[String]$Request,

		[Parameter(Mandatory, HelpMessage = 'Policy hashtable: AllowedCommands, AllowComputedArguments')]
		[Hashtable]$Policy
	)

	# Nested: short single-line snippet of an AST node's source, for rejection messages, so a reason
	# never dumps a whole multi-line request back to the caller.
	Function Get-RequestExtentSnippet
	{
		Param ($Node)
		$Private:Text = [String]$Node.Extent.Text -replace '\s+', ' '
		If ($Private:Text.Length -gt 60) { $Private:Text.Substring(0, 57) + '...' } Else { $Private:Text }
	}

	# --- resolve policy (default-deny defaults) ---
	$Private:Allowed = @()
	If ($Policy.ContainsKey('AllowedCommands') -and $Policy['AllowedCommands'])
	{ $Private:Allowed = @($Policy['AllowedCommands']) }
	$Private:AllowComputed = [Bool]$Policy['AllowComputedArguments']

	# Command-name comparison is case-insensitive.
	$Private:AllowedSet = New-Object 'System.Collections.Generic.HashSet[String]' ([StringComparer]::OrdinalIgnoreCase)
	ForEach ($Private:C in $Private:Allowed) { $null = $Private:AllowedSet.Add([String]$Private:C) }

	# --- parse ---
	$Private:ParseErrors = $null
	$Private:Ast = [System.Management.Automation.Language.Parser]::ParseInput($Request, [ref]$null, [ref]$Private:ParseErrors)
	If ($Private:ParseErrors -and $Private:ParseErrors.Count -gt 0)
	{
		Return [PSCustomObject]@{
			Allowed = $false
			Reason  = ('parse error: {0}' -f $Private:ParseErrors[0].Message)
		}
	}

	# --- the permitted AST node types (default-deny: anything else is rejected) ---
	# Structure + command call + simple literal/variable/array/hashtable argument values only.
	# Deliberately EXCLUDED (so they fail closed): AssignmentStatementAst (language-mode flip),
	# MemberExpressionAst / InvokeMemberExpressionAst (.NET calls), TypeExpressionAst ([type]),
	# ScriptBlockExpressionAst, SubExpressionAst ($(...)), BinaryExpressionAst / UnaryExpressionAst
	# (computed), ConvertExpressionAst (casts), FunctionDefinitionAst, If/ForEach/While/Trap/etc.
	$Private:AllowedNodeTypes = New-Object 'System.Collections.Generic.HashSet[String]' ([StringComparer]::Ordinal)
	ForEach ($Private:T in @(
			'ScriptBlockAst', 'NamedBlockAst', 'StatementBlockAst', 'PipelineAst',
			'CommandExpressionAst', 'CommandAst', 'CommandParameterAst',
			'StringConstantExpressionAst', 'ExpandableStringExpressionAst', 'ConstantExpressionAst',
			'VariableExpressionAst', 'ArrayLiteralAst', 'ArrayExpressionAst', 'HashtableAst',
			'ParenExpressionAst'
		)) { $null = $Private:AllowedNodeTypes.Add($Private:T) }

	$Private:Reasons = New-Object System.Collections.Generic.List[String]

	# Walk EVERY node.
	$Private:AllNodes = $Private:Ast.FindAll({ $true }, $true)
	ForEach ($Private:Node in $Private:AllNodes)
	{
		$Private:TypeName = $Private:Node.GetType().Name

		If (-not $Private:AllowedNodeTypes.Contains($Private:TypeName))
		{
			$Private:Reasons.Add(('disallowed construct ({0}): {1}' -f $Private:TypeName, (Get-RequestExtentSnippet $Private:Node)))
			Continue
		}

		Switch ($Private:TypeName)
		{
			'CommandAst'
			{
				# '&' / '.' invocation of a variable/scriptblock -> GetCommandName() is null; reject.
				If ($Private:Node.InvocationOperator -ne [System.Management.Automation.Language.TokenKind]::Unknown)
				{
					$Private:Reasons.Add(('invocation operator ''{0}'' (e.g. & or .): {1}' -f $Private:Node.InvocationOperator, (Get-RequestExtentSnippet $Private:Node)))
					Break
				}
				$Private:CmdName = $Private:Node.GetCommandName()
				If ([String]::IsNullOrEmpty($Private:CmdName))
				{
					$Private:Reasons.Add(('dynamic/computed command name: {0}' -f (Get-RequestExtentSnippet $Private:Node)))
					Break
				}
				If (-not $Private:AllowedSet.Contains($Private:CmdName))
				{
					$Private:Reasons.Add(('command not allowed: ''{0}''' -f $Private:CmdName))
				}
			}
			'ExpandableStringExpressionAst'
			{
				# Double-quoted string with embedded $(...) = computed. Blocked unless explicitly allowed.
				If ((-not $Private:AllowComputed) -and $Private:Node.NestedExpressions -and $Private:Node.NestedExpressions.Count -gt 0)
				{
					$Private:Reasons.Add(('computed (interpolated) string argument: {0}' -f (Get-RequestExtentSnippet $Private:Node)))
				}
			}
		}
	}

	If ($Private:Reasons.Count -gt 0)
	{
		# De-duplicate; keep order.
		$Private:Unique = $Private:Reasons | Select-Object -Unique
		Return [PSCustomObject]@{
			Allowed = $false
			Reason  = ($Private:Unique -join '; ')
		}
	}

	Return [PSCustomObject]@{
		Allowed = $true
		Reason  = 'all commands allowlisted; only literal/variable/array/hashtable arguments; no disallowed constructs'
	}
}
