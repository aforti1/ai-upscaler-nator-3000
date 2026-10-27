[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ProjectRoot = $PSScriptRoot
$ToolsRoot = Join-Path $ProjectRoot 'tools'
$EngineRoot = Join-Path $ToolsRoot 'engine'
$EngineExe = Join-Path $EngineRoot 'realesrgan-ncnn-vulkan.exe'
$ModelParam = Join-Path $EngineRoot 'models\realesrgan-x4plus.param'
$VenvRoot = Join-Path $ProjectRoot '.venv'
$VenvPython = Join-Path $VenvRoot 'Scripts\python.exe'
$ArchivePath = Join-Path $ToolsRoot 'realesrgan-ncnn-vulkan-20220424-windows.zip'
$EngineUrl = 'https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-windows.zip'

New-Item -ItemType Directory -Force -Path $ToolsRoot, (Join-Path $ProjectRoot 'cache'), (Join-Path $ProjectRoot 'outputs'), (Join-Path $ProjectRoot 'proofs') | Out-Null

$Python = Get-Command python -ErrorAction SilentlyContinue
if (-not $Python) {
    throw 'Python 3.10+ was not found on PATH. Install Python, reopen PowerShell, and run setup.ps1 again.'
}

if (-not (Test-Path -LiteralPath $VenvPython)) {
    Write-Host 'Creating an isolated project Python environment...' -ForegroundColor Cyan
    & $Python.Source -m venv $VenvRoot
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not create the project virtual environment.'
    }
}

Write-Host 'Installing the local print-finishing dependency (Pillow)...' -ForegroundColor Cyan
& $VenvPython -m pip install --upgrade -r (Join-Path $ProjectRoot 'requirements.txt')
if ($LASTEXITCODE -ne 0) {
    throw 'Pillow installation failed. Read the pip error above, then rerun setup.ps1.'
}

if ($Force -and (Test-Path -LiteralPath $EngineRoot)) {
    Remove-Item -LiteralPath $EngineRoot -Recurse -Force
}

if (-not (Test-Path -LiteralPath $EngineExe) -or -not (Test-Path -LiteralPath $ModelParam)) {
    if (Test-Path -LiteralPath $EngineRoot) {
        Remove-Item -LiteralPath $EngineRoot -Recurse -Force
    }
    Write-Host 'Downloading the official local Real-ESRGAN Vulkan engine and model bundle (~45 MB)...' -ForegroundColor Cyan
    Invoke-WebRequest -Uri $EngineUrl -OutFile $ArchivePath

    $Staging = Join-Path $ToolsRoot 'engine-staging'
    Remove-Item -LiteralPath $Staging -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $Staging | Out-Null
    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $Staging -Force

    $FoundEngine = Get-ChildItem -LiteralPath $Staging -Filter 'realesrgan-ncnn-vulkan.exe' -Recurse | Select-Object -First 1
    if (-not $FoundEngine) {
        throw 'The downloaded archive did not contain realesrgan-ncnn-vulkan.exe. The release layout may have changed.'
    }

    New-Item -ItemType Directory -Force -Path $EngineRoot | Out-Null
    Get-ChildItem -LiteralPath $FoundEngine.Directory.FullName -Force | Copy-Item -Destination $EngineRoot -Recurse -Force
    Remove-Item -LiteralPath $Staging -Recurse -Force
}

if (-not (Test-Path -LiteralPath $EngineExe) -or -not (Test-Path -LiteralPath $ModelParam)) {
    throw "Engine installation failed: the executable or general-image model is missing from $EngineRoot."
}

Write-Host "`nSetup complete." -ForegroundColor Green
Write-Host 'Run .\check-environment.ps1 next, then .\run-pipeline.ps1 -Input ''C:\path\to\image.jpg'''
