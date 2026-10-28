[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [Alias('Input')]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$InputPath,

    [ValidateRange(1, 3)]
    [int]$Passes = 2,

    [ValidateRange(32, 2048)]
    [int]$Tile = 128,

    [ValidateRange(1, 72)]
    [double]$PrintWidthIn = 18,

    [ValidateRange(1, 72)]
    [double]$PrintHeightIn = 24,

    [ValidateRange(72, 1200)]
    [int]$Ppi = 300,

    [ValidateRange(0, 0.25)]
    [double]$Grain = 0.12,

    # This PC exposes Intel as Vulkan GPU 0 and the 4 GB NVIDIA MX330 as GPU 1.
    [int]$GpuId = 1,

    [ValidateRange(70, 100)]
    [int]$JpegQuality = 95
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = $PSScriptRoot
$EngineRoot = Join-Path $ProjectRoot 'tools\engine'
$EngineExe = Join-Path $EngineRoot 'realesrgan-ncnn-vulkan.exe'
$FinalizeScript = Join-Path $ProjectRoot 'scripts\finalize_print.py'
$Python = Join-Path $ProjectRoot '.venv\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $EngineExe)) {
    throw 'The local AI engine is not installed. Run .\setup.ps1 first.'
}
if (-not (Test-Path -LiteralPath $Python)) {
    throw 'The project Python environment is missing. Run .\setup.ps1.'
}

$ResolvedInput = (Resolve-Path -LiteralPath $InputPath).Path
$InputStem = [IO.Path]::GetFileNameWithoutExtension($ResolvedInput)
$SafeStem = ($InputStem -replace '[^a-zA-Z0-9_-]', '_').Trim('_')
if ([string]::IsNullOrWhiteSpace($SafeStem)) { $SafeStem = 'image' }
$RunId = Get-Date -Format 'yyyyMMdd-HHmmss'

$CacheRoot = Join-Path $ProjectRoot (Join-Path 'cache' "$SafeStem-$RunId")
$OutputRoot = Join-Path $ProjectRoot 'outputs'
$ProofRoot = Join-Path $ProjectRoot 'proofs'
New-Item -ItemType Directory -Force -Path $CacheRoot, $OutputRoot, $ProofRoot | Out-Null

function Invoke-RealEsrganPass {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][int]$Stage
    )

    $Arguments = @(
        '-i', $Source,
        '-o', $Destination,
        '-n', 'realesrgan-x4plus',
        '-s', '4',
        '-t', $Tile,
        # The NCNN binary resolves its model directory relative to the executable.
        '-m', 'models',
        '-f', 'png',
        '-v'
    )
    if ($GpuId -ge 0) { $Arguments += @('-g', $GpuId) }

    Write-Host "`nAI pass $Stage of $Passes (tile: $Tile)..." -ForegroundColor Cyan
    & $EngineExe @Arguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Destination)) {
        throw "Real-ESRGAN failed on pass $Stage. Retry with -Tile 128, or run .\check-environment.ps1."
    }
}

function Invoke-AiPasses {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Label
    )

    $Result = $Source
    for ($Stage = 1; $Stage -le $Passes; $Stage++) {
        $Next = Join-Path $CacheRoot ("{0}-ai-pass-{1}-x{2}.png" -f $Label, $Stage, ([math]::Pow(4, $Stage)))
        Invoke-RealEsrganPass -Source $Result -Destination $Next -Stage $Stage
        $Result = $Next
    }
    return $Result
}

$AlphaTools = Join-Path $ProjectRoot 'scripts\alpha_tools.py'
$IsTransparent = (& $Python $AlphaTools probe --input $ResolvedInput) -eq 'transparent'

if ($IsTransparent) {
    # The engine and the JPEG finisher both drop transparency, so a transparent image is
    # split into an alpha mask (and colour, if it varies), upscaled, and recombined as a PNG.
    $TargetWidthPx = [int][math]::Round($PrintWidthIn * $Ppi)
    $OutputName = '{0}__{1}__realesrgan-{2}pass__{3}px_wide_transparent.png' -f $SafeStem, $RunId, $Passes, $TargetWidthPx
    $OutputPath = Join-Path $OutputRoot $OutputName
    $ManifestPath = Join-Path $OutputRoot ($OutputName -replace '\.png$', '.json')
    $MaskPath = Join-Path $CacheRoot 'alpha-mask.png'
    $ColorPath = Join-Path $CacheRoot 'color.png'

    Write-Host "`nTransparent image detected: upscaling the alpha mask separately." -ForegroundColor Cyan
    $ColorInfo = & $Python $AlphaTools split --input $ResolvedInput --mask $MaskPath --color $ColorPath
    if ($LASTEXITCODE -ne 0) { throw 'Could not split the transparent image.' }

    $MergeArgs = @('--output', $OutputPath, '--width', $TargetWidthPx, '--ppi', $Ppi)
    $MergeArgs += @('--mask', (Invoke-AiPasses -Source $MaskPath -Label 'alpha'))
    if ($ColorInfo -like 'solid *') {
        $MergeArgs += @('--solid') + ($ColorInfo -split ' ')[1..3]
    } else {
        $MergeArgs += @('--color', (Invoke-AiPasses -Source $ColorPath -Label 'color'))
    }

    & $Python $AlphaTools merge @MergeArgs
    if ($LASTEXITCODE -ne 0) {
        throw 'Transparent merge failed. The AI intermediates have been preserved in cache for inspection.'
    }

    [ordered]@{
        source = $ResolvedInput
        source_sha256 = (Get-FileHash -LiteralPath $ResolvedInput -Algorithm SHA256).Hash
        ai_engine = 'Real-ESRGAN ncnn Vulkan (official v0.2.5.0 bundle)'
        ai_model = 'realesrgan-x4plus'
        ai_passes = $Passes
        tile_size = $Tile
        gpu_id = if ($GpuId -ge 0) { $GpuId } else { 'auto' }
        transparent = $true
        colour = $ColorInfo
        final_width_px = $TargetWidthPx
        ppi = $Ppi
        output = $OutputPath
        cache = $CacheRoot
        created_local = (Get-Date).ToString('o')
        note = 'Height follows the source aspect ratio; -PrintHeightIn, -Grain and -JpegQuality are ignored for transparent images.'
    } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $ManifestPath -Encoding utf8

    Write-Host "`nComplete." -ForegroundColor Green
    Write-Host "Transparent PNG: $OutputPath"
    Write-Host "Manifest:        $ManifestPath"
    return
}

$Current = Invoke-AiPasses -Source $ResolvedInput -Label 'ai'

$TargetWidthPx = [int][math]::Round($PrintWidthIn * $Ppi)
$TargetHeightPx = [int][math]::Round($PrintHeightIn * $Ppi)
$OutputName = '{0}__{1}__realesrgan-{2}pass__{3}x{4}in_{5}ppi.jpg' -f $SafeStem, $RunId, $Passes, $PrintWidthIn, $PrintHeightIn, $Ppi
$OutputPath = Join-Path $OutputRoot $OutputName
$ProofPath = Join-Path $ProofRoot ($OutputName -replace '\.jpg$', '__proof.jpg')
$ManifestPath = Join-Path $OutputRoot ($OutputName -replace '\.jpg$', '.json')

Write-Host "`nFinishing exact print file: $TargetWidthPx x $TargetHeightPx px..." -ForegroundColor Cyan
& $Python $FinalizeScript `
    --input $Current `
    --output $OutputPath `
    --proof $ProofPath `
    --width $TargetWidthPx `
    --height $TargetHeightPx `
    --ppi $Ppi `
    --quality $JpegQuality `
    --grain $Grain
if ($LASTEXITCODE -ne 0) {
    throw 'Print finishing failed. The AI intermediate has been preserved in cache for inspection.'
}

$Manifest = [ordered]@{
    source = $ResolvedInput
    source_sha256 = (Get-FileHash -LiteralPath $ResolvedInput -Algorithm SHA256).Hash
    ai_engine = 'Real-ESRGAN ncnn Vulkan (official v0.2.5.0 bundle)'
    ai_model = 'realesrgan-x4plus'
    ai_passes = $Passes
    ai_scale_before_finish = "x$([math]::Pow(4, $Passes))"
    tile_size = $Tile
    gpu_id = if ($GpuId -ge 0) { $GpuId } else { 'auto' }
    final_dimensions_px = "$TargetWidthPx x $TargetHeightPx"
    print_dimensions_in = "$PrintWidthIn x $PrintHeightIn"
    ppi = $Ppi
    film_grain_strength = $Grain
    output = $OutputPath
    proof = $ProofPath
    cache = $CacheRoot
    created_local = (Get-Date).ToString('o')
    note = 'AI detail is model-inferred. Review facial features and text before printing.'
}
$Manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $ManifestPath -Encoding utf8

Write-Host "`nComplete." -ForegroundColor Green
Write-Host "Print file: $OutputPath"
Write-Host "Proof:      $ProofPath"
Write-Host "Manifest:   $ManifestPath"
