param(
  [string[]]$Scenes,
  [string]$Size = '',
  [int]$SettleSec = 8,
  [int]$SampleSec = 6
)

# Absolute GPU time per frame, from \GPU Engine(...)\Running Time (100ns units,
# cumulative). FrameTiming.rasterDuration only covers the raster thread's own
# CPU work; with Skia on ANGLE/D3D11 the GPU executes asynchronously, so the
# engine counter is the only thing that sees the real cost.

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$exe = Join-Path $repo 'build\windows\x64\runner\Profile\joycai_image_ai_toolkits.exe'
if (-not (Test-Path $exe)) { throw "No profile build at $exe -- run: flutter build windows --profile" }

$env:RBENCH = '1'
$env:RBENCH_FRAMES = '100000'   # never reached; killed after sampling
$env:RBENCH_WARMUP = '60'
$env:RBENCH_SIZE = $Size
$env:RBENCH_OUT = ''

function Get-GpuRunningMs($procId) {
  $c = Get-Counter -Counter "\GPU Engine(pid_${procId}*engtype_3d)\Running Time" -ErrorAction SilentlyContinue
  if (-not $c) { return 0 }
  $sum = 0
  foreach ($s in $c.CounterSamples) { $sum += $s.CookedValue }
  return $sum / 10000.0   # 100ns ticks -> ms
}

$rows = @()
foreach ($scene in $Scenes) {
  $env:RBENCH_SCENE = $scene
  $env:RBENCH_LABEL = "gpu/$scene"
  $p = Start-Process -FilePath $exe -PassThru
  Start-Sleep -Seconds $SettleSec
  $t0 = Get-GpuRunningMs $p.Id
  $w0 = [Diagnostics.Stopwatch]::StartNew()
  Start-Sleep -Seconds $SampleSec
  $t1 = Get-GpuRunningMs $p.Id
  $w0.Stop()
  try { $p.Kill() } catch {}
  Start-Sleep -Milliseconds 500

  $wallMs = $w0.Elapsed.TotalMilliseconds
  $gpuMs = $t1 - $t0
  $busyPct = if ($wallMs -gt 0) { 100.0 * $gpuMs / $wallMs } else { 0 }
  # The window is vsync-paced at 60Hz, so frames in the sample window:
  $frames = $wallMs / 16.667
  $perFrame = if ($frames -gt 0) { $gpuMs / $frames } else { 0 }
  $rows += [pscustomobject]@{
    Scene      = $scene
    GpuMsFrame = [math]::Round($perFrame, 2)
    BusyPct    = [math]::Round($busyPct, 1)
    GpuMsTotal = [math]::Round($gpuMs, 0)
    WallMs     = [math]::Round($wallMs, 0)
  }
  $rows[-1] | Format-Table -AutoSize -HideTableHeaders | Out-String | Write-Output
}
Write-Output '--- summary ---'
$rows | Format-Table -AutoSize | Out-String | Write-Output
