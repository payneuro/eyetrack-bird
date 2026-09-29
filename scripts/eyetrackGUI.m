function varargout = eyetrackGUI()
% eyetrackGUI            open the GUI
% fig = eyetrackGUI()    also return the figure handle
% GUI for the dual-camera eye tracking pipeline:
%   Settings    - paths and constants (defaults from src/eyetrackParams.m)
%   Calibration - check a calibration folder, preview images, run calibrateCameras
%   Behavior    - check one behavior session, tune tracker settings on a preview
%                 frame, label the beak, track, and analyze it
%   Birds       - combine all behavior sessions per bird (runEyetrackAll) and plot the summary
%
% Long steps (tracking, analysis) run in this MATLAB session. Figures open in
% their own windows and stay open. Command window output is copied to the log.

code_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(code_dir, 'src'));

P = loadSettings();
p_track = defaultTrackerParams();
stop_requested = false;
ui = struct;
vids = struct('folder', '', 'v1', [], 'v2', [], 'N', 0);
calib_cycle = struct('row', 0, 'k', 0);

%% Layout
fig = uifigure('Name', 'eyetrack-bird', 'Position', [80 60 1280 840]);
gmain = uigridlayout(fig, [3 1], 'RowHeight', {'1x', 150, 22}, 'Padding', [6 6 6 6]);
tg = uitabgroup(gmain);
log_area = uitextarea(gmain, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 11);
status_label = uilabel(gmain, 'Text', 'Ready');

tab_set = uitab(tg, 'Title', 'Settings');
tab_cal = uitab(tg, 'Title', 'Calibration');
tab_ses = uitab(tg, 'Title', 'Behavior');
tab_bird = uitab(tg, 'Title', 'Birds');

buildSettingsTab();
buildCalibrationTab();
buildSessionTab();
buildBirdTab();
tg.SelectedTab = tab_set;
logMsg('eyetrack-bird GUI. Settings loaded; edit them in the Settings tab.');
if nargout > 0
    varargout{1} = fig; % no output unless asked, so calling without ; prints nothing
end

%% ===================== Settings tab =====================
    function buildSettingsTab()
        g = uigridlayout(tab_set, [11 4], 'ColumnWidth', {190, 90, '1x', 90}, ...
            'RowHeight', [repmat({26}, 1, 10) {'1x'}]);
        tip = ['Behavior sessions find their calibration by the six digits after the last underscore, ' ...
            'e.g. HC13_230525b -> <calibration root>\230525.'];
        ui.set.calib_root = pathRow(g, 1, 'Calibration root', 'calib_root', tip);
        ui.set.data_root = pathRow(g, 2, 'Behavior session root', 'data_root', tip);
        ui.set.camfilename = textRow(g, 3, 'Video file template', 'camfilename');
        ui.set.square_size = numRow(g, 4, 'Checkerboard square (mm)', 'square_size');
        ui.set.mirror_thickness = numRow(g, 5, 'Mirror thickness (mm)', 'mirror_thickness');
        ui.set.axes_thresh = numRow(g, 6, 'Axes marker threshold', 'axes_thresh');
        ui.set.downsample_eye = numRow(g, 7, 'QTM frames per video frame', 'downsample_eye');
        ui.set.beak_skip_frames = numRow(g, 8, 'Beak click spacing (frames)', 'beak_skip_frames');
        r = uigridlayout(g, [1 3], 'ColumnWidth', {170, 200, '1x'}, 'Padding', [0 0 0 0]);
        r.Layout.Row = 10; r.Layout.Column = [1 4];
        uibutton(r, 'Text', 'Save as my defaults', 'ButtonPushedFcn', @(~,~) saveSettings(), ...
            'Tooltip', ['Save these values to your MATLAB preferences (setpref ''eyetrackGUI''). ' ...
            'The GUI starts with them next time instead of src/eyetrackParams.m.']);
        uibutton(r, 'Text', 'Reset to eyetrackParams.m', 'ButtonPushedFcn', @(~,~) resetSettings(), ...
            'Tooltip', ['Reload the values in src/eyetrackParams.m and delete your saved GUI defaults, ' ...
            'so the GUI starts from eyetrackParams.m again.']);

        p = uipanel(g, 'Title', 'Installed software (red = missing on this computer; Add-Ons need your MathWorks license)', 'FontWeight', 'bold');
        p.Layout.Row = 11; p.Layout.Column = [1 4];
        pg = uigridlayout(p, [2 1], 'RowHeight', {'1x', 26}, 'Padding', [6 6 6 6]);
        ui.req.table = uitable(pg, 'RowName', {}, ...
            'ColumnName', {'Software', 'OK', 'Needed for', 'How to install'}, ...
            'ColumnWidth', {240, 35, 260, 'auto'}, 'CellSelectionCallback', @showRequirement);
        r = uigridlayout(pg, [1 3], 'ColumnWidth', {120, '1x', 160}, 'Padding', [0 0 0 0]);
        uibutton(r, 'Text', 'Recheck', 'ButtonPushedFcn', @(~,~) refreshRequirements(), ...
            'Tooltip', 'Check again after installing something (restart MATLAB first for toolboxes and PATH changes)');
        ui.req.detail = uilabel(r, 'Text', 'Click a row to show its full install instructions here', 'WordWrap', 'on');
        ui.req.link = uihyperlink(r, 'Text', 'Open download page', 'Visible', 'off');
        refreshRequirements();
    end

    function showRequirement(~, evt)
        if isempty(evt.Indices); return; end
        row = ui.req.T(evt.Indices(1), :);
        ui.req.detail.Text = [row.item{1} ': ' row.how_to_install{1}];
        ui.req.link.Visible = ~isempty(row.url{1});
        if ~isempty(row.url{1}); ui.req.link.URL = row.url{1}; end
    end

    function refreshRequirements()
        T = checkRequirements();
        ui.req.T = T; % keeps the url column, which the table doesn't show
        showStatusTable(ui.req.table, T(:, {'item', 'ok', 'needed_for', 'how_to_install'}));
    end

    function h = pathRow(g, row, label, field, tip)
        l = uilabel(g, 'Text', label, 'Tooltip', tip); l.Layout.Row = row; l.Layout.Column = 1;
        h = uieditfield(g, 'text', 'Value', P.(field), 'Tooltip', tip, ...
            'ValueChangedFcn', @(src,~) setP(field, src.Value));
        h.Layout.Row = row; h.Layout.Column = [2 3];
        b = uibutton(g, 'Text', 'Browse', 'ButtonPushedFcn', @(~,~) browseP(field, h));
        b.Layout.Row = row; b.Layout.Column = 4;
    end

    function h = textRow(g, row, label, field)
        l = uilabel(g, 'Text', label); l.Layout.Row = row; l.Layout.Column = 1;
        h = uieditfield(g, 'text', 'Value', P.(field), ...
            'ValueChangedFcn', @(src,~) setP(field, src.Value));
        h.Layout.Row = row; h.Layout.Column = [2 3];
    end

    function h = numRow(g, row, label, field)
        l = uilabel(g, 'Text', label); l.Layout.Row = row; l.Layout.Column = 1;
        h = uieditfield(g, 'numeric', 'Value', P.(field), 'HorizontalAlignment', 'left', ...
            'ValueChangedFcn', @(src,~) setP(field, src.Value));
        h.Layout.Row = row; h.Layout.Column = 2;
    end

    function setP(field, value)
        P.(field) = value;
        vids.folder = ''; % reopen videos with the new settings
        if isfield(ui, 'ses') && strcmp(field, 'downsample_eye')
            ui.ses.downsample.Value = value;
        end
    end

    function browseP(field, h)
        d = uigetdir(P.(field));
        figure(fig);
        if ischar(d)
            h.Value = d;
            setP(field, d);
        end
    end

    function refreshSettingsFields()
        fn = fieldnames(ui.set);
        for ii = 1:numel(fn)
            ui.set.(fn{ii}).Value = P.(fn{ii});
        end
        ui.ses.downsample.Value = P.downsample_eye;
    end

    function saveSettings()
        setpref('eyetrackGUI', 'P', P);
        logMsg('Saved settings to MATLAB preferences.');
    end

    function resetSettings()
        P = eyetrackParams();
        if ispref('eyetrackGUI', 'P'); rmpref('eyetrackGUI', 'P'); end
        refreshSettingsFields();
        logMsg('Settings reset to src/eyetrackParams.m.');
    end

%% ===================== Calibration tab =====================
    function buildCalibrationTab()
        g = uigridlayout(tab_cal, [1 2], 'ColumnWidth', {480, '1x'});
        left = uigridlayout(g, [4 1], 'RowHeight', {96, 158, '1x', 104}, 'Padding', [0 0 0 0]);

        % 1. Folder
        p = uipanel(left, 'Title', '1. Calibration folder', 'FontWeight', 'bold');
        pg = uigridlayout(p, [2 1], 'RowHeight', {26, 26}, 'Padding', [6 6 6 6]);
        r = uigridlayout(pg, [1 3], 'ColumnWidth', {'1x', 70, 70}, 'Padding', [0 0 0 0]);
        ui.cal.folder = uieditfield(r, 'text', 'Placeholder', 'Existing folder, e.g. Z:\...\calibration\231212', ...
            'ValueChangedFcn', @(~,~) refreshCalibration());
        uibutton(r, 'Text', 'Browse', 'ButtonPushedFcn', @(~,~) browseCalibration());
        uibutton(r, 'Text', 'Refresh', 'ButtonPushedFcn', @(~,~) refreshCalibration(), ...
            'Tooltip', 'Re-check this folder''s files and update the list in 3 (after you add or delete images)');
        r = uigridlayout(pg, [1 3], 'ColumnWidth', {110, 80, '1x'}, 'Padding', [0 0 0 0]);
        uilabel(r, 'Text', 'or new (YYMMDD):');
        ui.cal.newdate = uieditfield(r, 'text', 'Value', char(datetime('today', 'Format', 'yyMMdd')));
        uibutton(r, 'Text', 'Create folder with cam1, cam2, lights, axes', 'ButtonPushedFcn', @(~,~) createCalibrationFolder(), ...
            'Tooltip', 'Make <calibration root>\<YYMMDD> with empty cam1, cam2, lights, and axes subfolders to save images into');

        % 2. Capture (outside MATLAB)
        p = uipanel(left, 'Title', '2. Capture images in SpinView and QTM (see README section 2)', 'FontWeight', 'bold');
        pg = uigridlayout(p, [1 1], 'Padding', [6 4 6 4]);
        helpLabel(pg, strjoin({ ...
            ['cam1\, cam2\:  4-10 checkerboard pairs, both cameras at once, same file names ' ...
            'in both folders'], ...
            ['lights\:  one LED on at a time; for each camera/light, camX_lightY_checkerboard.bmp ' ...
            '(long exposure, ~6000 us) and camX_lightY.bmp (min exposure, LED spot saturated)'], ...
            ['axes\:  cam1.bmp and cam2.bmp with the triangle markers saturated, plus qtm.mat ' ...
            'exported from QTM with markers labeled p0, px, py']}, newline));

        % 3. Check
        p = uipanel(left, 'Title', '3. Check files (red = missing; click a row to preview)', 'FontWeight', 'bold');
        pg = uigridlayout(p, [1 1], 'Padding', [6 6 6 6]);
        ui.cal.table = uitable(pg, 'ColumnName', {'Item', 'OK', 'Note'}, 'ColumnWidth', {160, 35, 'auto'}, ...
            'RowName', {}, 'CellSelectionCallback', @(~,evt) previewCalibration(evt));

        % 4. Process
        p = uipanel(left, 'Title', '4. Process', 'FontWeight', 'bold');
        pg = uigridlayout(p, [2 1], 'RowHeight', {30, 26}, 'Padding', [6 6 6 6]);
        uibutton(pg, 'Text', 'Run calibration', 'FontWeight', 'bold', ...
            'ButtonPushedFcn', @(~,~) runStep('Calibration', @runCalibration, true), ...
            'Tooltip', ['Process the images in this folder and overwrite calib.mat and axes.mat. ' ...
            'Check the log: reprojection error < 1 px, light 1 left of light 2, matching QTM and camera axis lengths. ' ...
            'Behavior sessions already triangulated with the old calibration keep their eye_triangulate.mat until it is deleted.']);
        r = uigridlayout(pg, [1 2], 'ColumnWidth', {'1x', '1x'}, 'Padding', [0 0 0 0]);
        uibutton(r, 'Text', 'Show saved results', 'ButtonPushedFcn', @(~,~) runStep('Calibration summary', @summarizeCalibration, true), ...
            'Tooltip', 'Print the saved calib.mat/axes.mat summary to the log without recomputing');
        uibutton(r, 'Text', 'Open Stereo Camera Calibrator app', 'ButtonPushedFcn', @(~,~) runStep('Stereo Camera Calibrator', @openStereoApp, false), ...
            'Tooltip', ['Open MATLAB''s app with this folder''s cam1/cam2 checkerboard images loaded, to inspect ' ...
            'detections and reprojection errors per pair. It does not change calib.mat; to drop a bad pair, delete its images and run calibration again.']);

        % Preview (for step 3)
        p = uipanel(g, 'Title', 'Preview', 'FontWeight', 'bold');
        right = uigridlayout(p, [2 2], 'RowHeight', {22, '1x'}, 'Padding', [6 6 6 6]);
        ui.cal.preview_label = uilabel(right, 'Text', 'Click a row in 3 to preview its images (click again for the next pair)');
        ui.cal.preview_label.Layout.Column = [1 2];
        ui.cal.ax1 = uiaxes(right); ui.cal.ax2 = uiaxes(right);
        prepImageAxes([ui.cal.ax1 ui.cal.ax2]);
    end

    function browseCalibration()
        start = ui.cal.folder.Value;
        if ~isfolder(start); start = P.calib_root; end
        d = uigetdir(start, 'Select calibration folder');
        figure(fig);
        if ischar(d)
            ui.cal.folder.Value = d;
            refreshCalibration();
        end
    end

    function createCalibrationFolder()
        d = fullfile(P.calib_root, strtrim(ui.cal.newdate.Value));
        if isempty(regexp(strtrim(ui.cal.newdate.Value), '^\d{6}$', 'once'))
            uialert(fig, 'Use a six-digit date, YYMMDD.', 'Calibration date'); return
        end
        for s = {'cam1', 'cam2', 'lights', 'axes'}
            if ~isfolder(fullfile(d, s{1})); mkdir(fullfile(d, s{1})); end
        end
        ui.cal.folder.Value = d;
        refreshCalibration();
        logMsg(['Created ' d]);
    end

    function refreshCalibration()
        d = ui.cal.folder.Value;
        calib_cycle.row = 0;
        if ~isfolder(d)
            ui.cal.table.Data = table();
            if ~isempty(d); logMsg(['Not a folder: ' d]); end
            return
        end
        showStatusTable(ui.cal.table, checkCalibrationFolder(d));
    end

    function runCalibration()
        d = requireFolder(ui.cal.folder.Value, 'calibration');
        calibrateCameras(d, P, 'all'); % always recompute; it takes seconds
        drawnow
        refreshCalibration();
        summarizeCalibration();
    end

    function openStereoApp()
        d = requireFolder(ui.cal.folder.Value, 'calibration');
        stereoCameraCalibrator(fullfile(d, 'cam1'), fullfile(d, 'cam2'), P.square_size);
    end

    function summarizeCalibration()
        d = requireFolder(ui.cal.folder.Value, 'calibration');
        f = fullfile(d, 'calib.mat');
        if ~isfile(f); error('No calib.mat in %s yet', d); end
        C = getfield(load(f), 'C');
        sp = C.stereo_params;
        fprintf('Calibration %s\n', d);
        fprintf('  Mean reprojection error: %.3f px (%i pairs)\n', sp.MeanReprojectionError, sp.NumPatterns);
        fprintf('  Camera baseline: %.1f mm\n', norm(C.p_cam2 - C.p_cam1));
        fprintf('  Light 1 (should be left):  [%.1f %.1f %.1f] mm\n', C.p_light1);
        fprintf('  Light 2 (should be right): [%.1f %.1f %.1f] mm\n', C.p_light2);
        if checkCameraOrder(C); fprintf('  Camera and light order OK\n'); end
        f = fullfile(d, 'axes.mat');
        if isfile(f)
            A = getfield(load(f), 'A');
            fprintf('  Axes origin (camera frame): [%.1f %.1f %.1f] mm\n', A.p0_eye);
        end
    end

    function previewCalibration(evt)
        d = ui.cal.folder.Value;
        if isempty(evt.Indices) || ~isfolder(d); return; end
        row = evt.Indices(1);
        item = ui.cal.table.Data.item{row};
        if calib_cycle.row == row
            calib_cycle.k = calib_cycle.k + 1;
        else
            calib_cycle = struct('row', row, 'k', 1);
        end
        tok = regexp(item, 'Light (\d), cam(\d)', 'tokens', 'once');
        if startsWith(item, 'Checkerboard')
            f1 = listImageFiles(fullfile(d, 'cam1'));
            f2 = listImageFiles(fullfile(d, 'cam2'));
            n = max(numel(f1), numel(f2));
            if n == 0; return; end
            k = mod(calib_cycle.k - 1, n) + 1;
            showImage(ui.cal.ax1, pick(f1, k), 'cam1');
            showImage(ui.cal.ax2, pick(f2, k), 'cam2');
            ui.cal.preview_label.Text = sprintf('Checkerboard pair %i of %i', k, n);
        elseif ~isempty(tok)
            base = sprintf('cam%s_light%s', tok{2}, tok{1});
            spot = fullfile(d, 'lights', [base '.bmp']);
            showImage(ui.cal.ax1, spot, [base '.bmp']);
            showImage(ui.cal.ax2, fullfile(d, 'lights', [base '_checkerboard.bmp']), [base '_checkerboard.bmp']);
            msg = '';
            if isfile(spot)
                I = imread(spot);
                msg = sprintf(' (%i saturated pixels; the largest saturated blob is taken as the LED)', nnz(I == 255));
            end
            ui.cal.preview_label.Text = [base msg];
        elseif startsWith(item, 'Axes')
            showImage(ui.cal.ax1, fullfile(d, 'axes', 'cam1.bmp'), 'axes cam1');
            showImage(ui.cal.ax2, fullfile(d, 'axes', 'cam2.bmp'), 'axes cam2');
            ui.cal.preview_label.Text = sprintf('Axes: markers must have intensity > %g for detection', P.axes_thresh);
        end
    end

%% ===================== Behavior tab =====================
    function buildSessionTab()
        g = uigridlayout(tab_ses, [1 2], 'ColumnWidth', {500, '1x'});
        left = uigridlayout(g, [7 1], 'RowHeight', {92, 26, 26, 185, '1x', 28, 32}, 'Padding', [0 0 0 0]);
        helpLabel(left, ['1. Pick a behavior session folder (cam1*.avi, cam2*.avi, qtm.mat). Its calibration must be processed.' newline ...
            '2. Preview a frame and tune the tracker (yellow = pupil fit, circles = CRs). Draw a crop to speed tracking. ' ...
            'Settings are fixed once eye.mat exists.' newline ...
            '3. Label the beak (5-10 poses), track, then analyze. Tracking resumes if stopped.']);

        r = uigridlayout(left, [1 3], 'ColumnWidth', {'1x', 70, 70}, 'Padding', [0 0 0 0]);
        ui.ses.folder = uieditfield(r, 'text', 'Placeholder', 'Behavior session folder, e.g. Z:\...\behavior\HC13_230525', ...
            'ValueChangedFcn', @(~,~) refreshSession());
        uibutton(r, 'Text', 'Browse', 'ButtonPushedFcn', @(~,~) browseSession());
        uibutton(r, 'Text', 'Refresh', 'ButtonPushedFcn', @(~,~) refreshSession(), ...
            'Tooltip', 'Re-check this behavior session''s files and pipeline outputs, and reload its tracker settings from eye.mat');

        r = uigridlayout(left, [1 4], 'ColumnWidth', {170, 60, '1x', 150}, 'Padding', [0 0 0 0]);
        uilabel(r, 'Text', 'QTM frames per video frame:');
        ui.ses.downsample = uieditfield(r, 'numeric', 'Value', P.downsample_eye, 'HorizontalAlignment', 'left', ...
            'ValueChangedFcn', @(src,~) setDownsample(src.Value));
        uilabel(r, 'Text', '');
        ui.ses.delete_eye = uibutton(r, 'Text', 'Delete eye.mat (retrack)', 'ButtonPushedFcn', @(~,~) deleteEye(), ...
            'Tooltip', 'Delete eye.mat and eye_triangulate.mat (asks first) so tracking restarts from frame 1 with new settings');

        ui.ses.table = uitable(left, 'ColumnName', {'Item', 'OK', 'Note'}, 'ColumnWidth', {150, 35, 'auto'}, 'RowName', {});

        ui.ses.params = uitable(left, 'ColumnName', {'Tracker setting', 'cam1', 'cam2'}, ...
            'ColumnEditable', [false true true], 'ColumnWidth', {170, 'auto', 'auto'}, 'RowName', {}, ...
            'CellEditCallback', @(~,evt) editTrackerParam(evt));

        r = uigridlayout(left, [1 4], 'Padding', [0 0 0 0]);
        uibutton(r, 'Text', 'Defaults', 'ButtonPushedFcn', @(~,~) setTrackerParams(defaultTrackerParams(), 'defaults'), ...
            'Tooltip', 'Reset the tracker settings table to src/defaultTrackerParams.m');
        uibutton(r, 'Text', 'Load from eye.mat...', 'ButtonPushedFcn', @(~,~) loadTrackerParams(), ...
            'Tooltip', 'Copy tracker settings from another behavior session''s eye.mat');
        uibutton(r, 'Text', 'Draw crop cam1', 'ButtonPushedFcn', @(~,~) drawCrop(1), ...
            'Tooltip', 'Show the full cam1 frame and drag a rectangle around the eye. Tracking only searches inside it (faster)');
        uibutton(r, 'Text', 'Draw crop cam2', 'ButtonPushedFcn', @(~,~) drawCrop(2), ...
            'Tooltip', 'Show the full cam2 frame and drag a rectangle around the eye. Tracking only searches inside it (faster)');

        r = uigridlayout(left, [1 4], 'Padding', [0 0 0 0]);
        uibutton(r, 'Text', '1. Label beak', 'ButtonPushedFcn', @(~,~) runStep('Beak labeling', @labelBeak, false), ...
            'Tooltip', 'Click the beak tip in cam1 then cam2 every few frames (5-10 head poses). Adds to beak.mat if it exists');
        uibutton(r, 'Text', '2. Track eyes', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~) runStep('Tracking', @trackSession, false), ...
            'Tooltip', 'Track pupil and CRs in every frame, then triangulate. Resumes a stopped run; skips tracking if eye.mat is complete');
        uibutton(r, 'Text', 'Stop tracking', 'ButtonPushedFcn', @(~,~) requestStop(), ...
            'Tooltip', 'Save progress to eye.mat and stop after the current frame. Track eyes resumes from there');
        uibutton(r, 'Text', '3. Analyze', 'ButtonPushedFcn', @(~,~) runStep('Behavior analysis', @analyzeSession, false), ...
            'Tooltip', 'Fit eye and beak positions in the head frame for this session (runEyetrackSingle) and save head_calibration.mat');

        right = uigridlayout(g, [3 2], 'RowHeight', {28, '1x', 22}, 'Padding', [0 0 0 0]);
        r = uigridlayout(right, [1 6], 'ColumnWidth', {45, 90, 100, 110, 110, '1x'}, 'Padding', [0 0 0 0]);
        r.Layout.Column = [1 2];
        uilabel(r, 'Text', 'Frame');
        ui.ses.frame = uispinner(r, 'Limits', [1 Inf], 'Value', 1, 'RoundFractionalValues', 'on', 'Step', 50, ...
            'Tooltip', 'Video frame to preview (arrows step 50 frames)');
        uibutton(r, 'Text', 'Preview', 'ButtonPushedFcn', @(~,~) runStep('Preview', @previewTracking, false), ...
            'Tooltip', 'Run the tracker with the current settings on this frame in both cameras');
        uibutton(r, 'Text', 'Random frame', 'ButtonPushedFcn', @(~,~) randomPreview(), ...
            'Tooltip', 'Preview a random frame');
        uibutton(r, 'Text', 'Full frame', 'ButtonPushedFcn', @(~,~) runStep('Full frame', @showFullFrames, false), ...
            'Tooltip', 'Show the uncropped frames with the crop boxes in yellow');
        ui.ses.frame_label = uilabel(r, 'Text', '');
        ui.ses.ax1 = uiaxes(right); ui.ses.ax2 = uiaxes(right);
        prepImageAxes([ui.ses.ax1 ui.ses.ax2]);
        ui.ses.progress = uilabel(right, 'Text', '');
        ui.ses.progress.Layout.Column = [1 2];

        setTrackerParams(p_track, 'defaults');
    end

    function browseSession()
        start = ui.ses.folder.Value;
        if ~isfolder(start); start = P.data_root; end
        d = uigetdir(start, 'Select behavior session folder');
        figure(fig);
        if ischar(d)
            ui.ses.folder.Value = d;
            refreshSession();
        end
    end

    function setDownsample(v)
        P.downsample_eye = v;
        ui.set.downsample_eye.Value = v;
    end

    function refreshSession()
        d = ui.ses.folder.Value;
        vids = struct('folder', '', 'v1', [], 'v2', [], 'N', 0);
        if ~isfolder(d)
            ui.ses.table.Data = table();
            return
        end
        [T, info] = checkSessionFolder(d, P);
        showStatusTable(ui.ses.table, T);
        f = fullfile(d, 'eye.mat');
        if isfile(f)
            s = load(f, 'p');
            setTrackerParams(s.p, 'eye.mat (locked: delete eye.mat to change)');
        elseif ~ui.ses.params.ColumnEditable(2)
            setTrackerParams(p_track, 'carried over from the last session (editable)');
        end
        if ~any(isnan(info.N_eye))
            ui.ses.frame.Limits = [1 min(info.N_eye)];
            t_example = 7;
            if isfield(p_track, 'example_t') && ~isempty(p_track(1).example_t); t_example = p_track(1).example_t; end
            ui.ses.frame.Value = min(min(info.N_eye), max(1, round(t_example * info.fps_eye)));
        end
        if ~any(isnan([info.N_eye info.N_head])) && info.N_head < min(info.N_eye) * P.downsample_eye
            logMsg(sprintf('Warning: QTM has %i frames, fewer than videos x %i = %i. Check the downsample factor.', ...
                info.N_head, P.downsample_eye, min(info.N_eye) * P.downsample_eye));
        end
    end

    function setTrackerParams(p, source)
        if numel(p) == 1; p(2) = p(1); end
        [p.pupil_start] = deal([NaN NaN]); % start each session's search fresh
        p_track = p;
        fn = fieldnames(p);
        fn = fn(~strcmp(fn, 'pupil_start')); % runtime state, not a setting
        data = cell(numel(fn), 3);
        for ii = 1:numel(fn)
            data{ii,1} = fn{ii};
            data{ii,2} = mat2str(p(1).(fn{ii}));
            data{ii,3} = mat2str(p(2).(fn{ii}));
        end
        ui.ses.params.Data = data;
        locked = contains(source, 'locked');
        ui.ses.params.ColumnEditable = [false ~locked ~locked];
        logMsg(['Tracker settings: ' source]);
    end

    function editTrackerParam(evt)
        row = evt.Indices(1); cam = evt.Indices(2) - 1;
        name = ui.ses.params.Data{row, 1};
        v = str2num(evt.NewData); %#ok<ST2NM> accepts '[500 1400]', '[]', 'NaN'
        if isempty(v) && ~any(strcmp(strtrim(evt.NewData), {'[]', ''}))
            ui.ses.params.Data{row, cam+1} = evt.PreviousData;
            uialert(fig, sprintf('Could not read "%s" as a number or vector.', evt.NewData), 'Tracker setting');
            return
        end
        p_track(cam).(name) = v;
    end

    function loadTrackerParams()
        [f, d] = uigetfile({'eye.mat;tracker_params.mat', 'eye.mat'}, 'Load tracker settings', P.data_root);
        figure(fig);
        if ~ischar(f); return; end
        s = load(fullfile(d, f), 'p');
        setTrackerParams(s.p, fullfile(d, f));
    end

    function deleteEye()
        d = ui.ses.folder.Value;
        f = fullfile(d, 'eye.mat');
        if ~isfile(f); logMsg('No eye.mat to delete.'); return; end
        sel = uiconfirm(fig, sprintf('Delete %s and eye_triangulate.mat? Tracking restarts from frame 1.', f), ...
            'Delete tracking results', 'Options', {'Delete', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
        if ~strcmp(sel, 'Delete'); return; end
        delete(f);
        if isfile(fullfile(d, 'eye_triangulate.mat')); delete(fullfile(d, 'eye_triangulate.mat')); end
        logMsg(['Deleted ' f]);
        setTrackerParams(p_track, 'from deleted eye.mat (editable)');
        refreshSession();
    end

    function openVideos()
        d = requireFolder(ui.ses.folder.Value, 'behavior session');
        if ~strcmp(vids.folder, d)
            [v1, v2, N] = openEyeVideos(d, P.camfilename);
            vids = struct('folder', d, 'v1', v1, 'v2', v2, 'N', N);
        end
    end

    function previewTracking()
        openVideos();
        ii = min(vids.N, ui.ses.frame.Value);
        p = p_track;
        [p.plot_on] = deal(1);
        [p.pupil_start] = deal([NaN NaN]);
        [I1, I2] = readEyeFrames(vids.v1, vids.v2, ii, p);
        ax = [ui.ses.ax1 ui.ses.ax2];
        I = {I1, I2};
        fit_txt = cell(1,2);
        for cam = 1:2
            [pupil, cr, ~, resid, points] = detectPupilCR(I{cam}, p(cam).edge_thresh0, p(cam));
            crs = squeeze(cr);
            cla(ax(cam)); h = struct('ah', ax(cam));
            detectPupilCRPlot(I{cam}, p(cam), h, pupil, crs, points);
            title(ax(cam), sprintf('cam%i', cam));
            fit_txt{cam} = sprintf('cam%i: pupil radius %.1f px, fit residual %.2f (max %.2f), %i of %i CRs', cam, ...
                max(pupil(3:4)), resid, p(cam).ellipse_residual_thresh, nnz(~isnan(crs(1,:))), p(cam).nCRs);
        end
        ui.ses.progress.Text = strjoin(fit_txt, '   |   ');
        ui.ses.frame_label.Text = sprintf('t = %.2f s of %.1f s', ii / vids.v1.FrameRate, vids.N / vids.v1.FrameRate);
    end

    function randomPreview()
        try
            openVideos();
            ui.ses.frame.Value = randi(vids.N);
        catch
        end
        runStep('Preview', @previewTracking, false);
    end

    function showFullFrames()
        openVideos();
        ii = min(vids.N, ui.ses.frame.Value);
        [I1, I2] = readEyeFrames(vids.v1, vids.v2, ii);
        ax = [ui.ses.ax1 ui.ses.ax2];
        I = {I1, I2};
        for cam = 1:2
            cla(ax(cam));
            imagesc(ax(cam), I{cam}); colormap(ax(cam), gray); axis(ax(cam), 'image');
            if ~isempty(p_track(cam).cropX)
                x = p_track(cam).cropX; y = p_track(cam).cropY;
                hold(ax(cam), 'on');
                plot(ax(cam), x([1 2 2 1 1]), y([1 1 2 2 1]), 'y-', 'LineWidth', 1.5);
                hold(ax(cam), 'off');
            end
            title(ax(cam), sprintf('cam%i full frame (yellow = crop)', cam));
        end
    end

    function drawCrop(cam)
        if ~ui.ses.params.ColumnEditable(2)
            uialert(fig, 'Settings are locked because eye.mat exists.', 'Crop'); return
        end
        try
            showFullFrames();
        catch err
            logMsg(err.message); return
        end
        ax = [ui.ses.ax1 ui.ses.ax2];
        title(ax(cam), sprintf('cam%i: drag a rectangle around the eye', cam));
        roi = drawrectangle(ax(cam), 'Color', 'c');
        if ~isvalid(roi) || isempty(roi.Position); return; end
        pos = round(roi.Position); % [x y w h]
        v = vids.(sprintf('v%i', cam));
        I_size = [v.Height v.Width];
        p_track(cam).cropX = [max(1, pos(1)) min(I_size(2), pos(1) + pos(3))];
        p_track(cam).cropY = [max(1, pos(2)) min(I_size(1), pos(2) + pos(4))];
        setTrackerParams(p_track, sprintf('crop cam%i set to x %s, y %s', cam, ...
            mat2str(p_track(cam).cropX), mat2str(p_track(cam).cropY)));
        showFullFrames();
    end

    function labelBeak()
        d = requireFolder(ui.ses.folder.Value, 'behavior session');
        resume = isfile(fullfile(d, 'beak.mat'));
        if resume
            sel = uiconfirm(fig, 'beak.mat exists. Add more points to it?', 'Beak', ...
                'Options', {'Add points', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 2);
            if ~strcmp(sel, 'Add points'); return; end
        end
        logMsg('Beak: left-click the beak tip in cam1, then cam2. Right-click skips ahead, Enter finishes.');
        getBeak(d, P.camfilename, resume, true, P.beak_skip_frames);
        % 3D points are cached; recompute them with the new beak clicks
        if isfile(fullfile(d, 'eye_triangulate.mat')); delete(fullfile(d, 'eye_triangulate.mat')); end
        refreshSession();
    end

    function trackSession()
        d = requireFolder(ui.ses.folder.Value, 'behavior session');
        stop_requested = false;
        opts = struct;
        opts.ah = [ui.ses.ax1 ui.ses.ax2];
        opts.stop_fcn = @checkStop;
        opts.progress_fcn = @(ii, N) set(ui.ses.progress, 'Text', sprintf('Tracked %i / %i frames', ii, N));
        cla(ui.ses.ax1); cla(ui.ses.ax2);
        % Tracking and triangulation only; QTM is not needed until analysis
        C = calibrateCameras(findCalibrationFolder(d, P.calib_root), P);
        processEyetrack(d, P.camfilename, C, false, false, true, p_track, opts);
        w = whos('-file', fullfile(d, 'eye.mat'));
        if any(strcmp({w.name}, 'ii'))
            s = load(fullfile(d, 'eye.mat'), 'ii');
            logMsg(sprintf('Tracking stopped at frame %i. Track eyes resumes from there.', s.ii));
        end
        refreshSession();
    end

    function tf = checkStop()
        drawnow limitrate
        tf = stop_requested;
    end

    function requestStop()
        stop_requested = true;
        logMsg('Stop requested; tracking will save and stop after this frame.');
    end

    function analyzeSession()
        d = requireFolder(ui.ses.folder.Value, 'behavior session');
        runEyetrackSingle(d, P.downsample_eye, P);
        refreshSession();
    end

%% ===================== Birds tab =====================
    function buildBirdTab()
        g = uigridlayout(tab_bird, [1 2], 'ColumnWidth', {330, '1x'});
        left = uigridlayout(g, [5 1], 'RowHeight', {92, 26, '1x', 32, 32}, 'Padding', [0 0 0 0]);
        helpLabel(left, ['Combine all behavior sessions of a bird into one head/eye calibration (runEyetrackAll). ' ...
            'Results go to <behavior session root>\<BIRD>_all. Beak clicks are asked for in the first behavior session only; ' ...
            'untracked behavior sessions are tracked first, with src/defaultTrackerParams.m (not the Behavior tab settings). ' ...
            'Then plot the summary across birds (plotEyetrack).']);
        uibutton(left, 'Text', 'Scan behavior session root', 'ButtonPushedFcn', @(~,~) scanBirds(), ...
            'Tooltip', 'List birds from folder names <BIRD>_<YYMMDD> in the behavior session root');
        ui.bird.list = uilistbox(left, 'Multiselect', 'on', 'Items', {}, 'ValueChangedFcn', @(~,~) showBirdSessions());
        uibutton(left, 'Text', 'Run selected birds', 'FontWeight', 'bold', ...
            'ButtonPushedFcn', @(~,~) runStep('Bird analysis', @runBirds, false), ...
            'Tooltip', 'For each selected bird, track any untracked sessions and combine all sessions (runEyetrackAll); saves <BIRD>_all');
        uibutton(left, 'Text', 'Summary plot (birds with _all results)', ...
            'ButtonPushedFcn', @(~,~) runStep('Summary', @summaryPlot, true), ...
            'Tooltip', 'Plot eye angles across the selected birds (or all listed birds) that have <BIRD>_all results (plotEyetrack)');
        ui.bird.table = uitable(g, 'RowName', {}, ...
            'ColumnName', {'Behavior session', 'Videos', 'qtm.mat', 'beak.mat', 'eye.mat', 'Calibration', 'head_calibration'});
    end

    function scanBirds()
        d = P.data_root;
        if ~isfolder(d); uialert(fig, ['Behavior session root not found: ' d], 'Birds'); return; end
        a = dir(d);
        names = {a([a.isdir]).name};
        tok = regexp(names, '^(.+)_\d{6}[^_]*$', 'tokens', 'once');
        birds = unique(cellfun(@(t) t{1}, tok(~cellfun(@isempty, tok)), 'UniformOutput', false));
        ui.bird.list.Items = birds;
        ui.bird.list.Value = {};
        logMsg(sprintf('Found %i birds in %s', numel(birds), d));
    end

    function showBirdSessions()
        rows = {};
        for b = ui.bird.list.Value
            a = dir(fullfile(P.data_root, [b{1} '_*']));
            a = a([a.isdir] & ~endsWith({a.name}, '_all'));
            for ii = 1:numel(a)
                f = fullfile(a(ii).folder, a(ii).name);
                n_vid = numel(dir(fullfile(f, sprintf(P.camfilename, 1)))) + numel(dir(fullfile(f, sprintf(P.camfilename, 2))));
                try
                    fc = findCalibrationFolder(f, P.calib_root);
                    has_cal = isfile(fullfile(fc, 'calib.mat')) && isfile(fullfile(fc, 'axes.mat'));
                catch
                    has_cal = false;
                end
                rows(end+1, :) = [{a(ii).name}, yesNo([n_vid == 2, isfile(fullfile(f, 'qtm.mat')), ...
                    isfile(fullfile(f, 'beak.mat')), isfile(fullfile(f, 'eye.mat')), has_cal, ...
                    isfile(fullfile(f, 'head_calibration.mat'))])]; %#ok<AGROW>
            end
            rows(end+1, :) = [{[b{1} '_all']}, {'', '', '', '', ''}, ...
                yesNo(isfile(fullfile(P.data_root, [b{1} '_all'], 'head_calibration.mat')))]; %#ok<AGROW>
        end
        ui.bird.table.Data = rows;
    end

    function runBirds()
        birds = ui.bird.list.Value;
        if isempty(birds); error('Select at least one bird'); end
        for ii = 1:numel(birds)
            logMsg(sprintf('Running %s (%i of %i)', birds{ii}, ii, numel(birds)));
            runEyetrackAll(fullfile(P.data_root, [birds{ii} '_*']), P.downsample_eye, 1, P);
        end
        showBirdSessions();
    end

    function summaryPlot()
        birds = ui.bird.list.Value;
        if isempty(birds); birds = ui.bird.list.Items; end
        has = cellfun(@(b) isfile(fullfile(P.data_root, [b '_all'], 'head_calibration_stats.mat')), birds);
        if ~any(has); error('No <BIRD>_all results yet for the selected birds'); end
        plotEyetrack(P.data_root, cellfun(@(b) [b '_*'], birds(has), 'UniformOutput', false));
        drawnow
    end

%% ===================== Shared helpers =====================
    function runStep(name, fn, capture)
        % Run fn, report errors in the log and a dialog. If capture, copy the
        % command window output into the log.
        status_label.Text = [name '...'];
        fig.Pointer = 'watch';
        drawnow
        if capture
            tmp = [tempname '.txt'];
            diary(tmp);
        end
        try
            fn();
            status_label.Text = [name ' done'];
            ok = true;
        catch err
            status_label.Text = [name ' failed'];
            ok = false;
        end
        if capture
            diary off
            if isfile(tmp)
                txt = fileread(tmp);
                delete(tmp);
                if ~isempty(strtrim(txt)); logMsg(strtrim(txt)); end
            end
        end
        if isvalid(fig); fig.Pointer = 'arrow'; end
        if ~ok
            logMsg(sprintf('%s failed: %s', name, err.message));
            fprintf(2, '%s\n', getReport(err, 'extended', 'hyperlinks', 'off'));
            if isvalid(fig); uialert(fig, err.message, [name ' failed']); end
        end
    end

    function logMsg(msg)
        if ~isvalid(fig); return; end
        txt_lines = splitlines(string(msg));
        stamp = string(datetime('now', 'Format', 'HH:mm:ss'));
        txt_lines(1) = stamp + "  " + txt_lines(1);
        log_area.Value = [log_area.Value; cellstr(txt_lines)];
        scroll(log_area, 'bottom');
        drawnow limitrate
    end

    function showStatusTable(tbl, T)
        tbl.Data = T;
        removeStyle(tbl);
        bad = find(~T.ok);
        if ~isempty(bad)
            addStyle(tbl, uistyle('BackgroundColor', [1 0.85 0.85]), 'row', bad);
        end
    end

    function d = requireFolder(d, what)
        if ~isfolder(d)
            error('Pick a %s folder first (got "%s")', what, d);
        end
    end
end

%% ===================== Local functions =====================
function P = loadSettings()
P = eyetrackParams();
if ispref('eyetrackGUI', 'P')
    saved = getpref('eyetrackGUI', 'P');
    fn = intersect(fieldnames(saved), fieldnames(P));
    for ii = 1:numel(fn)
        P.(fn{ii}) = saved.(fn{ii});
    end
end
end

function helpLabel(parent, txt)
uilabel(parent, 'Text', txt, 'WordWrap', 'on', 'VerticalAlignment', 'top', ...
    'FontColor', [0.25 0.25 0.25]);
end

function prepImageAxes(ax)
for ii = 1:numel(ax)
    ax(ii).XTick = []; ax(ii).YTick = [];
    ax(ii).Box = 'on';
    colormap(ax(ii), gray);
end
end

function c = yesNo(tf)
c = repmat({'no'}, 1, numel(tf));
c(tf) = {'yes'};
end

function f = pick(files, k)
if k <= numel(files); f = files{k}; else; f = ''; end
end

function showImage(ax, f, label)
cla(ax);
if isempty(f) || ~isfile(f)
    title(ax, [label ': missing'], 'Interpreter', 'none');
    return
end
imagesc(ax, imread(f)); colormap(ax, gray); axis(ax, 'image');
ax.XTick = []; ax.YTick = [];
[~, n, e] = fileparts(f);
if strcmp(label, [n e]); txt = label; else; txt = [label '  (' n e ')']; end
title(ax, txt, 'Interpreter', 'none');
end
