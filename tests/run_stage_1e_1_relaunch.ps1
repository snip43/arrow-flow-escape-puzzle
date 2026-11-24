param(
    [Parameter(Mandatory)][string]$Godot,
    [switch]$Capture,
    [ValidateSet("1e_1","1e_2a")][string]$Stage = "1e_1"
)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$profileName = 'af_test_' + [Guid]::NewGuid().ToString('N')
$processIds = @{}
function Invoke-Phase([string]$phase) {
    $options = @('--path', $project, '--fixed-fps','60','--quit-after','4000',
        '--script',"res://tests/capture_stage_$Stage.gd")
    if (!$Capture -or $phase -eq 'cleanup') { $options += '--headless' }
    $options += @('--', $phase, $profileName)
    if ($Capture -and $phase -ne 'cleanup') { $options += '--capture' }
    $output = & $Godot @options
    $code = $LASTEXITCODE
    $output | Out-Host
    $tag = $Stage.ToUpperInvariant()
    $marker = $output | Select-String "^STAGE_${tag}_PROCESS $phase PID=(\d+) checks=\d+ failures=0$"
    if ($code -ne 0 -or !$marker) { throw "$phase failed (exit $code)" }
    $processIds[$phase] = $marker.Matches[0].Groups[1].Value
}
try {
    Invoke-Phase 'write'
    Invoke-Phase 'read'
    if ($processIds.write -eq $processIds.read) { throw 'Process IDs must differ' }
} finally {
    Invoke-Phase 'cleanup'
}
