# Creates the Android and iOS platform folders, applies the permissions required
# by the camera/scanner/OCR packages, then resolves dependencies.
# Run from PowerShell on a machine that has the Flutter SDK in PATH:
#   powershell -ExecutionPolicy Bypass -File .\tool\setup_platforms.ps1

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $root

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host 'Flutter SDK was not found in PATH.' -ForegroundColor Red
    Write-Host 'Install Flutter from https://docs.flutter.dev/get-started/install then run this script again.'
    exit 1
}

Write-Host 'Flutter version:'
flutter --version

if (-not (Test-Path 'android') -or -not (Test-Path 'ios')) {
    $tempProject = Join-Path $env:TEMP ("riada_lab_platforms_" + [guid]::NewGuid().ToString('N'))
    Write-Host "Generating platform folders in a temporary project..."
    flutter create --org com.riyada.lab --project-name riada_lab --platforms=android,ios $tempProject
    if (-not (Test-Path 'android')) {
        Copy-Item (Join-Path $tempProject 'android') $root -Recurse -Force
    }
    if (-not (Test-Path 'ios')) {
        Copy-Item (Join-Path $tempProject 'ios') $root -Recurse -Force
    }
    Remove-Item $tempProject -Recurse -Force
}

$utf8 = New-Object System.Text.UTF8Encoding($false)

# --- Android permissions -----------------------------------------------------
$manifest = Join-Path $root 'android\app\src\main\AndroidManifest.xml'
if (Test-Path $manifest) {
    $text = [System.IO.File]::ReadAllText($manifest)
    if ($text -notmatch 'android\.permission\.CAMERA') {
        $permissions = @'
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />

'@
        $index = $text.IndexOf('<application')
        if ($index -lt 0) { throw 'Could not find <application> in AndroidManifest.xml' }
        $text = $text.Insert($index, $permissions)
    }
    $text = $text -replace 'android:label="[^"]*"', 'android:label="مختبر ريادة"'
    [System.IO.File]::WriteAllText($manifest, $text, $utf8)
    Write-Host 'Android camera/gallery permissions applied.' -ForegroundColor Green
}

# --- Android minSdk (ML Kit + scanner need at least 23) ----------------------
$gradeFile = Get-ChildItem (Join-Path $root 'android\app') -Filter 'build.gradle*' -File |
    Select-Object -First 1
if ($gradeFile) {
    $gradle = [System.IO.File]::ReadAllText($gradeFile.FullName)
    $gradle = $gradle -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 23'
    $gradle = $gradle -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 23'
    [System.IO.File]::WriteAllText($gradeFile.FullName, $gradle, $utf8)
    Write-Host 'Android minSdk set to 23.' -ForegroundColor Green
}

# --- iOS usage descriptions --------------------------------------------------
$plist = Join-Path $root 'ios\Runner\Info.plist'
if (Test-Path $plist) {
    $text = [System.IO.File]::ReadAllText($plist)
    if ($text -notmatch 'NSCameraUsageDescription') {
        $keys = @'
	<key>NSCameraUsageDescription</key>
	<string>نستخدم الكاميرا لمسح باركود العينة وتصوير ورقة نتائج التحاليل.</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>نحتاج الوصول للصور لاختيار صورة ورقة النتائج لقراءتها.</string>
	<key>NSPhotoLibraryAddUsageDescription</key>
	<string>نحفظ صورة النتائج محلياً للرجوع إليها عند المراجعة.</string>
'@
        $index = $text.LastIndexOf('</dict>')
        if ($index -lt 0) { throw 'Could not find </dict> in Info.plist' }
        $text = $text.Insert($index, $keys)
    }
    $text = $text -replace '<key>CFBundleDisplayName</key>\s*<string>[^<]*</string>', ('<key>CFBundleDisplayName</key>' + "`r`n`t<string>مختبر ريادة</string>")
    [System.IO.File]::WriteAllText($plist, $text, $utf8)
    Write-Host 'iOS camera/photo usage descriptions applied.' -ForegroundColor Green
}

Write-Host 'Resolving packages...'
flutter pub get

Write-Host ''
Write-Host 'Done. Next steps:' -ForegroundColor Cyan
Write-Host '  flutter devices'
Write-Host '  flutter run'
Write-Host ''
Write-Host 'For Android, use a physical device or an emulator with a virtual camera.'
Write-Host 'For iOS, the camera does not work in the Simulator; use a real iPhone.'
