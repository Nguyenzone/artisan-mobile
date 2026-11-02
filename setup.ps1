# Artisan Mobile - thiet lap du an lan dau (Windows PowerShell)
# Chay bang: setup.bat  (hoac: powershell -ExecutionPolicy Bypass -File setup.ps1)
$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

Write-Host '== 1/4 Kiem tra Flutter ==' -ForegroundColor Cyan
flutter --version
if ($LASTEXITCODE -ne 0) { throw 'Chua cai Flutter hoac Flutter chua co trong PATH.' }

Write-Host '== 2/4 Tao thu muc android/ va ios/ (giu nguyen code trong lib/) ==' -ForegroundColor Cyan
flutter create --platforms=android,ios --org com.minhdang --project-name artisan_mobile .
if ($LASTEXITCODE -ne 0) { throw 'flutter create that bai.' }

Write-Host '== 3/4 Them quyen mang (Modbus TCP qua WiFi) ==' -ForegroundColor Cyan
$utf8 = New-Object System.Text.UTF8Encoding $false
$manifest = Join-Path $PSScriptRoot 'android\app\src\main\AndroidManifest.xml'
$m = [System.IO.File]::ReadAllText($manifest)
if ($m -notmatch 'android.permission.INTERNET') {
  $perm = "`r`n    <uses-permission android:name=`"android.permission.INTERNET`"/>`r`n    <uses-permission android:name=`"android.permission.ACCESS_NETWORK_STATE`"/>"
  $m = [regex]::Replace($m, '(<manifest[^>]*>)', '$1' + $perm)
  [System.IO.File]::WriteAllText($manifest, $m, $utf8)
  Write-Host '   Da them quyen INTERNET vao AndroidManifest.xml'
}
$plist = Join-Path $PSScriptRoot 'ios\Runner\Info.plist'
if (Test-Path $plist) {
  $p = [System.IO.File]::ReadAllText($plist)
  if ($p -notmatch 'NSLocalNetworkUsageDescription') {
    $add = "`t<key>NSLocalNetworkUsageDescription</key>`n`t<string>Ket noi toi bo dieu khien may rang qua Modbus TCP trong mang noi bo.</string>`n</dict>`n</plist>"
    $p = [regex]::Replace($p, '</dict>\s*</plist>\s*$', $add)
    [System.IO.File]::WriteAllText($plist, $p, $utf8)
    Write-Host '   Da them quyen mang noi bo (Local Network) cho iOS'
  }
}

Write-Host '== 4/4 Tai thu vien ==' -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get that bai.' }

Write-Host ''
Write-Host 'XONG! Cam dien thoai Android (bat USB debugging) roi chay:  flutter run' -ForegroundColor Green
Write-Host 'Tao file cai dat APK:  flutter build apk --release' -ForegroundColor Green
