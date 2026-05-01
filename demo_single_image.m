% =========================================================================
%  SINGLE IMAGE DEMO
%  COMP 510 | Digital Image Processing | Final Project
%
%  Run this script first to test the pipeline on one image before
%  processing the full dataset. Shows all processing stages side by side
%  in an 8-panel figure so you can inspect each step individually.
%
%  Usage:
%    1. Edit IMAGE_PATH below to point to any image in your data/input/ folder
%    2. Press F5 or click Run
%    3. Inspect the 8-panel figure — each panel is one pipeline stage
%    4. Check the Command Window for PSNR, SSIM, and ICR metrics
%
%  Required toolbox: Image Processing Toolbox
% =========================================================================

clc; clear; close all;

% -------------------------------------------------------------------------
%  CONFIGURATION — edit this line only
% -------------------------------------------------------------------------
IMAGE_PATH = 'data/input/Te-gl_1.jpg';    % <-- change to your image filename

% =========================================================================
%  PARAMETERS  (must match brain_tumor_pipeline.m)
% =========================================================================
CLAHE_CLIP     = 0.015;
CLAHE_TILES    = [8 8];
UNSHARP_RADIUS = 2.5;
UNSHARP_AMOUNT = 0.85;
UNSHARP_THRESH = 0.02;
HE_A  = 0.5;   HE_B  = 1.5;
HE_D0 = 0.08;  HE_N  = 2;
HMF_GL = 0.6;  HMF_GH = 1.5;
HMF_CUTOFF = 0.15; HMF_SHARP = 1.5;
BLEND_HMF  = 0.6;  BLEND_HE  = 0.4;
GAMMA       = 1.85;
STRETCH_LOW = 0.02;
STRETCH_HI  = 0.98;
BRAIN_THRESH  = 0.08;
MORPH_CLOSE_R = 8;
MORPH_OPEN_R  = 3;

% =========================================================================
%  LOAD IMAGE
% =========================================================================
raw = imread(IMAGE_PATH);
if size(raw, 3) == 3
    raw = rgb2gray(raw);
end
raw      = im2double(raw);
original = rescale(raw);
[rows, cols] = size(original);

% =========================================================================
%  PROCESSING — all 12 stages
% =========================================================================

% Stage 1 — Preprocessing
img = rescale(raw);
img = medfilt2(img, [3 3]);

% Stage 2 — CLAHE + unsharp
img_clahe = adapthisteq(img, ...
    'ClipLimit', CLAHE_CLIP, 'NumTiles', CLAHE_TILES, ...
    'Distribution', 'rayleigh', 'Alpha', 0.4);
img_sharp = imsharpen(img_clahe, ...
    'Radius', UNSHARP_RADIUS, 'Amount', UNSHARP_AMOUNT, 'Threshold', UNSHARP_THRESH);

% Stage 3 — Frequency domain
[U, V] = meshgrid(1:cols, 1:rows);
U_n = (U - cols/2) / cols;
V_n = (V - rows/2) / rows;
D   = sqrt(U_n.^2 + V_n.^2);

H_HP   = 1 ./ (1 + (HE_D0 ./ (D + eps)).^(2*HE_N));
H_emph = HE_A + HE_B .* H_HP;
img_he = real(ifft2(ifftshift(fftshift(fft2(img_sharp)) .* H_emph)));
img_he = rescale(img_he);

D_sq   = U_n.^2 + V_n.^2;
H_hm   = HMF_GL + (HMF_GH - HMF_GL) .* ...
         (1 - exp(-HMF_SHARP .* D_sq ./ (HMF_CUTOFF^2 + eps)));
img_hm = rescale(exp(real(ifft2(ifftshift( ...
             fftshift(fft2(log(img_clahe + 1e-6))) .* H_hm)))));
img_hm_blended = rescale(0.6 .* img_sharp + 0.4 .* img_hm);

freq_result = rescale(BLEND_HMF .* img_hm_blended + BLEND_HE .* img_he);
freq_result = rescale(wiener2(freq_result, [3 3]));

% Stage 4 — Haze removal
low_high = stretchlim(freq_result, [STRETCH_LOW STRETCH_HI]);
final    = imadjust(freq_result, low_high, [0 1]);
final    = rescale(final .^ GAMMA);

% Stage 5 — Pseudocolor
img_color = ind2rgb(im2uint8(final), hot(256));

% Stages 6-8 — Brain extraction
brain_raw  = original > BRAIN_THRESH;
se_close   = strel('disk', MORPH_CLOSE_R);
se_open    = strel('disk', MORPH_OPEN_R);
brain_mask = imclose(brain_raw,  se_close);
brain_mask = imopen(brain_mask,  se_open);
brain_mask = imfill(brain_mask, 'holes');

cc = bwconncomp(brain_mask, 8);
if cc.NumObjects > 0
    [~, idx] = max(cellfun(@numel, cc.PixelIdxList));
    brain_mask_clean = false(rows, cols);
    brain_mask_clean(cc.PixelIdxList{idx}) = true;
else
    brain_mask_clean = brain_raw;
end

% Stage 9 — Measurements
stats  = regionprops(brain_mask_clean, 'Area','Perimeter','Centroid', ...
                     'BoundingBox','EquivDiameter');
b_area   = stats(1).Area;
b_perim  = stats(1).Perimeter;
b_eqdiam = stats(1).EquivDiameter;

% Stage 12 — Metrics
psnr_val = psnr(img_clahe, original);
ssim_val = ssim(img_clahe, original);
icr_orig = std(original(brain_mask_clean)) / (mean(original(brain_mask_clean)) + eps);
icr_final= std(final(brain_mask_clean))    / (mean(final(brain_mask_clean))    + eps);

% =========================================================================
%  8-PANEL FIGURE
% =========================================================================
fig = figure('Name','Single Image Demo — All Pipeline Stages', ...
             'Position',[50 50 1600 800]);

subplot(2,4,1); imshow(original,    []); title('1. Original',           'FontWeight','bold');
subplot(2,4,2); imshow(img_clahe,   []); title('2. CLAHE',              'FontWeight','bold');
subplot(2,4,3); imshow(img_sharp,   []); title('3. Unsharp Mask',       'FontWeight','bold');
subplot(2,4,4); imshow(freq_result, []); title('4. Frequency Domain',   'FontWeight','bold');
subplot(2,4,5); imshow(final,       []); title('5. Final Enhanced',     'FontWeight','bold', 'Color',[0 0.5 0]);
subplot(2,4,6); imshow(img_color);       title('6. Pseudocolor (hot)',  'FontWeight','bold');
subplot(2,4,7); imshow(brain_mask_clean);title('7. Brain Mask',         'FontWeight','bold');

subplot(2,4,8);
imshow(final, []);
hold on;
boundary = bwperim(brain_mask_clean);
[by, bx] = find(boundary);
plot(bx, by, 'g.', 'MarkerSize',1);
hold off;
title('8. Brain Extraction Overlay', 'FontWeight','bold');

sgtitle(sprintf('Pipeline Demo: %s', IMAGE_PATH), 'FontSize',13, 'FontWeight','bold');

% =========================================================================
%  METRICS OUTPUT
% =========================================================================
fprintf('\n=== Results for: %s ===\n', IMAGE_PATH);
fprintf('  PSNR (CLAHE vs original) : %.2f dB\n',   psnr_val);
fprintf('  SSIM (CLAHE vs original) : %.4f\n',       ssim_val);
fprintf('  ICR  original -> enhanced: %.3f -> %.3f (%+.1f%%)\n', ...
        icr_orig, icr_final, 100*(icr_final-icr_orig)/(icr_orig+eps));
fprintf('  Brain area               : %d px\n',      round(b_area));
fprintf('  Brain perimeter          : %.0f px\n',    b_perim);
fprintf('  Brain eq. diameter       : %.1f px\n\n',  b_eqdiam);
