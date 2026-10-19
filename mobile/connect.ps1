Write-Host "[1/4] Telefon IP manzili (Hotspot Gateway) qidirilmoqda..." -ForegroundColor Cyan

# Asosiy shlyuz (Default Gateway) IP manzilini avtomatik aniqlash
$phoneIP = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1).NextHop

if (-not $phoneIP) {
    Write-Host "[XATO] Wi-Fi tarmog'i topilmadi! Kompyuter telefon Hotspot'iga ulanganini tekshiring." -ForegroundColor Red
    exit
}

Write-Host "[OK] Telefon IP manzili topildi: $phoneIP" -ForegroundColor Green
$target = "${phoneIP}:5555"

# 1-urinish: To'g'ridan-to'g'ri 5555 portga ulanib ko'rish
Write-Host "[2/4] Wi-Fi orqali ulanilmoqda ($target)..." -ForegroundColor Yellow
$connectResult = adb connect $target | Out-String

# Agar 5555 port yopiq bo'lsa (10061 yoki 10060 xatosi chiqsa)
if ($connectResult -match "cannot connect" -or $connectResult -match "10061" -or $connectResult -match "10060") {
    Write-Host "[DIQQAT] 5555-port yopiq! (Telefon qayta yoqilgan yoki port hali ochilmagan)." -ForegroundColor Yellow
    Write-Host ">>> Iltimos, telefonni 5 soniyaga USB kabel orqali kompyuterga ulang..." -ForegroundColor Magenta
    
    # USB kabel ulanishini kutish
    adb wait-for-usb-device
    Write-Host "[OK] USB kabel ulandi! 5555-port ochilmoqda..." -ForegroundColor Green
    
    adb tcpip 5555
    Start-Sleep -Seconds 2
    
    Write-Host ">>> Endi USB kabelni sug'urib olishingiz mumkin!" -ForegroundColor Cyan
    $connectResult = adb connect $target | Out-String
}

Write-Host $connectResult

# 8080 portni backend uchun reverse qilish
Write-Host "[3/4] Backend uchun 8080-port bog'lanmoqda (adb reverse)..." -ForegroundColor Cyan
adb -s $target reverse tcp:8080 tcp:8080

Write-Host "[4/4] Hammasi tayyor! Endi flutter run qilishingiz mumkin." -ForegroundColor Green
adb devices