% =========================================================================
%  BRAIN TUMOR MRI ENHANCEMENT PIPELINE  —  FINAL VERSION
%  COMP 510 | Digital Image Processing | Final Project
%
%  Dataset : Kaggle Brain Tumor MRI Dataset (Masoud Nickparvar)
%            kaggle.com/datasets/masoudnickparvar/brain-tumor-mri-dataset
%  Images  : 10 selected glioblastoma cases from Testing/glioma/
%
%  Clinical motivation:
%    Glioblastoma radiation therapy planning requires clear MRI images
%    for accurate tumor boundary delineation. Raw scans suffer from low
%    local contrast, intensity inhomogeneity, and acquisition noise.
%    This pipeline enhances image quality using classical techniques,
%    then performs brain extraction to isolate diagnostically relevant
%    tissue — the standard first step in clinical neuroimaging workflows.
%
%  Pipeline stages:
%    1.  Preprocessing          — normalize, grayscale, median denoise
%    2.  Spatial enhancement    — CLAHE, unsharp masking
%    3.  Frequency enhancement  — high-emphasis filter, homomorphic filter
%    4.  Haze removal           — contrast stretch, gamma correction
%    5.  Color processing       — pseudocolor map (hot colormap)
%    6.  Segmentation           — brain extraction via thresholding
%    7.  Morphological ops      — imclose + imopen to clean brain boundary
%    8.  Connected components   — isolate largest region (brain parenchyma)
%    9.  Object measurement     — area, perimeter, centroid, bounding box
%   10.  Object isolation       — skull-stripped enhanced image
%   11.  Compression analysis   — JPEG Q=10/50/90 vs lossless (PSNR, SSIM)
%   12.  Evaluation             — PSNR, SSIM, ICR per image + summary CSV
%
%  Note on metrics:
%    PSNR and SSIM are the primary quality metrics for an enhancement
%    pipeline — they measure structural fidelity across the whole image.
%    ICR (Internal Contrast Ratio) measures tissue contrast within the
%    brain mask: ICR = std(brain pixels) / mean(brain pixels). A higher
%    ICR means the brain's tissue types are more distinguishable from each
%    other, which is exactly what CLAHE and frequency enhancement improve.
%
%  Required toolbox : Image Processing Toolbox
%  Run              : press F5 or type brain_tumor_pipeline in Command Window
% =========================================================================

clc; clear; close all;

% =========================================================================
%  SECTION 0: CONFIGURATION
%  Edit paths here. All other behaviour is controlled by the parameters.
% =========================================================================

INPUT_DIR   = 'data/input';      % folder containing your 10 .jpg images
OUTPUT_DIR  = 'data/output';     % enhanced images saved here
FIGURES_DIR = 'data/figures';    % comparison + segmentation figures
CROPS_DIR   = 'data/crops';      % skull-stripped isolated brain images

% --- Enhancement toggles (set false to disable a stage for comparison) ---
DO_CLAHE        = true;
DO_UNSHARP      = true;
DO_HIGHEMPHASIS = true;
DO_HOMOMORPHIC  = true;

% --- CLAHE ---
% ClipLimit: 0.005 = subtle, 0.01 = balanced, 0.02 = aggressive
% NumTiles:  [8 8] divides image into 64 local regions for adaptation
CLAHE_CLIP  = 0.015;
CLAHE_TILES = [8 8];

% --- Unsharp masking ---
% Radius:  size of the blur kernel used to build the sharpening mask
% Amount:  strength of sharpening boost (keep <= 0.8 for MRI)
% Thresh:  minimum edge contrast to sharpen (prevents noise amplification)
UNSHARP_RADIUS = 2.5;
UNSHARP_AMOUNT = 0.85;
UNSHARP_THRESH = 0.02;

% --- High-frequency emphasis filter ---
%   H(u,v) = HE_A  +  HE_B * H_butterworth_highpass(u,v)
%   HE_A : base gain applied to ALL frequencies (keeps anatomy intact)
%   HE_B : additional gain for HIGH frequencies (boosts edges/detail)
%   HE_D0: normalized cutoff — above this frequency, boosting kicks in
HE_A  = 0.5;
HE_B  = 1.5;
HE_D0 = 0.08;
HE_N  = 2;

% --- Homomorphic filter ---
%   Separates illumination (low freq) from reflectance/detail (high freq)
%   in log space. gL < 1 compresses illumination; gH > 1 boosts detail.
HMF_GL     = 0.6;
HMF_GH     = 1.5;
HMF_CUTOFF = 0.15;
HMF_SHARP  = 1.5;

% --- Frequency blend weights ---
BLEND_HMF = 0.6;   % weight for homomorphic result
BLEND_HE  = 0.4;   % weight for high-emphasis result (must sum to ~1)

% --- Haze removal ---
% After blending, a gray haze lifts the black point. imadjust re-stretches
% to the actual content range; gamma > 1 darkens midtones back toward black.
GAMMA       = 1.85;
STRETCH_LOW = 0.02;
STRETCH_HI  = 0.98;

% --- Brain extraction ---
% BRAIN_THRESH: pixels above this value are considered non-background.
% Lower values include more tissue; raise slightly if noisy backgrounds
% are being included. Tested range: 0.05 – 0.15.
BRAIN_THRESH   = 0.08;
MORPH_CLOSE_R  = 8;    % imclose radius — fills gaps in brain boundary
MORPH_OPEN_R   = 3;    % imopen radius  — removes small background noise

% --- Compression quality levels ---
JPEG_QUALITIES = [10, 50, 90];

% =========================================================================
%  SECTION 1: SETUP
% =========================================================================

for d = {OUTPUT_DIR, FIGURES_DIR, CROPS_DIR}
    if ~exist(d{1}, 'dir'), mkdir(d{1}); end
end

imageFiles = [dir(fullfile(INPUT_DIR, '*.jpg'));
              dir(fullfile(INPUT_DIR, '*.jpeg'));
              dir(fullfile(INPUT_DIR, '*.png'))];

if isempty(imageFiles)
    error('No images found in "%s".\nCheck that INPUT_DIR path is correct.', ...
          INPUT_DIR);
end

nImages = numel(imageFiles);
fprintf('Found %d image(s) in: %s\n\n', nImages, INPUT_DIR);

% Column names for the output metrics CSV
metricVars = {'Filename', ...
    'PSNR_dB', 'SSIM', ...
    'ICR_Original', 'ICR_Enhanced', 'ICR_Improvement_pct', ...
    'Brain_Area_px', 'Brain_Perimeter_px', ...
    'Brain_Centroid_X', 'Brain_Centroid_Y', ...
    'Brain_BBox_X', 'Brain_BBox_Y', 'Brain_BBox_W', 'Brain_BBox_H', ...
    'Brain_EqDiameter_px', ...
    'PSNR_JPEG_Q10', 'PSNR_JPEG_Q50', 'PSNR_JPEG_Q90', ...
    'SSIM_JPEG_Q10', 'SSIM_JPEG_Q50', 'SSIM_JPEG_Q90'};

metricsTable = cell(nImages, numel(metricVars));

% =========================================================================
%  SECTION 2: MAIN PROCESSING LOOP
% =========================================================================

for i = 1:nImages

    fname = imageFiles(i).name;
    fpath = fullfile(INPUT_DIR, fname);
    [~, fbase, ~] = fileparts(fname);
    fprintf('[%02d/%02d]  %s\n', i, nImages, fname);

    % =====================================================================
    %  LOAD IMAGE
    %  The Kaggle dataset stores grayscale MRI as 3-channel JPEG. We
    %  collapse to single-channel and convert to double [0,1] for all
    %  arithmetic operations. im2double preserves precision; uint8 arithmetic
    %  would introduce rounding errors at each pipeline stage.
    % =====================================================================

    raw = imread(fpath);
    if size(raw, 3) == 3
        raw = rgb2gray(raw);
    end
    raw      = im2double(raw);
    original = rescale(raw);
    [rows, cols] = size(original);

    % =====================================================================
    %  STAGE 1 — PREPROCESSING
    %  Normalize intensity to the full [0,1] range: some MRI JPEG exports
    %  have a narrow window (e.g., [0.1, 0.8]) that wastes dynamic range.
    %  Median filter suppresses salt-and-pepper noise from JPEG compression
    %  artifacts using a 3x3 neighborhood — preserves edges better than
    %  Gaussian blur at this scale.
    % =====================================================================

    img = rescale(raw);
    img = medfilt2(img, [3 3]);

    % =====================================================================
    %  STAGE 2 — SPATIAL DOMAIN ENHANCEMENT
    % =====================================================================

    % 2a — CLAHE (Contrast-Limited Adaptive Histogram Equalization)
    %   Operates tile-by-tile (8x8 grid) rather than globally, so dark
    %   tumor interiors gain contrast without overexposing the bright skull.
    %   Rayleigh distribution matches the right-skewed histogram of MRI data
    %   better than the default 'uniform' option.
    if DO_CLAHE
        img_clahe = adapthisteq(img, ...
            'ClipLimit',    CLAHE_CLIP,  ...
            'NumTiles',     CLAHE_TILES, ...
            'Distribution', 'rayleigh',  ...
            'Alpha',        0.4);
    else
        img_clahe = img;
    end

    % 2b — Unsharp masking
    %   Amplifies high-frequency edge content by subtracting a blurred copy
    %   of the image. Sharpens tumor boundaries and internal tissue structure.
    %   Threshold prevents the filter from amplifying noise in flat regions.
    if DO_UNSHARP
        img_sharp = imsharpen(img_clahe, ...
            'Radius',    UNSHARP_RADIUS, ...
            'Amount',    UNSHARP_AMOUNT, ...
            'Threshold', UNSHARP_THRESH);
    else
        img_sharp = img_clahe;
    end

    spatial_result = img_sharp;

    % =====================================================================
    %  STAGE 3 — FREQUENCY DOMAIN ENHANCEMENT
    %  Both filters are applied in the 2D DFT domain using fft2/ifft2.
    %  fftshift re-centers the spectrum so the DC component is at (0,0)
    %  and frequency distance D can be computed as a simple Euclidean norm.
    % =====================================================================

    [U, V] = meshgrid(1:cols, 1:rows);
    U_n = (U - cols/2) / cols;      % normalize frequency to [-0.5, 0.5]
    V_n = (V - rows/2) / rows;
    D   = sqrt(U_n.^2 + V_n.^2);   % radial frequency from DC

    % 3a — High-frequency emphasis filter
    %   H(u,v) = HE_A + HE_B * H_butterworth_hp(u,v)
    %   Unlike a pure bandpass, this never zeros out any frequency component.
    %   HE_A preserves all anatomy; HE_B selectively boosts fine detail.
    if DO_HIGHEMPHASIS
        H_HP       = 1 ./ (1 + (HE_D0 ./ (D + eps)).^(2*HE_N));
        H_emph     = HE_A + HE_B .* H_HP;
        img_he     = real(ifft2(ifftshift( ...
                         fftshift(fft2(img_sharp)) .* H_emph)));
        img_he     = rescale(img_he);
    else
        img_he = img_sharp;
    end

    % 3b — Homomorphic filter
    %   MRI intensity = illumination x reflectance (multiplicative model).
    %   Log transform converts this to additive: log(I) = log(L) + log(R).
    %   In log-frequency space: illumination -> low freqs, detail -> high freqs.
    %   gL < 1 suppresses slow illumination variation across the image field.
    %   gH > 1 amplifies local tissue reflectance (the clinically useful detail).
    %   Blended 60/40 with spatial result so anatomy is never lost.
    if DO_HOMOMORPHIC
        D_sq   = U_n.^2 + V_n.^2;
        H_hm   = HMF_GL + (HMF_GH - HMF_GL) .* ...
                 (1 - exp(-HMF_SHARP .* D_sq ./ (HMF_CUTOFF^2 + eps)));
        img_hm = rescale(exp(real(ifft2(ifftshift( ...
                     fftshift(fft2(log(img_clahe + 1e-6))) .* H_hm)))));
        img_hm_blended = rescale(0.6 .* img_sharp + 0.4 .* img_hm);
    else
        img_hm_blended = img_sharp;
    end

    % Combine frequency results, then Wiener filter to suppress ringing.
    % Ringing (Gibbs artifact) can appear after frequency-domain filtering;
    % wiener2 adaptively smooths regions where noise exceeds signal.
    freq_result = rescale(BLEND_HMF .* img_hm_blended + BLEND_HE .* img_he);
    freq_result = rescale(wiener2(freq_result, [3 3]));

    % =====================================================================
    %  STAGE 4 — HAZE REMOVAL
    %  Blending in Stage 3 lifts the black point, producing a gray haze.
    %  stretchlim finds the 1st-99th percentile of actual pixel values;
    %  imadjust remaps that range to [0,1], clipping the lifted black point
    %  back to true black. Gamma > 1 then darkens midtones without affecting
    %  pure blacks or whites, restoring the deep background of MRI images.
    % =====================================================================

    low_high = stretchlim(freq_result, [STRETCH_LOW STRETCH_HI]);
    final    = imadjust(freq_result, low_high, [0 1]);
    final    = rescale(final .^ GAMMA);

    % =====================================================================
    %  STAGE 5 — COLOR IMAGE PROCESSING
    %  Apply the 'hot' pseudocolor map to the enhanced grayscale image.
    %  The hot colormap (black -> red -> yellow -> white) maps intensity to
    %  color in a way that mirrors clinical T1-contrast windowing conventions:
    %  dark background tissue appears near-black/dark-red; the bright
    %  gadolinium-enhancing rim of GBM tumors appears yellow-white.
    %  Saved as a separate color output — the grayscale pipeline is unchanged.
    % =====================================================================

    cmap      = hot(256);
    img_color = ind2rgb(im2uint8(final), cmap);
    imwrite(img_color, fullfile(OUTPUT_DIR, [fbase '_color.png']));

    % =====================================================================
    %  STAGE 6 — SEGMENTATION: BRAIN EXTRACTION
    %  Brain extraction (skull stripping) is the standard first step in
    %  clinical neuroimaging pipelines. It isolates brain parenchyma from
    %  the black background and non-brain structures so that all downstream
    %  measurements apply only to diagnostically relevant tissue.
    %
    %  We segment on the ORIGINAL image, not the enhanced one. The original
    %  has a reliable, stable background (near-zero black) making the
    %  brain/background boundary easy to threshold. The enhanced image has
    %  been brightness-adjusted and would give an unstable threshold.
    %
    %  Method: threshold at BRAIN_THRESH to find all non-background pixels,
    %  then use morphological operations and connected component analysis
    %  to isolate the clean brain region.
    % =====================================================================

    % Threshold: any pixel brighter than BRAIN_THRESH is brain tissue
    brain_raw = original > BRAIN_THRESH;

    % =====================================================================
    %  STAGE 7 — MORPHOLOGICAL PROCESSING
    %  The raw threshold mask has two common artifacts:
    %    (a) Internal holes — dark ventricles and CSF spaces inside the brain
    %        fall below BRAIN_THRESH and appear as holes in the mask.
    %        imclose with a large disk fills these cavities so the mask
    %        represents the full brain volume continuously.
    %    (b) External noise — small bright specks outside the brain (JPEG
    %        compression artifacts, bright neck tissue at image edges) create
    %        small isolated blobs. imopen removes components smaller than
    %        the structuring element, leaving only substantial regions.
    %  imfill('holes') does a final pass to catch any remaining interior gaps.
    % =====================================================================

    se_close  = strel('disk', MORPH_CLOSE_R);
    se_open   = strel('disk', MORPH_OPEN_R);

    brain_mask = imclose(brain_raw,  se_close);   % fill ventricles/CSF holes
    brain_mask = imopen(brain_mask,  se_open);    % remove exterior noise blobs
    brain_mask = imfill(brain_mask, 'holes');      % final interior hole fill

    % =====================================================================
    %  STAGE 8 — CONNECTED COMPONENT ANALYSIS
    %  After morphological cleanup, the binary mask may still contain
    %  multiple disconnected regions (e.g., bright neck tissue, scalp
    %  fragments at image borders). bwconncomp identifies all distinct
    %  connected regions; we keep only the LARGEST, which is the brain.
    %  This is robust because the brain is always the dominant structure.
    % =====================================================================

    cc = bwconncomp(brain_mask, 8);   % 8-connectivity includes diagonals

    if cc.NumObjects == 0
        % Fallback: if extraction fails entirely, use the raw threshold mask
        warning('Image %s: brain extraction found no components. Using raw threshold.', fname);
        brain_mask_clean = brain_raw;
    else
        % Find the largest connected component by pixel count
        region_sizes     = cellfun(@numel, cc.PixelIdxList);
        [~, largest_idx] = max(region_sizes);

        % Build a clean mask containing only the largest region (the brain)
        brain_mask_clean = false(rows, cols);
        brain_mask_clean(cc.PixelIdxList{largest_idx}) = true;
    end

    % =====================================================================
    %  STAGE 9 — OBJECT PARAMETER MEASUREMENT
    %  regionprops extracts geometric properties of the brain region.
    %  These are the same measurements used in clinical neuroimaging to
    %  characterize brain volume and position for treatment planning.
    %
    %  All measurements are in pixels. To convert to mm^2 or mm, multiply
    %  by the scanner's pixel spacing (typically 0.5-1.0 mm/pixel for MRI),
    %  which would be available in the original DICOM metadata.
    % =====================================================================

    brain_stats = regionprops(brain_mask_clean, ...
                      'Area', 'Perimeter', 'Centroid', ...
                      'BoundingBox', 'EquivDiameter');

    if ~isempty(brain_stats)
        % Take stats from the single brain region
        b_area   = brain_stats(1).Area;
        b_perim  = brain_stats(1).Perimeter;
        b_cent   = brain_stats(1).Centroid;
        b_bbox   = brain_stats(1).BoundingBox;
        b_eqdiam = brain_stats(1).EquivDiameter;
    else
        b_area = 0; b_perim = 0; b_cent = [0 0];
        b_bbox = [0 0 0 0]; b_eqdiam = 0;
    end

    fprintf('    Brain: area=%d px | perim=%.0f px | eq.diam=%.1f px\n', ...
            round(b_area), b_perim, b_eqdiam);

    % =====================================================================
    %  STAGE 10 — OBJECT OF INTEREST ISOLATION
    %  Apply the brain mask to the enhanced image to produce a skull-stripped
    %  output: non-brain pixels are set to black (zero). This is the standard
    %  "skull-stripped" image used in clinical radiation therapy planning
    %  software to focus dose calculations on brain tissue only.
    %  Both grayscale and color versions are saved.
    % =====================================================================

    % Skull-strip: zero out everything outside the brain mask
    final_stripped       = final .* double(brain_mask_clean);
    img_color_stripped   = img_color;
    for ch = 1:3
        layer = img_color_stripped(:,:,ch);
        layer(~brain_mask_clean) = 0;
        img_color_stripped(:,:,ch) = layer;
    end

    imwrite(final_stripped,     fullfile(CROPS_DIR, [fbase '_brain_gray.png']));
    imwrite(img_color_stripped, fullfile(CROPS_DIR, [fbase '_brain_color.png']));

    % =====================================================================
    %  STAGE 11 — COMPRESSION & QUALITY ANALYSIS
    %  Clinical images are stored in PACS (Picture Archiving and
    %  Communication Systems) which often apply JPEG compression to save
    %  storage. This stage demonstrates that our enhanced images retain
    %  diagnostic quality across a range of compression levels.
    %  Procedure: write as JPEG at Q=10/50/90, read back, compute PSNR
    %  and SSIM vs. the lossless PNG. Temp files are deleted immediately.
    % =====================================================================

    psnr_jpeg = zeros(1, numel(JPEG_QUALITIES));
    ssim_jpeg = zeros(1, numel(JPEG_QUALITIES));

    for q = 1:numel(JPEG_QUALITIES)
        qlevel  = JPEG_QUALITIES(q);
        tmpFile = fullfile(OUTPUT_DIR, sprintf('%s_tmp_q%d.jpg', fbase, qlevel));
        imwrite(final, tmpFile, 'jpg', 'Quality', qlevel);
        comp    = im2double(imread(tmpFile));
        comp    = comp(1:rows, 1:cols);   % guard against 1-px decode variance
        psnr_jpeg(q) = psnr(comp, final);
        ssim_jpeg(q) = ssim(comp, final);
        delete(tmpFile);
    end

    fprintf('    Compression — Q10: %.1fdB/%.3f | Q50: %.1fdB/%.3f | Q90: %.1fdB/%.3f\n', ...
            psnr_jpeg(1), ssim_jpeg(1), psnr_jpeg(2), ssim_jpeg(2), ...
            psnr_jpeg(3), ssim_jpeg(3));

    % =====================================================================
    %  STAGE 12 — IMAGE QUALITY EVALUATION
    %
    %  PSNR and SSIM: compare the CLAHE-enhanced image against the original.
    %  These are the standard metrics for image enhancement pipelines —
    %  they measure how much structural quality was gained across the
    %  whole image, not just between two fixed sample regions.
    %
    %  ICR (Internal Contrast Ratio): measures tissue contrast WITHIN the
    %  brain mask. Defined as std(brain_pixels) / mean(brain_pixels).
    %  A higher ICR means the brain's tissue types span a wider, more
    %  separated intensity range — i.e., white matter, gray matter, CSF,
    %  and tumor are more visually distinguishable from each other.
    %  This directly reflects what CLAHE and frequency enhancement improve.
    %  Unlike CNR, ICR does not require knowing where the tumor is.
    % =====================================================================

    psnr_val = psnr(img_clahe, original);
    ssim_val = ssim(img_clahe, original);

    % ICR on the original image (within brain mask only)
    orig_brain_px   = original(brain_mask_clean);
    icr_orig        = std(orig_brain_px) / (mean(orig_brain_px) + eps);

    % ICR on the final enhanced image (same mask, fair comparison)
    final_brain_px  = final(brain_mask_clean);
    icr_final       = std(final_brain_px) / (mean(final_brain_px) + eps);

    icr_improvement = 100 * (icr_final - icr_orig) / (icr_orig + eps);

    fprintf('    Quality — PSNR: %.2f dB | SSIM: %.4f | ICR: %.3f -> %.3f (%+.1f%%)\n', ...
            psnr_val, ssim_val, icr_orig, icr_final, icr_improvement);

    % Store all metrics
    metricsTable(i,:) = { fname, ...
        psnr_val,       ssim_val, ...
        icr_orig,       icr_final,     icr_improvement, ...
        round(b_area),  b_perim, ...
        b_cent(1),      b_cent(2), ...
        b_bbox(1),      b_bbox(2),     b_bbox(3), b_bbox(4), ...
        b_eqdiam, ...
        psnr_jpeg(1),   psnr_jpeg(2),  psnr_jpeg(3), ...
        ssim_jpeg(1),   ssim_jpeg(2),  ssim_jpeg(3) };

    % =====================================================================
    %  SAVE ALL OUTPUT FILES
    % =====================================================================

    % Enhanced grayscale image
    imwrite(final, fullfile(OUTPUT_DIR, [fbase '_enhanced.png']));

    % 5-panel pipeline comparison figure
    save_pipeline_figure(original, img_clahe, spatial_result, ...
                         freq_result, final, fname, FIGURES_DIR, fbase);

    % 4-panel segmentation + measurement figure
    save_brain_figure(original, final, img_color, ...
                      brain_mask_clean, b_bbox, b_cent, ...
                      b_area, b_eqdiam, fname, FIGURES_DIR, fbase);

    fprintf('\n');

end % end image loop

% =========================================================================
%  SECTION 3: SUMMARY
% =========================================================================

T = cell2table(metricsTable, 'VariableNames', metricVars);
writetable(T, fullfile(OUTPUT_DIR, 'metrics_summary.csv'));

psnr_all = cell2mat(metricsTable(:, strcmp(metricVars,'PSNR_dB')));
ssim_all = cell2mat(metricsTable(:, strcmp(metricVars,'SSIM')));
icr_imp  = cell2mat(metricsTable(:, strcmp(metricVars,'ICR_Improvement_pct')));
area_all = cell2mat(metricsTable(:, strcmp(metricVars,'Brain_Area_px')));

fprintf('=================================================================\n');
fprintf('  PIPELINE COMPLETE — %d images processed\n', nImages);
fprintf('=================================================================\n');
fprintf('  Avg PSNR             : %.2f dB\n',  mean(psnr_all));
fprintf('  Avg SSIM             : %.4f\n',     mean(ssim_all));
fprintf('  Avg ICR improvement  : %+.1f%%\n', mean(icr_imp));
fprintf('  Avg brain area       : %.0f px  (range: %d – %d)\n', ...
        mean(area_all), min(area_all), max(area_all));
fprintf('  Enhanced images      : %s\n', OUTPUT_DIR);
fprintf('  Skull-stripped crops : %s\n', CROPS_DIR);
fprintf('  Figures              : %s\n', FIGURES_DIR);
fprintf('  Metrics CSV          : %s/metrics_summary.csv\n', OUTPUT_DIR);
fprintf('=================================================================\n');


% =========================================================================
%  LOCAL HELPER FUNCTIONS
% =========================================================================

% -------------------------------------------------------------------------
function save_pipeline_figure(orig, clahe, spatial, freq, final, ...
                               title_str, out_dir, base)
% SAVE_PIPELINE_FIGURE  5-panel left-to-right enhancement progression.
%   Uses print() at 300 DPI instead of saveas() to avoid the low-resolution
%   pixelation that saveas produces in MATLAB Online (72 DPI screen capture).
%   Paper units decouple figure size from screen resolution entirely.

    fig = figure('Visible','off');
    set(fig, 'Units','inches', 'Position',[0 0 20 4.5]);   % width x height in inches
    set(fig, 'PaperUnits','inches', 'PaperSize',[20 4.5], ...
             'PaperPosition',[0 0 20 4.5]);

    data   = {orig,  clahe,  spatial,           freq,               final};
    labels = {'Original', 'After CLAHE', 'Spatial (Unsharp)', ...
              'Frequency Domain', 'Final Enhanced'};

    for k = 1:5
        ax = subplot(1,5,k);
        imshow(data{k}, [], 'Parent', ax);
        title(labels{k}, 'FontWeight','bold', 'FontSize',11);
    end
    sgtitle(['Pipeline: ' strrep(title_str,'_','\_')], ...
            'FontSize',13, 'FontWeight','bold');

    outFile = fullfile(out_dir, [base '_pipeline.png']);
    print(fig, outFile, '-dpng', '-r300');   % 300 DPI — crisp on screen and in slides
    close(fig);
end

% -------------------------------------------------------------------------
function save_brain_figure(orig, enhanced, color_img, brain_mask, ...
                            bbox, centroid, area, eq_diam, ...
                            title_str, out_dir, base)
% SAVE_BRAIN_FIGURE  4-panel segmentation and measurement figure.
%   Uses print() at 300 DPI — same reason as save_pipeline_figure above.

    fig = figure('Visible','off');
    set(fig, 'Units','inches', 'Position',[0 0 18 5]);
    set(fig, 'PaperUnits','inches', 'PaperSize',[18 5], ...
             'PaperPosition',[0 0 18 5]);

    % Panel 1 — Pseudocolor enhanced image
    subplot(1,4,1);
    imshow(color_img);
    title('Color-Enhanced (hot map)', 'FontWeight','bold', 'FontSize',11);
    xlabel('Dark red = tissue   Yellow/white = bright regions', 'FontSize',9);

    % Panel 2 — Enhanced image with brain boundary overlay
    subplot(1,4,2);
    imshow(enhanced, []);
    hold on;
    boundary = bwperim(brain_mask);
    [by, bx] = find(boundary);
    plot(bx, by, 'g.', 'MarkerSize', 1);
    plot(centroid(1), centroid(2), 'r+', 'MarkerSize',14, 'LineWidth',2);
    if any(bbox > 0)
        rectangle('Position', bbox, 'EdgeColor','y', 'LineWidth',1.5);
    end
    hold off;
    title('Brain Extraction Overlay', 'FontWeight','bold', 'FontSize',11);
    xlabel('Green = boundary   Red+ = centroid   Yellow = bbox', 'FontSize',9);

    % Panel 3 — Clean binary brain mask
    subplot(1,4,3);
    imshow(brain_mask);
    title('Brain Mask (post-morph)', 'FontWeight','bold', 'FontSize',11);
    xlabel('imclose + imopen + imfill + largest CC', 'FontSize',9);

    % Panel 4 — Original with measurements annotated
    subplot(1,4,4);
    imshow(orig, []);
    title('Original + Measurements', 'FontWeight','bold', 'FontSize',11);
    xlabel(sprintf('Brain area: %d px   Eq. diameter: %.1f px', ...
                   round(area), eq_diam), 'FontSize',9);

    sgtitle(['Segmentation: ' strrep(title_str,'_','\_')], ...
            'FontSize',13, 'FontWeight','bold');

    outFile = fullfile(out_dir, [base '_segmentation.png']);
    print(fig, outFile, '-dpng', '-r300');
    close(fig);
end

