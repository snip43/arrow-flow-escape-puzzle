param(
    [Parameter(Mandatory)][string]$Godot,
    [switch]$Capture
)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$profileName = 'af_test_' + [Guid]::NewGuid().ToString('N')
$processIds = @{}
function Invoke-Phase([string]$phase) {
    $options = @('--path', $project, '--fixed-fps','60','--quit-after','4000',
        '--script','res://tests/capture_stage_1e_1.gd')
    if (!$Capture -or $phase -eq 'cleanup') { $options += '--headless' }
    $options += @('--', $phase, $profileName)
    if ($Capture -and $phase -ne 'cleanup') { $options += '--capture' }
    $output = & $Godot @options
    $code = $LASTEXITCODE
    $output | Out-Host
    $marker = $output | Select-String "^STAGE_1E_1_PROCESS $phase PID=(\d+) checks=\d+ failures=0$"
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
