param(
    [Parameter(Mandatory)][string]$Godot,
    [string]$AndroidSdk,
    [string]$Jdk = $env:JAVA_HOME,
    [string]$Templates = (Join-Path $env:APPDATA 'Godot/export_templates/4.3.stable'),
    [string]$DebugKeystore = (Join-Path $env:USERPROFILE '.android/debug.keystore')
)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
if (!$AndroidSdk) { $AndroidSdk = $env:ANDROID_HOME }
if (!$AndroidSdk) { $AndroidSdk = $env:ANDROID_SDK_ROOT }
if (!$AndroidSdk) { $AndroidSdk = Join-Path $env:USERPROFILE 'AppData/Local/Android/Sdk' }
if (!$Jdk) { throw 'Set JAVA_HOME or pass -Jdk (JDK 17).' }
function Require-File([string]$file) {
    if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing required file: $file" }
    (Resolve-Path -LiteralPath $file).Path
}
$engine = Require-File $Godot
if ($engine -like '*_console.exe') { $engine = Require-File ($engine -replace '_console\.exe$','.exe') }
$console = Require-File ($engine -replace '\.exe$','_console.exe')
$version = & $console --version
if ($LASTEXITCODE -ne 0 -or $version -notmatch '^4\.3\.stable\.') { throw "Godot 4.3 stable required; got $version" }
$adb = Require-File (Join-Path $AndroidSdk 'platform-tools/adb.exe')
$tools = Get-ChildItem (Join-Path $AndroidSdk 'build-tools') -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (!$tools) { throw "Android build-tools missing under $AndroidSdk" }
$aapt = Require-File (Join-Path $tools.FullName 'aapt.exe')
$signer = Require-File (Join-Path $tools.FullName 'apksigner.bat')
$java = Require-File (Join-Path $Jdk 'bin/java.exe')
$debugKey = Require-File $DebugKeystore
foreach ($template in 'android_debug.apk','android_release.apk') { $null = Require-File (Join-Path $Templates $template) }

# A portable editor and runtime-only staging project keep the user's editor
# settings, import cache, test scripts and acceptance screenshots out of the APK.
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$uniqueName = 'arrow-flow-export-' + [guid]::NewGuid().ToString('N')
$work = Join-Path $tempRoot $uniqueName
$stage = Join-Path $work 'project'
$data = Join-Path $work 'editor_data'
$output = Join-Path $project 'build/android/arrow-flow-debug.apk'
$previousJava = $env:JAVA_HOME
try {
    $env:JAVA_HOME = (Resolve-Path $Jdk).Path
    $templateDir = Join-Path $data 'export_templates/4.3.stable'
    New-Item -ItemType Directory -Path $stage,$templateDir | Out-Null
    Copy-Item -LiteralPath $engine,$console -Destination $work
    New-Item -ItemType File -Path (Join-Path $work '_sc_') | Out-Null
    foreach ($name in 'android_debug.apk','android_release.apk') {
        Copy-Item -LiteralPath (Join-Path $Templates $name) -Destination $templateDir
    }
    foreach ($name in 'game','levels','scenes','ui','project.godot','export_presets.cfg') {
        Copy-Item -LiteralPath (Join-Path $project $name) -Destination $stage -Recurse
    }
    $settings = @(
        '[gd_resource type="EditorSettings" format=3]', '[resource]',
        ('export/android/android_sdk_path = "{0}"' -f (Resolve-Path $AndroidSdk).Path.Replace('\','/')),
        ('export/android/java_sdk_path = "{0}"' -f $env:JAVA_HOME.Replace('\','/')),
        ('export/android/debug_keystore = "{0}"' -f $debugKey.Replace('\','/'))
    )
    [IO.File]::WriteAllLines((Join-Path $data 'editor_settings-4.3.tres'),$settings)
    $portable = Join-Path $work (Split-Path $console -Leaf)
    function Invoke-Godot([string[]]$options) {
        $lines = & $portable --headless --path $stage @options 2>&1
        $code = $LASTEXITCODE
        $lines | Where-Object { $_ -notmatch '^ADDING:|apksigner\.bat sign' } | Out-Host
        if ($code -ne 0 -or $lines -match '(?i)(?:SCRIPT ERROR|ERROR):') { throw "Godot failed (exit $code)" }
    }
    Invoke-Godot @('--editor','--import')
    $fresh = Join-Path $work 'arrow-flow-debug.apk'
    Invoke-Godot @('--export-debug','Android Debug',$fresh)
    $null = Require-File $fresh
    $badging = & $aapt dump badging $fresh
    if ($LASTEXITCODE -ne 0) { throw 'aapt dump badging failed' }
    $summary = $badging | Where-Object { $_ -match '^(package:|sdkVersion:|targetSdkVersion:|native-code:|launchable-activity:|uses-permission)' }
    $summary | Out-Host
    if (!($summary -match "^package: name='com\.romiqolab\.arrowflow'") -or !($summary -match "^native-code:.*'arm64-v8a'.*'x86_64'")) { throw 'Unexpected package ID or ABI' }
    $permissions = & $aapt dump permissions $fresh
    if ($LASTEXITCODE -ne 0) { throw 'aapt dump permissions failed' }
    $permissions | Out-Host
    if ($permissions -match '^uses-permission') { throw 'The offline game must not request Android permissions.' }
    $cert = & $signer verify --verbose --print-certs $fresh
    $code = $LASTEXITCODE
    $cert | Out-Host
    if ($code -ne 0 -or !($cert -match 'certificate DN:.*CN=Android Debug')) { throw 'Android debug signature verification failed' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($fresh)
    try {
        $catalog = $archive.GetEntry('assets/levels/data/catalog.json')
        if (!$catalog) { throw 'Runtime catalogue missing from APK' }
        foreach ($folder in 'game','levels','scenes','ui') {
            foreach ($script in Get-ChildItem -LiteralPath (Join-Path $stage $folder) -Recurse -Filter '*.gd') {
                $entry = 'assets/' + $script.FullName.Substring($stage.Length + 1).Replace('\','/')
                if (!$archive.GetEntry($entry) -and !$archive.GetEntry($entry + '.remap')) { throw "Script missing from APK: $entry" }
            }
        }
        $stream = $catalog.Open()
        try { $hash = (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash } finally { $stream.Dispose() }
        if ($hash -ne '5401de5a357fba34ca8e0c2c03c78a1431dcc46ecf0929ab827416f4255d14ff') { throw 'Packaged catalogue hash mismatch' }
        if ($archive.Entries.FullName -match '^assets/(tests|docs|tools)/') { throw 'Development resources found in APK' }
    } finally { $archive.Dispose() }
    New-Item -ItemType Directory -Force -Path (Split-Path $output) | Out-Null
    Copy-Item -LiteralPath $fresh -Destination $output -Force
    $digest = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    Write-Output "APK=$output bytes=$((Get-Item -LiteralPath $output).Length) SHA256=$digest"
} finally {
    $env:JAVA_HOME = $previousJava
    if ((Test-Path -LiteralPath $work) -and
        [IO.Path]::GetFullPath($work) -eq [IO.Path]::Combine($tempRoot,$uniqueName) -and $uniqueName -match '^arrow-flow-export-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $work -Recurse -Force
    }
}
