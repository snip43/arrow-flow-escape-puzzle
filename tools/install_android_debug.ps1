param(
    [string]$AndroidSdk = $env:ANDROID_HOME,
    [string]$Apk = (Join-Path $PSScriptRoot '../build/android/arrow-flow-debug.apk')
)
$ErrorActionPreference = 'Stop'
if (!$AndroidSdk) { $AndroidSdk = $env:ANDROID_SDK_ROOT }
if (!$AndroidSdk) { $AndroidSdk = Join-Path $env:USERPROFILE 'AppData/Local/Android/Sdk' }
$adb = Join-Path $AndroidSdk 'platform-tools/adb.exe'
$package = 'com.romiqolab.arrowflow'
if (!(Test-Path -LiteralPath $Apk -PathType Leaf)) { throw 'Build the debug APK first.' }
$listing = & $adb devices -l
if ($LASTEXITCODE -ne 0) { throw 'adb devices failed.' }
$devices = @($listing | Where-Object { $_.Trim() -and $_ -notmatch '^List of devices' })
if ($devices.Count -ne 1 -or $devices[0] -notmatch '^(\S+)\s+device\b') {
    throw 'Connect exactly one authorized physical device and close any emulators.'
}
$serial = $Matches[1]
function Invoke-Device([string[]]$options) {
    $result = & $adb -s $serial @options
    if ($LASTEXITCODE -ne 0) { throw "ADB failed: $($options[0])" }
    $result
}
$qemu = Invoke-Device @('shell','getprop','ro.kernel.qemu')
$bootQemu = Invoke-Device @('shell','getprop','ro.boot.qemu')
if ($serial -like 'emulator-*' -or $qemu -eq '1' -or $bootQemu -eq '1') { throw 'Physical device required.' }
# Include packages with retained data. Install only for the active Android user.
$packages = Invoke-Device @('shell','pm','list','packages','-u',$package)
if ($packages -contains "package:$package") { throw 'Package or retained data already present. Existing profile preserved.' }
$installed = Invoke-Device @('install','--user','current',$Apk)
if ($installed -notcontains 'Success') { throw "Install failed: $installed" }
Invoke-Device @('shell','am','start','-W','-n',"$package/com.godot.game.GodotApp")
