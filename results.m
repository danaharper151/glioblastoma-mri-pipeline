% =========================================================================
%  TABBED RESULTS VIEWER — 3-ROW VERSION
%  COMP 510 | Digital Image Processing | Final Project
%
%  Shows Original / Enhanced / Color for each processed image.
%  Each tab displays up to 4 images across, 3 rows deep.
%
%  Usage:
%    1. Run brain_mri_pipeline.m first to populate data/output/
%    2. Run this script
%    3. Click through the tabs — File -> Save As to export any tab as PNG
% =========================================================================

clc; clear; close all;

% -------------------------------------------------------------------------
%  CONFIGURATION
% -------------------------------------------------------------------------
INPUT_DIR      = 'data/input';
OUTPUT_DIR     = 'data/output';
IMAGES_PER_TAB = 4;
MAX_TABS       = 5;

% -------------------------------------------------------------------------
%  MATCH FILES: original -> enhanced -> color
% -------------------------------------------------------------------------
origFiles = [dir(fullfile(INPUT_DIR, '*.jpg'));
             dir(fullfile(INPUT_DIR, '*.jpeg'));
             dir(fullfile(INPUT_DIR, '*.png'))];

if isempty(origFiles)
    error('No original images found in: %s', INPUT_DIR);
end

matchedOrig  = {};
matchedEnh   = {};
matchedColor = {};

for k = 1:numel(origFiles)
    [~, base, ~] = fileparts(origFiles(k).name);
    enhPath   = fullfile(OUTPUT_DIR, [base '_enhanced.png']);
    colorPath = fullfile(OUTPUT_DIR, [base '_color.png']);
    if isfile(enhPath) && isfile(colorPath)
        matchedOrig{end+1}  = fullfile(INPUT_DIR, origFiles(k).name); %#ok
        matchedEnh{end+1}   = enhPath;                                 %#ok
        matchedColor{end+1} = colorPath;                               %#ok
    end
end

if isempty(matchedOrig)
    error('No matched triplets found. Run brain_mri_pipeline.m first.');
end

totalImages = numel(matchedOrig);
numTabs     = min(MAX_TABS, ceil(totalImages / IMAGES_PER_TAB));
fprintf('Found %d matched sets — creating %d tab(s)\n', totalImages, numTabs);

% -------------------------------------------------------------------------
%  BUILD TABBED FIGURE
% -------------------------------------------------------------------------
fig = figure('Name',     'Brain Tumor MRI — Original / Enhanced / Color', ...
             'Position', [60 60 1440 820], ...
             'Color',    [0.10 0.10 0.10]);

tg = uitabgroup(fig, 'Units','normalized', 'Position',[0 0 1 1]);

for t = 1:numTabs

    idxStart = (t-1) * IMAGES_PER_TAB + 1;
    idxEnd   = min(t * IMAGES_PER_TAB, totalImages);
    idxRange = idxStart:idxEnd;
    n        = numel(idxRange);

    tab = uitab(tg, ...
        'Title',           sprintf('  Images %d-%d  ', idxStart, idxEnd), ...
        'BackgroundColor', [0.10 0.10 0.10]);

    % Tab header
    annotation(tab, 'textbox', ...
        'Units','normalized', 'Position',[0 0.945 1 0.05], ...
        'String',  sprintf('Original  |  Enhanced  |  Color (hot map)       Tab %d of %d', t, numTabs), ...
        'HorizontalAlignment','center', 'VerticalAlignment','middle', ...
        'FontSize',12, 'FontWeight','bold', ...
        'Color',[1 1 1], 'EdgeColor','none', 'BackgroundColor','none');

    % Layout: 3 rows, n columns
    colW  = 1 / n;
    padX  = 0.008;
    rowH  = 0.285;           % height of each image row
    row1Y = 0.640;           % Original  — top row
    row2Y = 0.340;           % Enhanced  — middle row
    row3Y = 0.040;           % Color     — bottom row

    for j = 1:n
        imgIdx = idxRange(j);

        % Load all three images
        orig = im2double(imread(matchedOrig{imgIdx}));
        if size(orig,3)==3, orig = rgb2gray(orig); end
        orig = rescale(orig);

        enh = im2double(imread(matchedEnh{imgIdx}));
        if size(enh,3)==3, enh = rgb2gray(enh); end

        col = imread(matchedColor{imgIdx});   % already RGB

        % Display name from filename
        [~, dispName, ~] = fileparts(matchedOrig{imgIdx});
        dispName = strrep(dispName, '_', '\_');

        xPos = (j-1)*colW + padX/2;
        wPos = colW - padX;

        % --- Row 1: Original ---
        ax1 = axes('Parent',tab,'Units','normalized', ...
                   'Position',[xPos row1Y wPos rowH]);
        imshow(orig, [], 'Parent', ax1);
        title(ax1, {'\color{white}\bf Original', ...
              ['\color[rgb]{0.6,0.6,0.6}' dispName]}, ...
              'FontSize',8, 'Interpreter','tex');
        set(ax1,'XColor','none','YColor','none','Color',[0.08 0.08 0.08]);

        % --- Row 2: Enhanced ---
        ax2 = axes('Parent',tab,'Units','normalized', ...
                   'Position',[xPos row2Y wPos rowH]);
        imshow(enh, [], 'Parent', ax2);
        title(ax2, '\color[rgb]{0.4,1,0.4}\bf Enhanced', ...
              'FontSize',8, 'Interpreter','tex');
        set(ax2,'XColor','none','YColor','none','Color',[0.08 0.08 0.08]);

        % --- Row 3: Color ---
        ax3 = axes('Parent',tab,'Units','normalized', ...
                   'Position',[xPos row3Y wPos rowH]);
        imshow(col, 'Parent', ax3);
        title(ax3, '\color[rgb]{1,0.75,0.2}\bf Color (hot map)', ...
              'FontSize',8, 'Interpreter','tex');
        set(ax3,'XColor','none','YColor','none','Color',[0.08 0.08 0.08]);

        % Column divider line
        if j < n
            xDiv = xPos + wPos + padX/2;
            annotation(tab,'line',[xDiv xDiv],[0.02 0.94], ...
                'Color',[0.28 0.28 0.28],'LineWidth',1);
        end
    end

    % Row label annotations on the left edge
    annotation(tab,'textbox','Units','normalized', ...
        'Position',[0 row1Y 0.013 rowH], ...
        'String','O R I G I N A L','Rotation',90, ...
        'HorizontalAlignment','center','VerticalAlignment','middle', ...
        'FontSize',7,'FontWeight','bold', ...
        'Color',[0.55 0.55 0.55],'EdgeColor','none','BackgroundColor','none');

    annotation(tab,'textbox','Units','normalized', ...
        'Position',[0 row2Y 0.013 rowH], ...
        'String','E N H A N C E D','Rotation',90, ...
        'HorizontalAlignment','center','VerticalAlignment','middle', ...
        'FontSize',7,'FontWeight','bold', ...
        'Color',[0.4 1 0.4],'EdgeColor','none','BackgroundColor','none');

    annotation(tab,'textbox','Units','normalized', ...
        'Position',[0 row3Y 0.013 rowH], ...
        'String','C O L O R','Rotation',90, ...
        'HorizontalAlignment','center','VerticalAlignment','middle', ...
        'FontSize',7,'FontWeight','bold', ...
        'Color',[1 0.75 0.2],'EdgeColor','none','BackgroundColor','none');

    % Horizontal dividers between rows
    annotation(tab,'line',[0.01 0.99],[row2Y+rowH+0.01 row2Y+rowH+0.01], ...
        'Color',[0.28 0.28 0.28],'LineWidth',1);
    annotation(tab,'line',[0.01 0.99],[row3Y+rowH+0.01 row3Y+rowH+0.01], ...
        'Color',[0.28 0.28 0.28],'LineWidth',1);

end

fprintf('Done! Click through the tabs in the figure window.\n');
fprintf('Tip: File -> Save As to export the active tab as PNG for slides.\n');