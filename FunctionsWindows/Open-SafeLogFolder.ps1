Function Open-SafeLogFolder
{
	<#
		.SYNOPSIS
		Opens the server log folder through a handle that refuses links, and returns an object to write and prune files through it.

		.DESCRIPTION
		Internal. The log folder (%APPDATA%\NamedPipe-Logs) is writable by the standard user while the server that writes to it may be
		elevated. Checking the folder by path and then writing by path leaves a gap in which the folder can be swapped for a junction
		or symbolic link, redirecting an elevated write or delete. This function closes the gap:

		- the folder is opened once, with FILE_FLAG_OPEN_REPARSE_POINT (a link is opened as the link, never followed);
		- an open folder that is a reparse point, or whose final path is not <canonical parent>\<leaf>, is refused;
		- the handle is held without delete sharing, so while the returned object is open the folder cannot be renamed, removed or
		  replaced;
		- every file is created (CREATE_NEW) or deleted through its own handle, which is checked the same way.

		The returned [NamedPipe.SafeLogFolder] has WriteNewFile(leaf, text), RemoveOlderThan(pattern, cutoffUtc), Path, Refused and
		Errors, and must be disposed. A refusal throws [NamedPipe.SafeLogFolder+RefusedException]; a missing folder throws
		[System.IO.DirectoryNotFoundException]. Nothing is written or deleted in either case.

		The P/Invoke type is created once per process under the name NamedPipe.SafeLogFolder. A .NET type outlives the module that
		defined it, so never change the shape of a type that already carries this name; give a changed shape a new name instead.

		.PARAMETER Path
		The log folder.

		.PARAMETER Create
		Create the folder first when it does not exist (writers only).
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory)]
		[String]$Path,

		[Switch]$Create
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	Try
	{
		If (-not ('NamedPipe.SafeLogFolder' -as [type]))
		{
			Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace NamedPipe
{
	public sealed class SafeLogFolder : IDisposable
	{
		public sealed class RefusedException : IOException
		{
			public RefusedException(string message) : base(message) { }
		}

		const uint GENERIC_WRITE = 0x40000000;
		const uint DELETE = 0x00010000;
		const uint FILE_READ_ATTRIBUTES = 0x80;
		// An open that asks only for attributes takes no part in sharing checks, so the folder is opened with list access to be pinned.
		const uint FILE_LIST_DIRECTORY = 0x1;
		const uint SHARE_READ = 1, SHARE_WRITE = 2, SHARE_DELETE = 4;
		const uint CREATE_NEW = 1, OPEN_EXISTING = 3;
		const uint FLAG_BACKUP_SEMANTICS = 0x02000000;
		const uint FLAG_OPEN_REPARSE_POINT = 0x00200000;
		const uint ATTR_DIRECTORY = 0x10, ATTR_REPARSE_POINT = 0x400;

		[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
		static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

		[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
		static extern uint GetFinalPathNameByHandleW(SafeFileHandle handle, StringBuilder buffer, uint length, uint flags);

		[DllImport("kernel32.dll", SetLastError = true)]
		static extern bool GetFileInformationByHandle(SafeFileHandle handle, out HandleInfo info);

		[DllImport("kernel32.dll", SetLastError = true)]
		static extern bool SetFileInformationByHandle(SafeFileHandle handle, int infoClass, ref byte info, uint size);

		[StructLayout(LayoutKind.Sequential)]
		struct HandleInfo
		{
			public uint Attributes;
			public uint CreationLow, CreationHigh, AccessLow, AccessHigh, WriteLow, WriteHigh;
			public uint VolumeSerial, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
		}

		readonly SafeFileHandle dir;
		readonly SafeFileHandle parent;
		readonly string path;
		public readonly List<string> Refused = new List<string>();
		public readonly List<string> Errors = new List<string>();

		SafeLogFolder(SafeFileHandle parentHandle, SafeFileHandle dirHandle, string canonicalPath)
		{
			parent = parentHandle;
			dir = dirHandle;
			path = canonicalPath;
		}

		public string Path { get { return path; } }

		static string Long(string p)
		{
			if (p.StartsWith(@"\\?\")) return p;
			if (p.StartsWith(@"\\")) return @"\\?\UNC\" + p.Substring(2);
			return @"\\?\" + p;
		}

		static string Plain(string p)
		{
			if (p.StartsWith(@"\\?\UNC\")) return @"\\" + p.Substring(8);
			if (p.StartsWith(@"\\?\")) return p.Substring(4);
			return p;
		}

		static bool Same(string a, string b)
		{
			return string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
		}

		static SafeFileHandle OpenHandle(string p, uint access, uint share, uint disposition, uint flags)
		{
			SafeFileHandle h = CreateFileW(Long(p), access, share, IntPtr.Zero, disposition, flags, IntPtr.Zero);
			if (h.IsInvalid)
			{
				int err = Marshal.GetLastWin32Error();
				if (err == 2 || err == 3) throw new DirectoryNotFoundException("Not found: " + p);
				throw new Win32Exception(err, "Cannot open '" + p + "': " + new Win32Exception(err).Message);
			}
			return h;
		}

		static string FinalPath(SafeFileHandle h)
		{
			uint need = GetFinalPathNameByHandleW(h, null, 0, 0);
			if (need == 0) throw new Win32Exception(Marshal.GetLastWin32Error());
			StringBuilder sb = new StringBuilder((int)need + 1);
			uint got = GetFinalPathNameByHandleW(h, sb, need + 1, 0);
			if (got == 0) throw new Win32Exception(Marshal.GetLastWin32Error());
			return Plain(sb.ToString()).TrimEnd('\\');
		}

		static HandleInfo Info(SafeFileHandle h)
		{
			HandleInfo info;
			if (!GetFileInformationByHandle(h, out info)) throw new Win32Exception(Marshal.GetLastWin32Error());
			return info;
		}

		// Opens the folder without following a link and refuses anything that is not the real folder at the expected place.
		public static SafeLogFolder Open(string logFolder)
		{
			string full = System.IO.Path.GetFullPath(logFolder).TrimEnd('\\');
			string parentPath = System.IO.Path.GetDirectoryName(full);
			string leaf = System.IO.Path.GetFileName(full);
			if (string.IsNullOrEmpty(parentPath) || leaf.Length == 0)
				throw new RefusedException("Refused: '" + logFolder + "' has no parent folder to verify against.");

			// The parent is opened normally (it may legitimately be reached through a profile redirection); it only fixes
			// where the folder must be. It stays open so it cannot be renamed under us either.
			SafeFileHandle ph = OpenHandle(parentPath, FILE_LIST_DIRECTORY | FILE_READ_ATTRIBUTES, SHARE_READ | SHARE_WRITE, OPEN_EXISTING, FLAG_BACKUP_SEMANTICS);
			SafeFileHandle dh = null;
			try
			{
				string expected = FinalPath(ph) + "\\" + leaf;
				dh = OpenHandle(full, FILE_LIST_DIRECTORY | FILE_READ_ATTRIBUTES, SHARE_READ | SHARE_WRITE, OPEN_EXISTING, FLAG_BACKUP_SEMANTICS | FLAG_OPEN_REPARSE_POINT);
				HandleInfo info = Info(dh);
				if ((info.Attributes & ATTR_REPARSE_POINT) != 0)
					throw new RefusedException("Refused: '" + full + "' is a junction or symbolic link, not a folder.");
				if ((info.Attributes & ATTR_DIRECTORY) == 0)
					throw new RefusedException("Refused: '" + full + "' is not a folder.");
				string actual = FinalPath(dh);
				if (!Same(actual, expected))
					throw new RefusedException("Refused: '" + full + "' resolves to '" + actual + "', expected '" + expected + "'.");
				SafeLogFolder result = new SafeLogFolder(ph, dh, actual);
				ph = null;
				dh = null;
				return result;
			}
			finally
			{
				if (dh != null) dh.Dispose();
				if (ph != null) ph.Dispose();
			}
		}

		static void CheckLeaf(string leaf)
		{
			if (string.IsNullOrEmpty(leaf) || leaf.IndexOfAny(new char[] { '\\', '/', ':' }) >= 0 || leaf == "." || leaf == "..")
				throw new RefusedException("Refused: '" + leaf + "' is not a plain file name.");
		}

		// Creates a NEW file (never opens an existing name, so a planted link is not followed) and writes UTF-8 without a BOM.
		public string WriteNewFile(string leaf, string text)
		{
			CheckLeaf(leaf);
			string target = path + "\\" + leaf;
			using (SafeFileHandle h = OpenHandle(target, GENERIC_WRITE, SHARE_READ, CREATE_NEW, FLAG_OPEN_REPARSE_POINT))
			{
				HandleInfo info = Info(h);
				string actual = FinalPath(h);
				if ((info.Attributes & ATTR_REPARSE_POINT) != 0 || !Same(actual, target))
					throw new RefusedException("Refused: the new file resolved to '" + actual + "', expected '" + target + "'.");
				byte[] bytes = new UTF8Encoding(false).GetBytes(text);
				using (FileStream fs = new FileStream(h, FileAccess.Write, 4096, false))
				{
					fs.Write(bytes, 0, bytes.Length);
					fs.Flush();
				}
			}
			return target;
		}

		// Deletes matching files older than the cutoff, each through a verified handle. A link or a file that resolves
		// elsewhere is listed in Refused and left alone; a file that cannot be deleted is listed in Errors.
		public int RemoveOlderThan(string pattern, DateTime cutoffUtc)
		{
			int removed = 0;
			foreach (string entry in Directory.EnumerateFiles(Long(path), pattern))
			{
				string name = System.IO.Path.GetFileName(entry);
				string target = path + "\\" + name;
				try
				{
					using (SafeFileHandle h = OpenHandle(target, DELETE | FILE_READ_ATTRIBUTES, SHARE_READ | SHARE_WRITE | SHARE_DELETE, OPEN_EXISTING, FLAG_OPEN_REPARSE_POINT))
					{
						HandleInfo info = Info(h);
						if ((info.Attributes & (ATTR_REPARSE_POINT | ATTR_DIRECTORY)) != 0)
						{
							Refused.Add(name + ": link or folder");
							continue;
						}
						string actual = FinalPath(h);
						if (!Same(actual, target))
						{
							Refused.Add(name + ": resolves to " + actual);
							continue;
						}
						long ticks = ((long)info.WriteHigh << 32) | info.WriteLow;
						if (DateTime.FromFileTimeUtc(ticks) >= cutoffUtc) continue;
						byte dispose = 1; // FILE_DISPOSITION_INFO { BOOLEAN DeleteFile }
						if (!SetFileInformationByHandle(h, 4, ref dispose, 1)) throw new Win32Exception(Marshal.GetLastWin32Error());
						removed++;
					}
				}
				catch (IOException ex) { Errors.Add(name + ": " + ex.Message); }
				catch (Win32Exception ex) { Errors.Add(name + ": " + ex.Message); }
			}
			return removed;
		}

		public void Dispose()
		{
			dir.Dispose();
			parent.Dispose();
		}
	}
}
'@
		}

		If ($Create -and -not [System.IO.Directory]::Exists($Path))
		{ $null = New-Item -ItemType Directory -Path $Path -Force }

		# Seam between "make sure it exists" and "open it": the gap the old check-by-path left open. No-op; tests swap the folder here.
		Invoke-SafeLogFolderSeam

		, [NamedPipe.SafeLogFolder]::Open($Path)
	}
	Catch [System.IO.DirectoryNotFoundException]
	{ throw }
	Catch
	{
		Write-MyCatchAudit -Source 'Open-SafeLogFolder: opening the server log folder through a link-refusing handle - failing closed, nothing is written or deleted' -ErrorRecord $_
		throw
	}
}
