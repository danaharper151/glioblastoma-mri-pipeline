# Glioblastoma MRI Enhancement Pipeline

**Classical image processing pipeline for brain tumor MRI enhancement and brain extraction,
built in MATLAB for clinical radiation therapy planning applications.**

---

## Overview

This project implements a 12-stage image processing pipeline that enhances raw T1-contrast
MRI scans of glioblastoma multiforme (GBM) to improve tumor boundary visibility for
radiation therapy planning. Every stage uses classical digital image processing techniques:
no machine learning or neural networks.

Developed as the final project for COMP 510 (Advanced Image Analysis Techniques).

**Clinical motivation:** Radiation therapy for GBM requires precise manual contouring of
the tumor boundary on MRI. Raw scans suffer from low local contrast, intensity
inhomogeneity, and acquisition noise. When boundaries are unclear, oncologists must expand
the treatment margin, irradiating healthy brain tissue that could otherwise be spared.
This pipeline addresses each artifact systematically using spatial and frequency domain
processing, then performs brain extraction — the standard first step in clinical
neuroimaging workflows.

---

## Pipeline Stages

| Stage | Technique | Purpose |
|-------|-----------|---------|
| 1 | Preprocessing | Intensity normalization, grayscale, median denoising |
| 2 | CLAHE | Adaptive local contrast enhancement (8x8 tile grid, Rayleigh distribution) |
| 3 | Unsharp masking | Edge sharpening for tumor boundary delineation |
| 4 | High-emphasis filter | Frequency domain detail boost without anatomical loss |
| 5 | Homomorphic filter | Log-domain illumination/reflectance separation |
| 6 | Haze removal | Contrast stretch + gamma correction to restore dynamic range |
| 7 | Pseudocolor mapping | Hot colormap for clinical tissue intensity visualization |
| 8 | Brain extraction | Threshold segmentation to isolate brain parenchyma |
| 9 | Morphological ops | imclose + imopen + imfill to clean brain boundary mask |
| 10 | Connected components | Largest-region isolation of brain from background |
| 11 | Object measurement | Area, perimeter, centroid, bounding box, equivalent diameter |
| 12 | Compression analysis | JPEG Q=10/50/90 quality degradation via PSNR and SSIM |

---

## Results

Evaluated on 10 glioblastoma MRI scans from the Kaggle Brain Tumor MRI Dataset:

### Aggregate Metrics

| Metric | Value |
|--------|-------|
| **Avg ICR improvement** | **+59.3%** |
| Avg PSNR (CLAHE vs original) | 18.09 dB |
| Avg SSIM (CLAHE vs original) | 0.484 |
| JPEG Q90 PSNR range | 41.2 - 43.9 dB |
| JPEG Q90 SSIM range | 0.991 - 0.995 |
| Avg brain area | 122,536 px (range: 84,674 - 184,615 px) |

### Per-Image Results

| Image | PSNR (dB) | SSIM | ICR Before | ICR After | ICR Improvement |
|-------|-----------|------|------------|-----------|----------------|
| Te-gl_1.jpg   | 21.26 | 0.582 | 0.480 | 0.782 | +63.0% |
| Te-gl_115.jpg | 19.36 | 0.569 | 0.375 | 0.741 | +97.7% |
| Te-gl_17.jpg  | 15.10 | 0.472 | 0.563 | 0.818 | +45.4% |
| Te-gl_18.jpg  | 16.51 | 0.329 | 0.518 | 0.723 | +39.6% |
| Te-gl_60.jpg  | 16.32 | 0.456 | 0.495 | 0.786 | +58.5% |
| Te-gl_62.jpg  | 16.80 | 0.483 | 0.754 | 0.894 | +18.7% |
| Te-gl_84.jpg  | 19.62 | 0.542 | 0.509 | 0.838 | +64.5% |
| Te-gl_9.jpg   | 18.24 | 0.376 | 0.420 | 0.765 | +82.2% |
| Te-gl_90.jpg  | 16.72 | 0.588 | 0.502 | 0.808 | +61.0% |
| Te-no_400.jpg | 21.00 | 0.446 | 0.592 | 0.965 | +62.9% |

### Compression Analysis

All 10 enhanced images retain diagnostic quality at JPEG Q=90 (PSNR > 41 dB, SSIM > 0.99),
demonstrating suitability for clinical PACS archiving.

| JPEG Quality | PSNR Range | SSIM Range | Clinical Interpretation |
|-------------|------------|------------|------------------------|
| Q=10 | 26.6 - 29.5 dB | 0.812 - 0.926 | Significant loss |
| Q=50 | 32.8 - 35.8 dB | 0.934 - 0.981 | Acceptable quality |
| Q=90 | 41.2 - 43.9 dB | 0.991 - 0.995 | Near-lossless, diagnostic quality preserved |

---

## Metrics Explained

**ICR (Internal Contrast Ratio)** = `std(brain pixels) / mean(brain pixels)` within the
extracted brain mask. A higher ICR means white matter, gray matter, CSF, and tumor tissue
span a wider, more separated intensity range - directly reflecting diagnostic utility.
Computed on both original and enhanced images using the same mask for a fair comparison.

**PSNR** measures structural fidelity of the enhanced image versus the original.

**SSIM** measures perceptual similarity preserving luminance, contrast, and local structure.

---

## Dataset

**Kaggle Brain Tumor MRI Dataset** by Masoud Nickparvar
https://www.kaggle.com/datasets/masoudnickparvar/brain-tumor-mri-dataset

7,023 T1-weighted contrast-enhanced MRI scans across four classes. This project uses
10 images from Testing/glioma/ selected for varied noise levels and contrast conditions.

To replicate: download the dataset, copy images from Testing/glioma/ into data/input/.

---

## Requirements

- MATLAB R2019a or later
- Image Processing Toolbox

```matlab
license('test', 'Image_Toolbox')   % returns 1 if available
```

---

## Usage

```bash
git clone https://github.com/danaharper151/glioblastoma-mri-pipeline.git
cd glioblastoma-mri-pipeline
```

Place MRI images into data/input/, then in MATLAB:

```matlab
demo_single_image       % test on one image first — 8-panel stage visualization
brain_tumor_pipeline    % process all images in data/input/
view_results_tabbed     % interactive before/after viewer (run after pipeline)
```

---

## Output Files

| File | Description |
|------|-------------|
| data/output/*_enhanced.png | Final enhanced grayscale image |
| data/output/*_color.png | Hot pseudocolor visualization |
| data/figures/*_pipeline.png | 5-panel enhancement progression (300 DPI) |
| data/figures/*_segmentation.png | 4-panel brain extraction + measurements (300 DPI) |
| data/crops/*_brain_gray.png | Skull-stripped grayscale output |
| data/crops/*_brain_color.png | Skull-stripped pseudocolor output |
| data/output/metrics_summary.csv | Full quantitative results for all images |

---

## Project Structure

```
glioblastoma-mri-pipeline/
├── brain_tumor_pipeline.m    # Main pipeline — all 12 stages
├── demo_single_image.m       # Single image demo with 8-panel visualization
├── view_results_tabbed.m     # Interactive tabbed before/after viewer
├── README.md
├── data/
│   └── input/
│       └── .gitkeep
└── .gitignore
```

---

## Key Design Decisions

**Why CLAHE instead of global histogram equalization?**
CLAHE enhances each 8x8 tile independently, preventing bright skull from being
overexposed while the tumor interior gains contrast. Global HE cannot achieve this.

**Why a high-emphasis filter instead of a bandpass?**
A pure bandpass zeros out low-frequency content, which is the brain anatomy. An early
version of this pipeline used a bandpass and produced edge maps instead of enhanced images.
The high-emphasis formula H = a + b x H_butterworth_hp preserves all frequencies while
selectively boosting detail.

**Why segment on the original image for brain extraction?**
The enhanced image is globally brightened, making any threshold unstable. The original's
near-zero background makes brain/background separation reliable across all images.

**Why ICR instead of CNR?**
CNR requires knowing where the tumor is. ICR is location-independent and measures tissue
separability across the entire brain region, which is exactly what enhancement improves.

---

## Authors

Dana Harper & Arya Singh
Anthropic Claude Sonnet 4.6 - build assistance and debugging
COMP 510 - Advanced Image Analysis Techniques
Instructor: Dr. Vedang Chauhan | April 2026

---

## License

Code released under the MIT License. MRI images from the Kaggle Brain Tumor MRI Dataset
are subject to their original license. Images are not included in this repository.
