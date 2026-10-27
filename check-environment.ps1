[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = $PSScriptRoot
$EngineExe = Join-Path $ProjectRoot 'tools\engine\realesrgan-ncnn-vulkan.exe'
$Python = Join-Path $ProjectRoot '.venv\Scripts\python.exe'

Write-Host 'AI Upscaler environment check' -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot"

if (-not (Test-Path -LiteralPath $Python)) {
    Write-Host 'FAIL: The project Python environment is missing. Run .\setup.ps1.' -ForegroundColor Red
    exit 1
}

& $Python -c "import PIL; print('Pillow:', PIL.__version__)"
if ($LASTEXITCODE -ne 0) {
    Write-Host 'FAIL: Pillow is unavailable. Run .\setup.ps1.' -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $EngineExe)) {
    Write-Host 'FAIL: Real-ESRGAN engine is missing. Run .\setup.ps1.' -ForegroundColor Red
    exit 1
}

Write-Host "Engine: $EngineExe" -ForegroundColor Green
Write-Host 'Engine help:' -ForegroundColor Cyan
$EngineHelp = (& $EngineExe -h 2>&1 | Out-String)
Write-Host $EngineHelp
if ($EngineHelp -notmatch 'Usage:\s+realesrgan-ncnn-vulkan') {
    Write-Host 'FAIL: The engine did not start. Update the GPU driver and check Vulkan support.' -ForegroundColor Red
    exit $LASTEXITCODE
}

$Gpu = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($Gpu) {
    Write-Host 'NVIDIA GPU:' -ForegroundColor Cyan
    & $Gpu.Source --query-gpu=name,driver_version,memory.total --format=csv,noheader
} else {
    Write-Host 'No NVIDIA utility found. The Vulkan engine may still work on Intel or AMD hardware.' -ForegroundColor Yellow
}
