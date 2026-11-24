param(
    [Parameter(Mandatory)][string]$Godot,
    [string[]]$Kinds = @('hint','continue'),
    [string[]]$Boundaries = @('before','prior','renamed','confirmed','applied','motion','stable','win-before','win-after','back-before','back-after','restart-before','restart-after'),
    [switch]$Capture,
    [string]$Results
)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$engine = (Resolve-Path -LiteralPath $Godot).Path
if ($engine -like '*_console.exe') { throw 'Use the Godot executable itself, not its console launcher.' }
$rows = @()
foreach ($kind in $Kinds) {
    foreach ($boundary in $Boundaries) {
        $name = 'af_test_' + [guid]::NewGuid().ToString('N')
        $scratch = Join-Path ([IO.Path]::GetTempPath()) $name
        [void][IO.Directory]::CreateDirectory($scratch)
        $marker = Join-Path $scratch 'boundary.json'
        function Start-Child([string]$phase,[bool]$render) {
            $opts = @('--path',('"{0}"' -f $project),'--fixed-fps','60','--log-file',('"{0}"' -f (Join-Path $scratch "$phase.log")))
            if (!$render) { $opts += '--headless' }
            $opts += @('--script','res://tests/crash_stage_1e_2c.gd','--',$phase,$name,$kind,$boundary,('"{0}"' -f $marker))
            if ($render) { $opts += '--capture' }
            Start-Process -FilePath $engine -ArgumentList $opts -PassThru -WindowStyle Hidden
        }
        function Verify-Child([string]$phase,[bool]$render) {
            $p = Start-Child $phase $render
            try {
                if (!$p.WaitForExit(40000)) { throw "$phase timeout PID=$($p.Id)" }
                $log = Get-Content -LiteralPath (Join-Path $scratch "$phase.log") -Raw
                if ($p.ExitCode -ne 0 -or $log -match '(?m)^(USER |SCRIPT )?ERROR:' -or $log -notmatch "VERIFY $phase PID=$($p.Id) checks=(\d+) failures=0") {
                    throw "$phase exit=$($p.ExitCode) $log"
                }
                [pscustomobject]@{pid=$p.Id; exit=$p.ExitCode; checks=[int]$Matches[1]}
            } finally {
                if (!$p.HasExited) { $p.Kill(); $p.WaitForExit() }
                $p.Dispose()
            }
        }
        $writer = Start-Child 'writer' $false
        try {
            $timer = [Diagnostics.Stopwatch]::StartNew()
            while (!(Test-Path -LiteralPath $marker) -and !$writer.HasExited -and $timer.ElapsedMilliseconds -lt 40000) {
                Start-Sleep -Milliseconds 30
            }
            if (!(Test-Path -LiteralPath $marker)) { throw (Get-Content -LiteralPath (Join-Path $scratch 'writer.log') -Raw) }
            $stamp = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
            if ($stamp.pid -ne $writer.Id -or $stamp.errors -ne 0 -or $stamp.kind -ne $kind -or $stamp.boundary -ne $boundary) { throw 'Writer marker mismatch' }
            $writer.Kill()
            if (!$writer.WaitForExit(5000) -or $writer.ExitCode -eq 0) { throw 'Writer did not exit forcibly' }
            $render = $Capture -and $boundary -eq 'renamed'
            $read = Verify-Child 'reader' $render
            $again = Verify-Child 'again' ($render -and $kind -eq 'hint')
            if (@(@($writer.Id,$read.pid,$again.pid) | Sort-Object -Unique).Count -ne 3) { throw 'PID reuse' }
            $warning = $null
            if ($render -and $kind -eq 'hint') { $warning = Verify-Child 'warning' $true }
            $row = [ordered]@{kind=$kind; boundary=$boundary; writer=$writer.Id; kill=$writer.ExitCode; read=$read; again=$again; warning=$warning; before=$stamp.before; after=$stamp.expected}
        } finally {
            if (!$writer.HasExited) { $writer.Kill(); $writer.WaitForExit() }
            $writer.Dispose()
            $cleanup = Verify-Child 'cleanup' $false
        }
        $row.cleanup = $cleanup
        $rows += [pscustomobject]$row
        Write-Host "$kind $boundary killed=$($row.writer) exit=$($row.kill) restored=$($read.pid),$($again.pid) checks=$($read.checks)+$($again.checks)"
        if ($Results) { ConvertTo-Json -InputObject $rows -Depth 9 | Set-Content -LiteralPath $Results -Encoding utf8 }
        foreach ($file in [IO.Directory]::GetFiles($scratch)) { [IO.File]::Delete($file) }
        [IO.Directory]::Delete($scratch)
    }
}
