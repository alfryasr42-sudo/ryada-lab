param(
    [ValidateSet('Run', 'Build')]
    [string]$Mode = 'Run'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root = Split-Path -Parent $PSScriptRoot
$ToolsRoot = 'D:\RiadaLabTools'
$FlutterDir = Join-Path $ToolsRoot 'flutter'
$script:SdkRoot = $null

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host "OK  $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "!   $Text" -ForegroundColor Yellow }

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Get-Flutter {
    $cmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $local = Join-Path $FlutterDir 'bin\flutter.bat'
    if (Test-Path $local) { return $local }
    return $null
}

function Install-Flutter {
    Write-Step 'تنزيل Flutter SDK (مرة واحدة فقط، قد يستغرق عدة دقائق)...'
    New-Item -ItemType Directory -Force -Path $ToolsRoot | Out-Null
    $json = Invoke-RestMethod 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
    $hash = $json.current_release.stable
    $rel = $json.releases | Where-Object { $_.hash -eq $hash -and $_.archive -like '*.zip' } | Select-Object -First 1
    if (-not $rel) { throw 'تعذر تحديد إصدار Flutter المستقر.' }
    $zip = Join-Path $ToolsRoot 'flutter.zip'
    $url = "$($json.base_url)/$($rel.archive)"
    Write-Host "    $url"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Expand-Archive -LiteralPath $zip -DestinationPath $ToolsRoot -Force
    Remove-Item $zip -Force
    return (Join-Path $FlutterDir 'bin\flutter.bat')
}

function Ensure-Jdk {
    Refresh-Path
    if (Get-Command java -ErrorAction SilentlyContinue) {
        Write-Ok 'Java موجود.'
        return
    }

    $roots = @('C:\Program Files\Eclipse Adoptium', 'C:\Program Files\Java', 'C:\Program Files\Microsoft')
    foreach ($r in $roots) {
        $jdk = Get-ChildItem $r -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'jdk-?(1[7-9]|2[0-9])' } |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($jdk) {
            $env:JAVA_HOME = $jdk.FullName
            $env:Path = "$($jdk.FullName)\bin;$env:Path"
            Write-Ok "Java: $($jdk.FullName)"
            return
        }
    }

    Write-Step 'تثبيت Java 17 (مطلوب لبناء أندرويد)...'
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'Java غير مثبت وwinget غير متاح. ثبّت Java 17 يدوياً ثم أعد المحاولة.'
    }
    & winget install --id EclipseAdoptium.Temurin.17.JDK -e --silent --accept-package-agreements --accept-source-agreements
    Refresh-Path

    $jdk = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'jdk-?17' } | Select-Object -First 1
    if (-not $jdk) {
        throw 'فشل تثبيت Java. ثبّته يدوياً من adoptium.net ثم أعد المحاولة.'
    }
    $env:JAVA_HOME = $jdk.FullName
    $env:Path = "$($jdk.FullName)\bin;$env:Path"
    Write-Ok "Java: $($jdk.FullName)"
}

function Find-SdkRoot {
    $candidates = @(
        'D:\Android\Sdk',
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT,
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk'),
        'C:\Android\Sdk'
    )
    foreach ($c in $candidates) {
        if (-not $c) { continue }
        if (Test-Path (Join-Path $c 'platform-tools\adb.exe')) { return $c }
        if (Test-Path (Join-Path $c 'cmdline-tools')) { return $c }
    }
    return 'D:\Android\Sdk'
}

function Ensure-AndroidSdk {
    $script:SdkRoot = Find-SdkRoot
    $sdk = $script:SdkRoot
    New-Item -ItemType Directory -Force -Path $sdk | Out-Null

    $sdkManager = Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
    if (-not (Test-Path $sdkManager)) {
        Write-Step 'تنزيل أدوات Android SDK (مرة واحدة فقط)...'
        $zip = Join-Path $ToolsRoot 'cmdline-tools.zip'
        $tmp = Join-Path $ToolsRoot 'cmdline-tools-tmp'
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Invoke-WebRequest -Uri 'https://dl.google.com/android/repository/commandlinetools-win-16111833_latest.zip' -OutFile $zip -UseBasicParsing
        Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
        $dest = Join-Path $sdk 'cmdline-tools'
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Remove-Item (Join-Path $dest 'latest') -Recurse -Force -ErrorAction SilentlyContinue
        Move-Item (Join-Path $tmp 'cmdline-tools') (Join-Path $dest 'latest')
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    $env:ANDROID_HOME = $sdk
    $env:ANDROID_SDK_ROOT = $sdk
    $env:Path = "$sdk\platform-tools;$sdk\cmdline-tools\latest\bin;$env:Path"

    $need = @()
    if (-not (Test-Path (Join-Path $sdk 'platform-tools\adb.exe'))) { $need += 'platform-tools' }
    foreach ($api in @('35', '36')) {
        if (-not (Test-Path (Join-Path $sdk "platforms\android-$api"))) { $need += "platforms;android-$api" }
    }
    foreach ($bt in @('35.0.0', '36.0.0')) {
        if (-not (Test-Path (Join-Path $sdk "build-tools\$bt"))) { $need += "build-tools;$bt" }
    }

    if ($need.Count -gt 0) {
        Write-Step 'تثبيت مكونات Android SDK (قد تستغرق عدة دقائق)...'
        & $sdkManager --sdk_root=$sdk @need 2>&1 | Out-Host
    }
    Write-Ok "Android SDK: $sdk"
}

function Invoke-Flutter {
    param([string[]]$Arguments)
    & $script:Flutter @Arguments
    if ($LASTEXITCODE -ne 0) { throw "فشل الأمر: flutter $($Arguments -join ' ')" }
}

try {
    Write-Host '========================================' -ForegroundColor Magenta
    Write-Host '        مختبر ريادة - مشغل التطبيق' -ForegroundColor Magenta
    Write-Host '========================================' -ForegroundColor Magenta

    $env:GRADLE_USER_HOME = 'D:\RiadaLabCaches\.gradle'
    $env:PUB_CACHE = 'D:\RiadaLabCaches\PubCache'
    $env:ANDROID_AVD_HOME = 'D:\Android\Avd'
    $env:TEMP = 'D:\RiadaLabCaches\temp'
    $env:TMP = $env:TEMP
    New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null

    $flutter = Get-Flutter
    if (-not $flutter) { $flutter = Install-Flutter }
    $script:Flutter = $flutter
    $env:Path = "$(Split-Path $flutter);$env:Path"
    Write-Ok "Flutter: $flutter"

    Ensure-Jdk
    Ensure-AndroidSdk

    # أعد إضافة Flutter إلى PATH بعد تحديث متغيرات البيئة
    $env:Path = "$(Split-Path $flutter);$env:Path"

    Write-Step 'التحقق من Flutter...'
    Invoke-Flutter -Arguments @('--version')
    & $flutter config --android-sdk $script:SdkRoot | Out-Null

    Write-Step 'تجهيز منصات المشروع...'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'tool\setup_platforms.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'فشل إعداد منصات المشروع.' }

    $serial = $null
    $adb = Join-Path $script:SdkRoot 'platform-tools\adb.exe'
    if (Test-Path $adb) {
        $serial = (& $adb devices) |
            Select-String '^\S+\s+device$' |
            ForEach-Object { ($_.Line -split '\s+')[0] } |
            Select-Object -First 1
    }

    if ($Mode -eq 'Run' -and -not $serial -and (Test-Path 'D:\Android\Avd\RiadaPhone.ini')) {
        Write-Step 'تشغيل محاكي Android...'
        Start-Process -FilePath (Join-Path $script:SdkRoot 'emulator\emulator.exe') `
            -ArgumentList @('-avd', 'RiadaPhone', '-gpu', 'auto', '-no-snapshot') `
            -WorkingDirectory (Join-Path $script:SdkRoot 'emulator')
        & $adb wait-for-device
        for ($i = 0; $i -lt 72; $i++) {
            $boot = (& $adb shell getprop sys.boot_completed 2>$null).Trim()
            if ($boot -eq '1') { break }
            Start-Sleep -Seconds 5
        }
        $serial = (& $adb devices) |
            Select-String '^\S+\s+device$' |
            ForEach-Object { ($_.Line -split '\s+')[0] } |
            Select-Object -First 1
    }

    if ($Mode -eq 'Run' -and $serial) {
        $apk = Join-Path $Root 'build\app\outputs\flutter-apk\app-release.apk'
        if (Test-Path $apk) {
            Write-Step "تثبيت التطبيق على $serial ..."
            & $adb install -r $apk | Out-Host
            if ($LASTEXITCODE -ne 0) { throw 'فشل تثبيت التطبيق على الجهاز.' }
            & $adb shell monkey -p com.riyada.lab.riada_lab -c android.intent.category.LAUNCHER 1 2>&1 | Out-Null
            Write-Ok 'تم تشغيل التطبيق.'
        }
        else {
            Invoke-Flutter -Arguments @('run', '-d', $serial)
        }
    }
    else {
        if ($Mode -eq 'Run') {
            Write-Warn 'لا يوجد هاتف موصول. سيتم بناء ملف APK بدلاً من التشغيل المباشر.'
            Write-Warn 'وصّل الهاتف وفعّل USB Debugging لتثبيت التطبيق تلقائياً.'
        }
        Write-Step 'بناء APK للإصدار...'
        Invoke-Flutter -Arguments @('build', 'apk', '--release')
        $apk = Join-Path $Root 'build\app\outputs\flutter-apk\app-release.apk'
        if (Test-Path $apk) {
            Write-Ok "تم البناء: $apk"
            Start-Process explorer.exe -ArgumentList "/select,`"$apk`""
        }
    }

    Write-Host "`nتمت العملية بنجاح." -ForegroundColor Green
}
catch {
    Write-Host "`nحدث خطأ: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
