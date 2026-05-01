% =========================================================================
%  TABBED BEFORE / AFTER VIEWER
%  COMP 510 | Digital Image Processing | Final Project
%
%  Creates a presentation-ready tabbed figure showing before/after pairs
%  for all processed images. Each tab displays 4 image pairs side by side:
%  original on top, final enhanced on the bottom.
%
%  Usage:
%    1. Run brain_tumor_pipeline.m first to populate data/output/
%    2. Run this script
%    3. Click through the tabs in the figure window
%
%  Tip: File -> Save As in the figure window exports the active tab as PNG.
% =========================================================================

clc; clear; close all;

% -------------------------------------------------------------------------
%  CONFIGURATION
% -------------------------------------------------------------------------
INPUT_DIR      = 'data/input';    % original images
OUTPUT_DIR     = 'data/output';   % enhanced images (*_enhanced.png)
IMAGES_PER_TAB = 4;               % pairs per tab (3 = bigger, 4 = more compact)
MAX_TABS       = 5;               % cap on number of tabs

% -------------------------------------------------------------------------
%  MATCH ORIGINAL FILES TO THEIR ENHANCED COUNTERPARTS
% -------------------------------------------------------------------------
origFiles = [dir(fullfile(INPUT_DIR, '*.jpg'));
             dir(fullfile(INPUT_DIR, '*.jpeg'));
             dir(fullfile(INPUT_DIR, '*.png'))];

if isempty(origFiles)
    error('No original images found in: %s', INPUT_DIR);
end

matchedOrig = {};
matchedEnh  = {};

for k = 1:numel(origFiles)
    [~, base, ~] = fileparts(origFiles(k).name);
    enhPath = fullfile(OUTPUT_DIR, [base '_enhanced.png']);
    if isfile(enhPath)
        matchedOrig{end+1} = fullfile(INPUT_DIR, origFiles(k).name); %#ok
        matchedEnh{end+1}  = enhPath;                                 %#ok
    end
end

if isempty(matchedOrig)
    error('No matched pairs found. Run brain_tumor_pipeline.m first.');
end

totalImages = numel(matchedOrig);
numTabs     = min(MAX_TABS, ceil(totalImages / IMAGES_PER_TAB));
fprintf('Found %d matched pairs — creating %d tab(s)\n', totalImages, numTabs);

% -------------------------------------------------------------------------
%  BUILD TABBED FIGURE
% -------------------------------------------------------------------------
fig = figure('Name',     'Brain Tumor MRI — Before / After', ...
             'Position', [80 80 1400 700], ...
             'Color',    [0.12 0.12 0.12]);

tg = uitabgroup(fig, 'Units','normalized', 'Position',[0 0 1 1]);

for t = 1:numTabs

    idxStart = (t-1) * IMAGES_PER_TAB + 1;
    idxEnd   = min(t * IMAGES_PER_TAB, totalImages);
    idxRange = idxStart:idxEnd;
    n        = numel(idxRange);

    tab = uitab(tg, ...
        'Title',           sprintf('  Images %d-%d  ', idxStart, idxEnd), ...
        'BackgroundColor', [0.12 0.12 0.12]);

    % Tab header label
    annotation(tab, 'textbox', ...
        'Units','normalized', 'Position',[0 0.93 1 0.06], ...
        'String',  sprintf('BEFORE  →  AFTER       (Tab %d of %d)', t, numTabs), ...
        'HorizontalAlignment','center', 'VerticalAlignment','middle', ...
        'FontSize',13, 'FontWeight','bold', ...
        'Color',[1 1 1], 'EdgeColor','none', 'BackgroundColor','none');

    colW = 1 / n;
    padX = 0.01;
    topY = 0.50;   % Before row y-start
    botY = 0.04;   % After  row y-start
    rowH = 0.42;

    for j = 1:n
        imgIdx = idxRange(j);

        orig = im2double(imread(matchedOrig{imgIdx}));
        if size(orig,3) == 3, orig = rgb2gray(orig); end
        orig = rescale(orig);

        enh = im2double(imread(matchedEnh{imgIdx}));
        if size(enh,3) == 3, enh = rgb2gray(enh); end

        [~, dispName, ~] = fileparts(matchedOrig{imgIdx});
        dispName = strrep(dispName, '_', '\_');

        xPos = (j-1)*colW + padX/2;
        wPos = colW - padX;

        % Before
        ax_top = axes('Parent',tab,'Units','normalized', ...
                      'Position',[xPos topY wPos rowH]);
        imshow(orig, [], 'Parent', ax_top);
        title(ax_top, {'\color{white}\bf Before', ...
              ['\color[rgb]{0.65,0.65,0.65}' dispName]}, ...
              'FontSize',9, 'Interpreter','tex');
        set(ax_top, 'XColor','none', 'YColor','none', 'Color',[0.08 0.08 0.08]);

        % After
        ax_bot = axes('Parent',tab,'Units','normalized', ...
                      'Position',[xPos botY wPos rowH]);
        imshow(enh, [], 'Parent', ax_bot);
        title(ax_bot, '\color[rgb]{0.4,1,0.4}\bf After (Enhanced)', ...
              'FontSize',9, 'Interpreter','tex');
        set(ax_bot, 'XColor','none', 'YColor','none', 'Color',[0.08 0.08 0.08]);

        % Column divider
        if j < n
            annotation(tab, 'line', ...
                [xPos+wPos+padX/2, xPos+wPos+padX/2], [0.02 0.95], ...
                'Color',[0.3 0.3 0.3], 'LineWidth',1);
        end
    end

    % Row labels
    annotation(tab,'textbox','Units','normalized','Position',[0 topY 0.012 rowH], ...
        'String','B E F O R E','Rotation',90,'HorizontalAlignment','center', ...
        'VerticalAlignment','middle','FontSize',8,'FontWeight','bold', ...
        'Color',[0.55 0.55 0.55],'EdgeColor','none','BackgroundColor','none');
    annotation(tab,'textbox','Units','normalized','Position',[0 botY 0.012 rowH], ...
        'String','A F T E R','Rotation',90,'HorizontalAlignment','center', ...
        'VerticalAlignment','middle','FontSize',8,'FontWeight','bold', ...
        'Color',[0.4 1 0.4],'EdgeColor','none','BackgroundColor','none');

    % Divider between rows
    annotation(tab,'line',[0.01 0.99],[topY-0.015 topY-0.015], ...
        'Color',[0.3 0.3 0.3],'LineWidth',1);
end

fprintf('Done. Click through the tabs in the figure window.\n');
fprintf('Tip: File -> Save As to export the active tab as PNG for slides.\n');
