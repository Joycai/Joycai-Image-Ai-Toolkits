param(
  [string[]]$Scenes,
  [string]$Size = '',
  [string]$Tag = 'run',
  [int]$Frames = 240,
  [int]$Warmup = 90,
  [int]$TimeoutSec = 150
)

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$exe = Join-Path $repo 'build\windows\x64\runner\Profile\joycai_image_ai_toolkits.exe'
if (-not (Test-Path $exe)) { throw "No profile build at $exe -- run: flutter build windows --profile" }
$outDir = Join-Path $repo "build\bench\$Tag"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$env:RBENCH = '1'
$env:RBENCH_FRAMES = "$Frames"
$env:RBENCH_WARMUP = "$Warmup"
if ($Size -ne '') { $env:RBENCH_SIZE = $Size } else { Remove-Item Env:RBENCH_SIZE -ErrorAction SilentlyContinue }

foreach ($scene in $Scenes) {
  $out = Join-Path $outDir "$scene.json"
  if (Test-Path $out) { Remove-Item $out }
  $env:RBENCH_SCENE = $scene
  $env:RBENCH_LABEL = "$Tag/$scene"
  $env:RBENCH_OUT = $out
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $p = Start-Process -FilePath $exe -PassThru
  if (-not $p.WaitForExit($TimeoutSec * 1000)) {
    try { $p.Kill() } catch {}
    Write-Output "$scene TIMEOUT after ${TimeoutSec}s"
    continue
  }
  $sw.Stop()
  if (Test-Path $out) {
    $j = Get-Content $out -Raw | ConvertFrom-Json
    $bd = [math]::Round($j.build.p50, 2)
    $rp50 = [math]::Round($j.raster.p50, 2)
    $rp90 = [math]::Round($j.raster.p90, 2)
    $fps = [math]::Round($j.fps, 1)
    Write-Output ("{0,-20} raster p50={1,7} p90={2,7}  build p50={3,5}  fps={4,6}  target={5} dpr={6}" -f $scene, $rp50, $rp90, $bd, $fps, $j.renderTarget, $j.devicePixelRatio)
  } else {
    Write-Output "$scene NO REPORT (exited in $([math]::Round($sw.Elapsed.TotalSeconds,1))s)"
  }
}
