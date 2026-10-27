# AI Upscaler — local, print-oriented image restoration

This is a Windows-first local pipeline for genuine AI super-resolution using the official
`realesrgan-ncnn-vulkan` implementation of Real-ESRGAN. It runs locally on a Vulkan-capable
GPU; no image is uploaded to a service.

The pipeline intentionally separates two jobs:

1. **AI restoration / super-resolution** — one or two tiled Real-ESRGAN x4 passes.
2. **Print finishing** — exact pixel dimensions, 300 ppi metadata, sRGB JPEG export, and optional
   restrained analogue-style grain.

It does **not** use a face-restoration model by default. That is deliberate: face-restoration
models can change a person's identity. Real-ESRGAN can still infer texture, so inspect the
result at 100% before printing.

## What you need

- Windows 10 or 11.
- A Vulkan-capable GPU with a current driver. This PC's 4 GB NVIDIA GPU is supported by the
  conservative default tile size of 256.
- Python 3.10+ on PATH (already installed on this computer).
- Internet access only once, to download the open-source Real-ESRGAN engine and its model files.

## First-time setup

Open PowerShell in this folder and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1
```

The setup script downloads the official Windows bundle of `realesrgan-ncnn-vulkan` from
Real-ESRGAN release `v0.2.5.0` to `tools\engine` and installs Pillow for final print output. It does not install an
API key, cloud SDK, or telemetry service.

To verify the installation:

```powershell
.\check-environment.ps1
```

## Run the 18 × 24 poster workflow

For the supplied Kiss Land image, run this exact command:

```powershell
.\run-pipeline.ps1 `
  -Input 'C:\Users\anyework\Downloads\the weeknd kiss land.jpg' `
  -PrintWidthIn 18 `
  -PrintHeightIn 24 `
  -Ppi 300 `
  -Passes 2 `
  -Tile 128 `
  -Grain 0.12
```

The finished file lands in `outputs\` with a timestamped name ending in `__18x24in_300ppi.jpg`.
A smaller proof JPEG and a JSON manifest are written next to it. The original is never changed.

## Quality and memory controls

- `-Passes 2` performs two x4 neural passes (x16 total) before a high-quality downsize to the
  exact print target. This is appropriate for very small source images.
- `-Passes 1` is quicker and less likely to create invented texture, but cannot add as much detail.
- `-Tile 128` is the verified safe default for this 4 GB GPU. If it is stable but slow, try
  `-Tile 256`; if the engine reports an out-of-memory error, keep `-Tile 128`.
- `-Grain 0` disables the artistic grain entirely. Values around `0.08–0.16` are subtle; avoid
  going above `0.20` for a photographic print.
- The default uses Vulkan GPU `1`, which is this computer's NVIDIA MX330. Use `-GpuId 0` only
  if you intentionally want to run on the Intel adapter.

Example using a larger tile after a successful test:

```powershell
.\run-pipeline.ps1 -Input 'C:\path\to\photo.jpg' -Tile 256 -Passes 2
```

## Professional checks before ordering a print

1. Review the output and `proofs\` image at 100% for strange hair, eyes, earrings, text, or
   architecture. AI super-resolution is an interpretation, not recovery of hidden pixels.
2. Confirm the manifest reports the correct dimensions and `300` ppi.
3. Order one small proof first if color accuracy matters. Matte or lustre paper is usually more
   forgiving than high gloss for low-resolution source material.
4. Send the finished JPEG as-is to the printer. Do not let the print site apply a second
   auto-enhancement pass.

## Project layout

```text
ai-upscaler/
  setup.ps1                 # downloads local AI engine and installs finishing dependency
  run-pipeline.ps1          # one-command end-to-end workflow
  check-environment.ps1     # verifies the local setup and engine
  scripts/finalize_print.py # print dimensions, sRGB, grain, manifest
  tools/engine/             # downloaded binary and model files (ignored by Git)
  cache/                    # non-destructive neural-pass intermediates (ignored by Git)
  outputs/                  # final JPEG, proof, and manifest (ignored by Git)
```

## Provenance and licenses

- AI engine: [Real-ESRGAN ncnn Vulkan](https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan),
  the official NCNN/Vulkan implementation of Real-ESRGAN.
- Model choice: `realesrgan-x4plus`, the general-image model—not the anime model.
- The engine package retains its own license file after setup. Review its terms before
  redistributing the package or commercializing model outputs.

This wrapper adds orchestration and print finishing; it does not claim that AI-generated detail
is authentic source detail.
