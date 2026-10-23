function varargout = eyetrackGUI()
% eyetrackGUI            open the GUI
% fig = eyetrackGUI()    also return the figure handle
% GUI for the dual-camera eye tracking pipeline:
%   Settings    - paths and constants (defaults from src/eyetrackParams.m)
%   Calibration - capture calibration images from the cameras, check and
%                 preview them (delete to retake), run calibrateCameras
%   Record behavior  - live view, then record both cameras on QTM's trigger
%                 (compressed on the GPU or raw)
%   Analyze behavior - check one behavior session, tune tracker settings on a preview
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
step_progress = NaN; % fraction done of the running step, shown in the status bar (NaN = unknown)
frame_plots = {struct(), struct()}; % image and fit-line handles in the Analyze behavior preview, per camera
beak = []; % beak labeling state while "Label beak" is on (p1, p2, pending cam1 click), [] when off
ui = struct;
vids = struct('folder', '', 'v1', [], 'v2', [], 'N', 0, 'in_view', []); % in_view: findBirdFrames result, loaded when skipping
cams = []; % connected eye cameras (openEyeCameras), [] if not connected
shown_files = {}; % saved images shown in the calibration Preview, for Delete
live = struct('timer', [], 'saved', [], 'img', gobjects(1, 2), 't0', [], 'resume_at', 0); % live view; paused until toc(t0) >= resume_at
rec = struct('state', [], 'timer', [], 'img', gobjects(1, 2), 't0', [], 'n_prev', [0 0], 't_prev', 0); % recording (startEyeRecording), state = [] when not recording

%% Layout
fig = uifigure('Name', 'eyetrack-bird', 'Position', [80 60 1280 840], ...
    'CloseRequestFcn', @(~,~) closeGUI(), 'DeleteFcn', @(~,~) releaseCameras());
gmain = uigridlayout(fig, [3 1], 'RowHeight', {'1x', 150, 22}, 'Padding', [6 6 6 6]);
tg = uitabgroup(gmain);
log_area = uitextarea(gmain, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 11);
status_label = uilabel(gmain, 'Text', 'Ready');

tab_set = uitab(tg, 'Title', 'Settings');
tab_cal = uitab(tg, 'Title', 'Calibration');
tab_rec = uitab(tg, 'Title', 'Record behavior');
tab_ses = uitab(tg, 'Title', 'Analyze behavior');
tab_bird = uitab(tg, 'Title', 'Birds');

buildSettingsTab();
buildCalibrationTab();
buildRecordTab();
buildSessionTab();
buildBirdTab();
tg.SelectedTab = tab_set;
tg.SelectionChangedFcn = @(~,~) moveLive(); % live view follows the Calibration and Record behavior tabs
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
        ui.set.square_size = numRow(g, 3, 'Checkerboard square (mm)', 'square_size');
        ui.set.axes_thresh = numRow(g, 4, 'Axes marker threshold', 'axes_thresh');
        ui.set.downsample_eye = numRow(g, 5, 'QTM frames per video frame', 'downsample_eye');
        ui.set.beak_skip_frames = numRow(g, 6, 'Beak click spacing (frames)', 'beak_skip_frames');
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
        left = uigridlayout(g, [5 1], 'RowHeight', {24, 96, 190, '1x', 104}, 'Padding', [0 0 0 0]);
        uipanel(left, 'Title', '0. First calibrate QTM', 'FontWeight', 'bold', 'ForegroundColor', 'k'); % title only, done in QTM

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

        % 2. Capture (from MATLAB; the QTM part of the axes step is done in QTM)
        p = uipanel(left, 'Title', '2. Capture still images (close SpinView first)', 'FontWeight', 'bold');
        pg = uigridlayout(p, [4 1], 'RowHeight', {26, 26, 28, '1x'}, 'Padding', [6 4 6 4]);
        r = uigridlayout(pg, [1 2], 'ColumnWidth', {140, '1x'}, 'Padding', [0 0 0 0]);
        ui.cap.connect = uibutton(r, 'Text', 'Connect cameras', 'ButtonPushedFcn', @(~,~) runStep('Connect cameras', @toggleCameras, true), ...
            'Tooltip', ['Connect to both Blackfly cameras (matched to cam1/cam2 by serial number in eyetrackParams.m) ' ...
            'and show them live in Preview']);
        ui.cap.status = uilabel(r, 'Text', 'Not connected');
        r = uigridlayout(pg, [1 4], 'ColumnWidth', {40, '1x', 95, 70}, 'Padding', [0 0 0 0]);
        uilabel(r, 'Text', 'What:');
        ui.cap.what = uidropdown(r, 'Items', {captureItems(P).label}, 'ValueChangedFcn', @(~,~) setCaptureExposure());
        uilabel(r, 'Text', 'Exposure (ms):', 'HorizontalAlignment', 'right');
        ui.cap.exposure = uieditfield(r, 'numeric', 'Limits', [0.012 30000], 'Value', 16, 'HorizontalAlignment', 'left', ...
            'ValueDisplayFormat', '%.3f', ...
            'ValueChangedFcn', @(~,~) applyLiveExposure(), ...
            'Tooltip', 'Applied to both cameras for this capture only; their own exposure is restored afterward');
        uibutton(pg, 'Text', 'Save images', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~) runStep('Save images', @captureStill, true), ...
            'Tooltip', 'Save the current live frame from each camera under the file names this item needs');
        items = captureItems(P);
        ui.cap.hint = uilabel(pg, 'WordWrap', 'on', 'VerticalAlignment', 'top', 'FontColor', [0.25 0.25 0.25], ...
            'Text', items(1).hint); % setCaptureExposure updates it when the item changes

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
        uibutton(pg, 'Text', 'Show saved results', 'ButtonPushedFcn', @(~,~) runStep('Calibration summary', @summarizeCalibration, true), ...
            'Tooltip', 'Print the saved calib.mat/axes.mat summary to the log without recomputing');

        % Preview (for step 3)
        p = uipanel(g, 'Title', 'Preview', 'FontWeight', 'bold');
        right = uigridlayout(p, [3 2], 'RowHeight', {22, '1x', 28}, 'Padding', [6 6 6 6]);
        ui.cal.preview_label = uilabel(right, 'Text', 'Pick saved images below, or click a row in 3');
        ui.cal.preview_label.Layout.Column = [1 2];
        ui.cal.ax1 = uiaxes(right); ui.cal.ax2 = uiaxes(right);
        prepImageAxes([ui.cal.ax1 ui.cal.ax2]);
        r = uigridlayout(right, [1 4], 'ColumnWidth', {95, '1x', 220, 100}, 'Padding', [0 0 0 0]);
        r.Layout.Column = [1 2];
        uilabel(r, 'Text', 'Saved images:');
        ui.cal.saved = uidropdown(r, 'Items', {'(none yet)'}, 'ValueChangedFcn', @(src,~) showSaved(src.Value), ...
            'Tooltip', 'Every image pair saved in this calibration folder');
        ui.cal.delete = uibutton(r, 'Text', 'Delete these images (to retake)', 'Enable', 'off', ...
            'ButtonPushedFcn', @(~,~) deleteShownImages(), ...
            'Tooltip', 'Delete the saved images shown above (asks first), then save them again in 2');
        ui.cal.back_to_live = uibutton(r, 'Text', 'Back to live', 'Visible', 'off', ...
            'ButtonPushedFcn', @(~,~) pauseLive(0), 'Tooltip', 'Show the live cameras again');
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
        if ~isfolder(d)
            ui.cal.table.Data = table();
            if ~isempty(d); logMsg(['Not a folder: ' d]); end
            return
        end
        showStatusTable(ui.cal.table, checkCalibrationFolder(d));
        labels = {savedImagePairs(d).label};
        if isempty(labels); labels = {'(none yet)'}; end
        previous = ui.cal.saved.Value;
        ui.cal.saved.Items = labels;
        if any(strcmp(labels, previous)); ui.cal.saved.Value = previous; end
    end

    function runCalibration()
        d = requireFolder(ui.cal.folder.Value, 'calibration');
        C = calibrateCameras(d, P, 'all'); % always recompute; it takes seconds
        drawnow
        if checkLightOrder(d, C)
            calibrateCameras(d, P, 'all'); % lights files were swapped
            drawnow
        end
        refreshCalibration();
        summarizeCalibration();
    end

    function toggleCameras()
        % Shared by the Calibration and Record behavior tabs
        if ~isempty(rec.state); error('Stop the recording first'); end
        if isempty(cams)
            cams = openEyeCameras(P.cam_serials);
            [ui.cap.connect.Text, ui.rec.connect.Text] = deal('Disconnect');
            [ui.cap.status.Text, ui.rec.status.Text] = deal(sprintf('Connected: cam1 %s, cam2 %s (exposure %.3f ms)', ...
                cams(1).serial, cams(2).serial, cams(1).src.ExposureTime/1000));
            setCaptureExposure();
            startLive();
        else
            stopLive();
            closeEyeCameras(cams);
            cams = [];
            [ui.cap.connect.Text, ui.rec.connect.Text] = deal('Connect cameras');
            [ui.cap.status.Text, ui.rec.status.Text] = deal('Not connected');
        end
    end

    function setCaptureExposure()
        % Fill in the selected item's exposure in ms (NaN = the camera's current setting) and hint
        item = selectedCaptureItem();
        ui.cap.hint.Text = item.hint;
        e = item.exposure_ms;
        if isnan(e) && ~isempty(cams)
            e = cams(1).src.ExposureTime/1000; % camera works in us
        end
        if ~isnan(e)
            ui.cap.exposure.Value = e;
            applyLiveExposure();
        end
    end

    function captureStill()
        % Save the current live frame from each camera for the selected item
        if ~isLive(); error('Connect the cameras first'); end
        d = requireFolder(ui.cal.folder.Value, 'calibration');
        pauseLive(Inf); % keep the saved frame on screen; back to live 2 s after we're done
        resume = onCleanup(@() pauseLive(2));
        I = {getsnapshot(cams(1).vid), getsnapshot(cams(2).vid)};
        exposure_ms = cams(1).src.ExposureTime/1000;
        item = selectedCaptureItem();
        ax = [ui.cal.ax1 ui.cal.ax2];
        ok = true(1, 2); result = cell(1, 2);
        for cam = 1:2
            [ok(cam), result{cam}] = showAndCheck(ax(cam), I{cam}, item.kind, sprintf('cam%i', cam), P);
        end
        msg = sprintf('%s, %.3f ms (%s)', item.label, exposure_ms, strjoin(result, '; '));
        if ~all(ok)
            msg = [msg ' (CHECK FAILED: retake this one)'];
        end
        files = captureFiles(d, item);
        short = strrep(files, [d filesep], '');
        exists = cellfun(@isfile, files);
        if any(exists)
            sel = uiconfirm(fig, sprintf('Overwrite %s?', strjoin(short(exists), ' and ')), 'Save images', ...
                'Options', {'Overwrite', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
            if ~strcmp(sel, 'Overwrite'); logMsg('Not saved.'); return; end
        end
        for cam = 1:2
            if ~isfolder(fileparts(files{cam})); mkdir(fileparts(files{cam})); end
            imwrite(I{cam}, files{cam});
        end
        msg = [msg ': saved ' strjoin(short, ', ')];
        refreshCalibration();
        setShownFiles(files);
        ui.cal.preview_label.Text = msg;
        logMsg(msg);
        if any(strcmp(item.kind, {'led', 'mirror'}))
            checkLightOrder(d, []);
        end
    end

    function swapped = checkLightOrder(d, C)
        % Light 1 must be the LED on the left in the cameras' view (the tracker
        % pairs corneal reflections left to right with lights 1 and 2). Once all
        % light images exist, locate the LEDs (quietly, using C if given) and
        % offer to swap the light 1 and 2 files if they're reversed.
        swapped = false;
        if isempty(C)
            if ~all(cellfun(@isfile, lightFiles(d))); return; end
            if min(numel(listImageFiles(fullfile(d, 'cam1'))), numel(listImageFiles(fullfile(d, 'cam2')))) < 4
                logMsg('Light order will be checked at Run calibration (needs 4+ checkerboard pairs first).');
                return
            end
            ui.cal.preview_label.Text = 'Checking which LED is light 1...'; drawnow
            try
                sp = myStereoCameraCalibrator(fullfile(d, 'cam1'), fullfile(d, 'cam2'), P.square_size, false);
                C = calibrateLights(d, sp, P.mirror_thickness, false);
            catch err
                logMsg(['Could not check the light order: ' err.message]);
                return
            end
        end
        if C.p_light1(1) <= C.p_light2(1)
            logMsg('Light order OK: light 1 is on the left.');
            return
        end
        sel = uiconfirm(fig, ['Light 1 is on the RIGHT in the cameras'' view, but should be on the left ' ...
            '(the tracker pairs corneal reflections left to right with light 1 and light 2). ' ...
            'Were the light 1 and light 2 images taken the wrong way round?'], 'Light order', ...
            'Options', {'Swap light 1 and 2 files', 'Keep as is'}, 'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
        if strcmp(sel, 'Swap light 1 and 2 files')
            swapLightFiles(d);
            logMsg('Swapped the light 1 and light 2 image files.');
            refreshCalibration();
            swapped = true;
        else
            logMsg('Kept the light files as they are (light 1 is on the right).');
        end
    end

    function startLive()
        % Stream both cameras and redraw the Preview ~10 times/s (stopLive ends it)
        live.saved = startEyeCamerasLive(cams, liveExposure()*1000); % ms -> us
        live.img = gobjects(1, 2); % image objects (a plain [] would store them as numbers)
        live.t0 = tic;
        live.resume_at = 0;
        live.timer = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.1, 'BusyMode', 'drop', ...
            'TimerFcn', @(~,~) updateLive());
        start(live.timer);
    end

    function stopLive()
        if ~isLive(); return; end
        stop(live.timer); delete(live.timer); live.timer = [];
        stopEyeCamerasLive(cams, live.saved);
        ui.cal.back_to_live.Visible = 'off';
    end

    function tf = isLive()
        tf = ~isempty(live.timer) && isvalid(live.timer);
    end

    function pauseLive(seconds)
        % Keep other images in Preview for this long (Inf = until Back to live)
        if ~isLive(); return; end
        live.resume_at = toc(live.t0) + seconds;
        ui.cal.back_to_live.Visible = isinf(seconds);
    end

    function updateLive()
        % Timer callback: show the newest frame from each camera
        if toc(live.t0) < live.resume_at; return; end
        try
            on_record = tg.SelectedTab == tab_rec;
            if on_record
                ax = [ui.rec.ax1 ui.rec.ax2];
            else
                ax = [ui.cal.ax1 ui.cal.ax2];
            end
            if ~all(isgraphics(live.img)) || ~isequal([live.img.Parent], ax) % first frame, other tab, or Preview was showing something else
                live.img = showFrames(ax, {getsnapshot(cams(1).vid), getsnapshot(cams(2).vid)});
                if on_record
                    ui.rec.preview_label.Text = 'Live (not recording)';
                else
                    setShownFiles({});
                    ui.cal.back_to_live.Visible = 'off';
                    ui.cal.preview_label.Text = 'Live';
                end
            end
            for cam = 1:2
                I = getsnapshot(cams(cam).vid);
                live.img(cam).CData = I;
                title(ax(cam), sprintf('cam%i live: %.1f%% saturated', cam, 100*mean(I(:) == 255)));
            end
            drawnow limitrate
        catch err
            stopLive();
            logMsg(['Live view stopped: ' err.message]);
        end
    end

    function moveLive()
        % Tab changed: show the live view in the new tab with that tab's exposure
        if ~isLive(); return; end
        live.resume_at = 0;
        ui.cal.back_to_live.Visible = 'off';
        applyLiveExposure();
    end

    function e = liveExposure()
        % (ms) the exposure box of the tab showing the live view
        if tg.SelectedTab == tab_rec
            e = ui.rec.exposure.Value;
        else
            e = ui.cap.exposure.Value;
        end
    end

    function applyLiveExposure()
        if ~isLive(); return; end
        for cam = 1:2
            setCameraExposure(cams(cam), liveExposure()*1000); % ms -> us
        end
    end

    function setShownFiles(files)
        shown_files = files(~cellfun(@isempty, files));
        ui.cal.delete.Enable = any(cellfun(@isfile, shown_files));
    end

    function deleteShownImages()
        files = shown_files(cellfun(@isfile, shown_files));
        if isempty(files); return; end
        d = ui.cal.folder.Value;
        short = strrep(files, [d filesep], '');
        sel = uiconfirm(fig, sprintf('Delete %s?', strjoin(short, ' and ')), 'Delete images', ...
            'Options', {'Delete', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
        if ~strcmp(sel, 'Delete'); return; end
        cellfun(@delete, files);
        logMsg(['Deleted ' strjoin(short, ', ')]);
        cla(ui.cal.ax1); cla(ui.cal.ax2);
        setShownFiles({});
        refreshCalibration();
    end

    function item = selectedCaptureItem()
        items = captureItems(P);
        item = items(strcmp({items.label}, ui.cap.what.Value));
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
        % Clicking a checklist row shows the matching saved images
        if isempty(evt.Indices); return; end
        item = ui.cal.table.Data.item{evt.Indices(1)};
        labels = ui.cal.saved.Items;
        if startsWith(item, 'Checkerboard')
            match = find(startsWith(labels, 'Checkerboard'), 1);
        elseif startsWith(item, 'Axes')
            match = find(strcmp(labels, 'Axes'), 1);
        else
            match = find(strcmp(labels, item), 1); % 'Light L, camC'
        end
        if isempty(match); return; end
        ui.cal.saved.Value = labels{match};
        showSaved(labels{match});
    end

    function showSaved(label)
        % Show one saved image pair in the Preview panel
        pauseLive(Inf);
        d = ui.cal.folder.Value;
        pairs = savedImagePairs(d);
        k = find(strcmp({pairs.label}, label), 1);
        if isempty(k); return; end
        files = pairs(k).files;
        ax = [ui.cal.ax1 ui.cal.ax2];
        ok = true(1, 2); result = cell(1, 2);
        for j = 1:2
            [~, name, ext] = fileparts(files{j});
            if isfile(files{j})
                [ok(j), result{j}] = showAndCheck(ax(j), imread(files{j}), pairs(k).kinds{j}, [name ext], P);
            else
                cla(ax(j)); result{j} = [name ext ': missing']; ok(j) = false;
                title(ax(j), result{j}, 'Interpreter', 'none');
            end
        end
        setShownFiles(files);
        msg = sprintf('%s: %s', label, strjoin(result, '; '));
        if ~all(ok); msg = [msg ' (CHECK FAILED: retake)']; end
        ui.cal.preview_label.Text = msg;
    end

%% ===================== Record behavior tab =====================
    function buildRecordTab()
        g = uigridlayout(tab_rec, [1 2], 'ColumnWidth', {480, '1x'});
        left = uigridlayout(g, [3 1], 'RowHeight', {96, 124, '1x'}, 'Padding', [0 0 0 0]);

        % 1. Session folder
        p = uipanel(left, 'Title', '1. Session folder', 'FontWeight', 'bold');
        pg = uigridlayout(p, [2 1], 'RowHeight', {26, 26}, 'Padding', [6 6 6 6]);
        r = uigridlayout(pg, [1 5], 'ColumnWidth', {35, 80, 45, 70, '1x'}, 'Padding', [0 0 0 0]);
        uilabel(r, 'Text', 'Bird:');
        ui.rec.bird = uieditfield(r, 'text', 'Placeholder', 'e.g. HC13');
        uilabel(r, 'Text', 'Date:', 'HorizontalAlignment', 'right');
        ui.rec.date = uieditfield(r, 'text', 'Value', char(datetime('today', 'Format', 'yyMMdd')));
        uibutton(r, 'Text', 'Create new folder', 'ButtonPushedFcn', @(~,~) runStep('Create session folder', @createSessionFolder, false), ...
            'Tooltip', 'Make <behavior session root>\<bird>_<YYMMDD> (adding b, c, ... if it exists)');
        r = uigridlayout(pg, [1 2], 'ColumnWidth', {'1x', 70}, 'Padding', [0 0 0 0]);
        ui.rec.folder = uieditfield(r, 'text', 'Placeholder', 'Session folder, e.g. Z:\...\behavior\HC13_230525');
        uibutton(r, 'Text', 'Browse', 'ButtonPushedFcn', @(~,~) browseRecordFolder());

        % 2. Cameras
        p = uipanel(left, 'Title', '2. Cameras', 'FontWeight', 'bold');
        pg = uigridlayout(p, [3 1], 'RowHeight', {26, 26, 26}, 'Padding', [6 4 6 4]);
        r = uigridlayout(pg, [1 2], 'ColumnWidth', {140, '1x'}, 'Padding', [0 0 0 0]);
        ui.rec.connect = uibutton(r, 'Text', 'Connect cameras', 'ButtonPushedFcn', @(~,~) runStep('Connect cameras', @toggleCameras, true), ...
            'Tooltip', 'Connect to both cameras and show them live in Preview (same connection as the Calibration tab)');
        ui.rec.status = uilabel(r, 'Text', 'Not connected');
        r = uigridlayout(pg, [1 2], 'ColumnWidth', {95, 80}, 'Padding', [0 0 0 0]);
        uilabel(r, 'Text', 'Exposure (ms):');
        ui.rec.exposure = uieditfield(r, 'numeric', 'Limits', [0.012 1000], 'Value', P.record_exposure_ms, ...
            'HorizontalAlignment', 'left', 'ValueDisplayFormat', '%.3f', 'ValueChangedFcn', @(~,~) applyLiveExposure(), ...
            'Tooltip', sprintf('At least 2 ms below the frame interval (%.0f ms at %g Hz)', 1000/P.eye_fps, P.eye_fps));
        r = uigridlayout(pg, [1 2], 'ColumnWidth', {95, '1x'}, 'Padding', [0 0 0 0]);
        uilabel(r, 'Text', 'Save as:');
        ui.rec.format = uidropdown(r, 'Items', {'Compressed (GPU H.264, .mp4)', 'Raw (uncompressed .avi)'}, ...
            'ItemsData', {'h264', 'raw'}, 'Tooltip', ['Compressed: ~0.13 MB/frame (~45 GB/hour for both cameras), ' ...
            'about 1 gray level from raw; fine to write straight to Z:. ' ...
            'Raw: lossless but 2.8 MB/frame (~1 TB/hour); record to a local SSD, not Z:.']);

        % 3. Record
        p = uipanel(left, 'Title', '3. Record (synchronized by QTM''s trigger)', 'FontWeight', 'bold');
        pg = uigridlayout(p, [3 1], 'RowHeight', {'1x', 32, 44}, 'Padding', [6 6 6 6]);
        helpLabel(pg, ['a. In QTM click Record, set the folder to this session folder and the file name to qtm, ' ...
            'and start. QTM waits for the space bar.' newline ...
            'b. Click Record here. The cameras now wait for QTM''s trigger pulses.' newline ...
            'c. Press the space bar in QTM. Both frame counts should climb together.' newline ...
            'd. Stop QTM first, then click Stop here.' newline ...
            'e. In QTM export the head rigid body (6DOF) to qtm.mat in the session folder.']);
        r = uigridlayout(pg, [1 2], 'Padding', [0 0 0 0]);
        ui.rec.start = uibutton(r, 'Text', 'Record', 'FontWeight', 'bold', 'FontColor', [0.75 0 0], ...
            'ButtonPushedFcn', @(~,~) runStep('Record', @startRecording, false), ...
            'Tooltip', 'Arm both cameras on the hardware trigger and save every frame into the session folder');
        ui.rec.stop = uibutton(r, 'Text', 'Stop', 'Enable', 'off', ...
            'ButtonPushedFcn', @(~,~) runStep('Stop recording', @stopRecording, false), ...
            'Tooltip', 'Stop QTM first. Finishes writing both videos and reports frame counts');
        ui.rec.count = uilabel(pg, 'Text', '', 'FontSize', 14, 'FontWeight', 'bold', 'WordWrap', 'on');

        p = uipanel(g, 'Title', 'Preview', 'FontWeight', 'bold');
        right = uigridlayout(p, [2 2], 'RowHeight', {22, '1x'}, 'Padding', [6 6 6 6]);
        ui.rec.preview_label = uilabel(right, 'Text', 'Connect the cameras to see them live');
        ui.rec.preview_label.Layout.Column = [1 2];
        ui.rec.ax1 = uiaxes(right); ui.rec.ax2 = uiaxes(right);
        prepImageAxes([ui.rec.ax1 ui.rec.ax2]);
    end

    function createSessionFolder()
        bird = strtrim(ui.rec.bird.Value);
        date = strtrim(ui.rec.date.Value);
        if isempty(regexp(bird, '^\w+$', 'once')); error('Enter the bird ID (letters and numbers)'); end
        if isempty(regexp(date, '^\d{6}$', 'once')); error('Use a six-digit date, YYMMDD'); end
        d = fullfile(P.data_root, [bird '_' date]);
        suffix = 'b';
        while isfolder(d)
            d = fullfile(P.data_root, [bird '_' date suffix]);
            suffix = char(suffix + 1);
        end
        mkdir(d);
        ui.rec.folder.Value = d;
        logMsg(['Created ' d]);
    end

    function browseRecordFolder()
        start = ui.rec.folder.Value;
        if ~isfolder(start); start = P.data_root; end
        d = uigetdir(start, 'Select session folder to record into');
        figure(fig);
        if ischar(d); ui.rec.folder.Value = d; end
    end

    function startRecording()
        if isempty(cams); error('Connect the cameras first'); end
        d = requireFolder(ui.rec.folder.Value, 'session');
        format = ui.rec.format.Value;
        if strcmp(format, 'raw') && isNetworkFolder(d)
            sel = uiconfirm(fig, ['Raw video is ~140 MB/s per camera, faster than a network drive can usually take. ' ...
                'Record raw to a local SSD instead?'], 'Raw to network drive', ...
                'Options', {'Record here anyway', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
            if ~strcmp(sel, 'Record here anyway'); return; end
        end
        stopLive();
        try
            rec.state = startEyeRecording(cams, d, format, P, ui.rec.exposure.Value*1000); % ms -> us
        catch err
            startLive(); % back to the live view, then report the error
            rethrow(err);
        end
        rec.img = gobjects(1, 2);
        rec.t0 = tic;
        rec.timer = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.5, 'BusyMode', 'drop', ...
            'TimerFcn', @(~,~) updateRecording());
        start(rec.timer);
        [ui.rec.start.Enable, ui.rec.connect.Enable, ui.cap.connect.Enable] = deal('off');
        ui.rec.stop.Enable = 'on';
        ui.rec.preview_label.Text = 'Armed: waiting for QTM';
        ui.rec.count.Text = 'Now press the space bar in QTM.';
        logMsg(sprintf('Recording armed (%s) into %s. Press the space bar in QTM.', format, d));
        logMsg(sprintf('Trigger: cam1 %s; cam2 %s', rec.state.trigger{:}));
        rec.n_prev = [0 0]; rec.t_prev = 0;
    end

    function updateRecording()
        % Timer callback: frame counts and the newest frames
        try
            n = [rec.state.cams(1).vid.FramesAcquired, rec.state.cams(2).vid.FramesAcquired];
            if all(n == 0); return; end
            s = [rec.state.cams(1).vid.UserData, rec.state.cams(2).vid.UserData];
            t = toc(rec.t0);
            fps = (n - rec.n_prev)/(t - rec.t_prev); % frames per second since the last update (= trigger rate)
            rec.n_prev = n; rec.t_prev = t;
            ui.rec.count.Text = sprintf('Recording: cam1 %i, cam2 %i frames (%.0f, %.0f fps)', n, fps);
            if any(~cellfun(@isempty, {s.error}))
                ui.rec.count.Text = [ui.rec.count.Text ' (ERROR: ' strjoin({s.error}, '; ') ')'];
            end
            if isempty(s(1).last) || isempty(s(2).last); return; end
            ax = [ui.rec.ax1 ui.rec.ax2];
            if ~all(isgraphics(rec.img))
                rec.img = showFrames(ax, {s.last});
                ui.rec.preview_label.Text = 'Recording (preview updates every 0.5 s)';
            else
                [rec.img.CData] = s.last;
            end
            drawnow limitrate
        catch err
            ui.rec.count.Text = ['Preview error: ' err.message];
        end
    end

    function stopRecording()
        if isempty(rec.state); return; end
        stop(rec.timer); delete(rec.timer);
        ui.rec.preview_label.Text = 'Finishing the videos...'; drawnow
        result = stopEyeRecording(rec.state);
        rec.state = [];
        [ui.rec.start.Enable, ui.rec.connect.Enable, ui.cap.connect.Enable] = deal('on');
        ui.rec.stop.Enable = 'off';
        msg = sprintf('Stopped. cam1: %i frames acquired, %i written. cam2: %i acquired, %i written.', ...
            result.acquired(1), result.written(1), result.acquired(2), result.written(2));
        problems = {};
        if result.acquired(1) ~= result.acquired(2); problems{end+1} = 'the cameras got different numbers of frames'; end
        if any(result.written ~= result.acquired); problems{end+1} = 'not every frame was written'; end
        if any(result.acquired == 0); problems{end+1} = 'a camera got no frames (trigger cable? QTM Out 2?)'; end
        errs = result.error(~cellfun(@isempty, result.error));
        problems = [problems errs(:)'];
        if isempty(problems)
            ui.rec.count.Text = 'Done. Now export qtm.mat from QTM.';
        else
            msg = [msg ' PROBLEM: ' strjoin(problems, '; ')];
            ui.rec.count.Text = ['Check: ' strjoin(problems, '; ')];
        end
        logMsg(msg);
        logMsg(['Files: ' strjoin(result.file, ', ') '. Export the QTM 6DOF data to qtm.mat in the same folder.']);
        if ~isempty(problems); uialert(fig, msg, 'Recording', 'Icon', 'warning'); end
        ui.ses.folder.Value = fileparts(result.file{1}); % ready in the Analyze behavior tab
        startLive();
    end

%% ===================== Analyze behavior tab =====================
    function buildSessionTab()
        g = uigridlayout(tab_ses, [1 2], 'ColumnWidth', {500, '1x'});
        left = uigridlayout(g, [9 1], 'RowHeight', {92, 26, 26, 26, 185, '1x', 28, 32, 26}, 'Padding', [0 0 0 0]);
        helpLabel(left, ['1. Pick a behavior session folder (cam1 and cam2 videos, qtm.mat). Must have a calibration present from the same day (YYMMDD).' newline ...
            '2. Step through frames with Eyetrack preview checked and tune the tracker (yellow = pupil fit, circles = CRs). Draw a crop to speed tracking. ' ...
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

        r = uigridlayout(left, [1 2], 'ColumnWidth', {'1x', 150}, 'Padding', [0 0 0 0]);
        ui.ses.skip = uicheckbox(r, 'Text', 'Skip frames without the bird', 'Value', P.skip_empty_frames, ...
            'ValueChangedFcn', @(src,~) skipChanged(src.Value), ...
            'Tooltip', ['Track and preview only frames where the bird is in view (background subtraction on shrunken frames, ' ...
            'thresholds in eyetrackParams.m). Skipped frames stay NaN']);
        uibutton(r, 'Text', 'Find bird frames', 'ButtonPushedFcn', @(~,~) runStep('Find bird frames', @showBirdFrames, true), ...
            'Tooltip', 'Find and plot the frames with the bird in view (cached in bird_frames.mat; ~1 min the first time)');

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
        ui.ses.beak = uibutton(r, 'state', 'Text', '1. Label beak', 'ValueChangedFcn', @(src,~) labelBeak(src.Value), ...
            'Tooltip', ['On: click the beak tip in cam1, then cam2, on the frames shown (5-10 head poses), ' ...
            'stepping with the frame controls. Each pair is saved to beak.mat right away. Right click skips a frame, Esc undoes the last click. Click again to finish']);
        uibutton(r, 'Text', '2. Track eyes', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~) runStep('Tracking', @trackSession, false), ...
            'Tooltip', 'Track pupil and CRs in every frame, then triangulate. Resumes a stopped run; skips tracking if eye.mat is complete');
        uibutton(r, 'Text', 'Stop tracking', 'ButtonPushedFcn', @(~,~) requestStop(), ...
            'Tooltip', 'Save progress to eye.mat and stop after the current frame. Track eyes resumes from there');
        uibutton(r, 'Text', '3. Analyze', 'ButtonPushedFcn', @(~,~) runStep('Behavior analysis', @analyzeSession, false), ...
            'Tooltip', 'Fit eye and beak positions in the head frame for this session (runEyetrackSingle) and save head_calibration.mat');

        r = uigridlayout(left, [1 3], 'ColumnWidth', {80, '1x', 150}, 'Padding', [0 0 0 0]);
        uilabel(r, 'Text', 'Beak labels:');
        ui.ses.beak_list = uidropdown(r, 'Items', {'(Label beak to review)'}, 'Enable', 'off', ...
            'ValueChangedFcn', @(src,~) goToFrame(src.Value, true), ...
            'Tooltip', 'Frames with beak clicks: pick one to show it (while Label beak is on)');
        ui.ses.beak_delete = uibutton(r, 'Text', 'Delete label on this frame', 'Enable', 'off', ...
            'ButtonPushedFcn', @(~,~) deleteBeakLabel(), ...
            'Tooltip', 'Remove the beak clicks on the frame shown from beak.mat (while Label beak is on)');

        right = uigridlayout(g, [4 2], 'RowHeight', {28, 24, '1x', 22}, 'Padding', [0 0 0 0]);
        r = uigridlayout(right, [1 9], 'ColumnWidth', {45, 80, 45, 38, 38, 45, 125, 80, '1x'}, 'Padding', [0 0 0 0]);
        r.Layout.Column = [1 2];
        uilabel(r, 'Text', 'Frame');
        ui.ses.frame = uispinner(r, 'Limits', [1 Inf], 'Value', 1, 'RoundFractionalValues', 'on', 'Step', 1, ...
            'ValueDisplayFormat', '%.0f', 'HorizontalAlignment', 'left', ...
            'ValueChangedFcn', @(src,~) goToFrame(src.Value), 'Tooltip', 'Video frame to preview');
        n = P.preview_step_frames;
        % {frames to move, button text, tooltip}
        steps = {-n, sprintf('<< %i', n), sprintf('Back %i frames', n); -1, '<', 'Back 1 frame'; ...
                  1, '>', 'Ahead 1 frame'; n, sprintf('%i >>', n), sprintf('Ahead %i frames', n)};
        for k = 1:size(steps, 1)
            step = steps{k, 1};
            uibutton(r, 'Text', steps{k, 2}, 'Tooltip', steps{k, 3}, ...
                'ButtonPushedFcn', @(~,~) goToFrame(ui.ses.frame.Value + step));
        end
        ui.ses.detect = uicheckbox(r, 'Text', 'Eyetrack preview', 'Value', true, ...
            'ValueChangedFcn', @(~,~) previewFrame(), ...
            'Tooltip', ['Run the tracker with the current settings on the frame shown, in both cameras, ' ...
            'and again whenever the frame or a setting changes. Unchecked: just show the (cropped) frames']);
        uibutton(r, 'Text', 'Full frame', 'ButtonPushedFcn', @(~,~) runStep('Full frame', @showFullFrames, false), ...
            'Tooltip', 'Show the uncropped frames with the crop boxes in yellow');
        ui.ses.frame_label = uilabel(r, 'Text', '');
        ui.ses.slider = uislider(right, 'Limits', [1 2], 'Value', 1, 'MajorTicks', [], 'MinorTicks', [], ...
            'ValueChangedFcn', @(src,~) goToFrame(src.Value), 'Tooltip', 'Whole session: drag to a frame and release to preview it');
        ui.ses.slider.Layout.Column = [1 2];
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
        if ~isempty(beak) && ~strcmp(vids.folder, d) % another session: stop labeling (clicks are already saved)
            ui.ses.detect.Value = beak.detect_was;
            beak = [];
            fig.WindowKeyPressFcn = '';
            enableBeakReview(false);
            ui.ses.beak.Value = false; ui.ses.beak.Text = '1. Label beak';
        end
        vids = struct('folder', '', 'v1', [], 'v2', [], 'N', 0, 'in_view', []);
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
            ui.ses.frame.Value = 1;
            ui.ses.slider.Limits = [1 max(2, min(info.N_eye))];
            goToFrame(1); % show the first frame (the first with the bird when skipping)
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
        if ui.ses.detect.Value && isfolder(ui.ses.folder.Value)
            previewFrame(); % redo detection with the new setting
        end
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
            vids = struct('folder', d, 'v1', v1, 'v2', v2, 'N', N, 'in_view', []);
        end
    end

    function showFrame()
        % Show the current frame (cropped) in both cameras; with "Eyetrack
        % preview" checked, also run the tracker on it and draw the fits
        openVideos();
        ii = min(vids.N, ui.ses.frame.Value);
        p = p_track;
        [p.plot_on] = deal(1);
        [p.pupil_start] = deal([NaN NaN]);
        [I1, I2] = readEyeFrames(vids.v1, vids.v2, ii, p);
        ax = [ui.ses.ax1 ui.ses.ax2];
        I = {I1, I2};
        ui.ses.frame_label.Text = sprintf('t = %.2f s of %.1f s', ii / vids.v1.FrameRate, vids.N / vids.v1.FrameRate);
        detect = ui.ses.detect.Value;
        fit_txt = cell(1,2);
        for cam = 1:2
            % Reuse the image and fit lines (only their data changes, ~50x faster
            % than redrawing) unless they're gone or the image size changed
            h = frame_plots{cam};
            if ~isfield(h, 'img') || ~isgraphics(h.img) || ~isequal(size(h.img.CData), size(I{cam})) ...
                    || (detect && ~isfield(h, 'pupil_line'))
                cla(ax(cam));
                h = struct('ah', ax(cam));
            end
            if detect
                [pupil, cr, ~, resid, points] = detectPupilCR(I{cam}, p(cam).edge_thresh0, p(cam));
                crs = squeeze(cr);
                h = detectPupilCRPlot(I{cam}, p(cam), h, pupil, crs, points);
                fit_txt{cam} = sprintf('cam%i: pupil radius %.1f px, fit residual %.2f (max %.2f), %i of %i CRs', cam, ...
                    max(pupil(3:4)), resid, p(cam).ellipse_residual_thresh, nnz(~isnan(crs(1,:))), p(cam).nCRs);
                title(ax(cam), sprintf('cam%i', cam));
            else
                if ~isfield(h, 'img')
                    h.img = imagesc(ax(cam), I{cam}); colormap(ax(cam), gray); axis(ax(cam), 'image');
                else
                    h.img.CData = I{cam};
                end
                title(ax(cam), sprintf('cam%i (detection off)', cam));
            end
            set(findobj(ax(cam), 'Type', 'line'), 'Visible', detect); % pupil and CR fits
            cam_k = cam;
            h.img.ButtonDownFcn = @(~,evt) beakClick(cam_k, evt); % only acts while labeling the beak
            frame_plots{cam} = h;
        end
        drawBeak();
        ui.ses.progress.Text = strjoin(fit_txt(~cellfun(@isempty, fit_txt)), '   |   ');
        drawnow limitrate
    end

    function previewFrame()
        % showFrame without runStep's busy indicator, which cost more than the
        % frame itself (~90 ms vs ~50 ms per step); errors still go to the log
        try
            showFrame();
        catch err
            logMsg(['Preview failed: ' err.message]);
        end
    end

    function goToFrame(ii, exact)
        % Spinner, step buttons, and slider all land here: move to frame ii and
        % preview it. With "Skip frames without the bird" checked, a frame without
        % the bird moves on to the next one with it (searching back if none
        % ahead), unless exact (reviewing a labeled frame).
        if nargin < 2; exact = false; end
        ii = round(min(max(ii, ui.ses.frame.Limits(1)), ui.ses.frame.Limits(2)));
        if ui.ses.skip.Value && ~exact
            if ~isfile(fullfile(ui.ses.folder.Value, 'bird_frames.mat')) % not computed yet: ~1 min, show progress
                runStep('Find bird frames', @birdFrames, true);
                if isempty(vids.in_view); return; end % failed (reported by runStep)
            end
            in_view = birdFrames();
            if ii <= numel(in_view) && ~in_view(ii)
                ahead = ii + find(in_view(ii:end), 1) - 1;
                back = find(in_view(1:ii), 1, 'last');
                if ii < ui.ses.frame.Value % moving back: prefer the bird frame before
                    candidates = [back ahead];
                else
                    candidates = [ahead back];
                end
                if isempty(candidates); logMsg('No frames with the bird in this session.'); return; end
                ii = candidates(1);
            end
        end
        if ~isempty(beak) && ii ~= ui.ses.frame.Value
            beak.pending = []; % a cam1 click without its cam2 click is dropped
        end
        ui.ses.frame.Value = ii;
        ui.ses.slider.Value = min(max(ii, ui.ses.slider.Limits(1)), ui.ses.slider.Limits(2));
        previewFrame();
    end

    function skipChanged(skip)
        % Checked: move the preview off a frame without the bird
        if skip && isfolder(ui.ses.folder.Value)
            goToFrame(ui.ses.frame.Value);
        end
    end

    function in_view = birdFrames()
        % findBirdFrames for this session (computed and saved the first time, ~1 min)
        openVideos();
        if isempty(vids.in_view)
            B = findBirdFrames(vids.folder, P.camfilename, P, false, @setStepProgress);
            vids.in_view = B.in_view;
            showStatusTable(ui.ses.table, checkSessionFolder(vids.folder, P)); % lists bird_frames.mat
        end
        in_view = vids.in_view;
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

    function labelBeak(on)
        % Beak labeling in the preview: click the beak tip in cam1, then cam2,
        % on the frame shown; the pair is saved to beak.mat (same format as
        % getBeak: p1, p2 = N x 2 full-frame pixels, NaN = not clicked) and the
        % preview jumps ahead P.preview_step_frames.
        d = ui.ses.folder.Value;
        if on
            try
                openVideos();
            catch err
                ui.ses.beak.Value = false; logMsg(['Label beak: ' err.message]); return
            end
            f = fullfile(d, 'beak.mat');
            if isfile(f)
                s = load(f, 'p1', 'p2');
                beak = struct('p1', s.p1, 'p2', s.p2);
            else
                beak = struct('p1', NaN(vids.N, 2), 'p2', NaN(vids.N, 2));
            end
            beak.pending = [];
            beak.history = []; % frames labeled this time, newest last (Esc undoes)
            beak.detect_was = ui.ses.detect.Value;
            ui.ses.detect.Value = false; % fits off while labeling
            ui.ses.beak.Text = '1. Done labeling';
            fig.WindowKeyPressFcn = @(~,evt) beakKey(evt);
            enableBeakReview(true);
            logMsg(sprintf(['Label beak: click the beak tip in cam1, then in cam2. Right click skips the frame, ' ...
                'Esc undoes the last click. %i frames labeled so far. Click Done labeling to finish.'], nnz(~isnan(beak.p1(:,1)))));
            previewFrame();
        else
            if isempty(beak); return; end
            ui.ses.detect.Value = beak.detect_was;
            n = nnz(~isnan(beak.p1(:,1)));
            beak = [];
            fig.WindowKeyPressFcn = '';
            enableBeakReview(false);
            ui.ses.beak.Text = '1. Label beak';
            % 3D points are cached; recompute them with the new beak clicks
            if isfile(fullfile(d, 'eye_triangulate.mat')); delete(fullfile(d, 'eye_triangulate.mat')); end
            logMsg(sprintf('Label beak done: %i frames labeled in beak.mat.', n));
            showStatusTable(ui.ses.table, checkSessionFolder(d, P)); % beak.mat row; stay on this frame
            previewFrame(); % redraw with the Eyetrack preview setting restored
        end
    end

    function beakClick(cam, evt)
        % Click on a preview image while labeling: cam1 first, then cam2.
        % Right click skips this frame (jumps ahead without saving).
        if isempty(beak); return; end
        ii = ui.ses.frame.Value;
        if (isprop(evt, 'Button') || isfield(evt, 'Button')) && evt.Button == 3
            goToFrame(ii + P.preview_step_frames);
            return
        end
        xy = evt.IntersectionPoint(1:2) + cropOffset(cam); % to full-frame pixels
        if cam == 1
            beak.pending = xy;
            drawBeak();
            ui.ses.progress.Text = sprintf('Frame %i: now click the beak tip in cam2', ii);
        elseif isempty(beak.pending)
            ui.ses.progress.Text = 'Click the beak tip in cam1 first';
        else
            beak.p1(ii,:) = beak.pending;
            beak.p2(ii,:) = xy;
            beak.pending = [];
            beak.history(end+1) = ii; % for Esc = undo
            saveBeak();
            drawBeak();
            ui.ses.progress.Text = sprintf('Saved beak on frame %i (%i frames labeled)', ii, nnz(~isnan(beak.p1(:,1))));
            goToFrame(ii + P.preview_step_frames);
        end
    end

    function beakKey(evt)
        % Esc while labeling: undo the last click (a pending cam1 click, or
        % the last saved pair, going back to its frame)
        if isempty(beak) || ~strcmp(evt.Key, 'escape'); return; end
        if ~isempty(beak.pending)
            beak.pending = [];
            drawBeak();
            ui.ses.progress.Text = 'Undid the cam1 click';
        elseif ~isempty(beak.history)
            ii = beak.history(end);
            beak.history(end) = [];
            beak.p1(ii,:) = NaN; beak.p2(ii,:) = NaN;
            saveBeak();
            goToFrame(ii);
            ui.ses.progress.Text = sprintf('Undid the beak on frame %i (%i frames labeled)', ii, nnz(~isnan(beak.p1(:,1))));
        end
    end

    function deleteBeakLabel()
        % Remove the beak clicks on the frame shown
        if isempty(beak); return; end
        ii = ui.ses.frame.Value;
        if ii > size(beak.p1, 1) || isnan(beak.p1(ii,1))
            ui.ses.progress.Text = sprintf('Frame %i has no beak label', ii); return
        end
        beak.p1(ii,:) = NaN; beak.p2(ii,:) = NaN;
        beak.history(beak.history == ii) = [];
        saveBeak();
        drawBeak();
        ui.ses.progress.Text = sprintf('Deleted the beak on frame %i (%i frames labeled)', ii, nnz(~isnan(beak.p1(:,1))));
    end

    function updateBeakList()
        % Dropdown of labeled frames, selecting the one shown if it's labeled
        labeled = find(~isnan(beak.p1(:,1)))';
        if isempty(labeled)
            ui.ses.beak_list.ItemsData = {}; ui.ses.beak_list.Items = {'(none yet)'};
            return
        end
        ui.ses.beak_list.ItemsData = {};
        ui.ses.beak_list.Items = arrayfun(@(k) sprintf('frame %i', k), labeled, 'UniformOutput', false);
        ui.ses.beak_list.ItemsData = num2cell(labeled);
        if any(labeled == ui.ses.frame.Value); ui.ses.beak_list.Value = ui.ses.frame.Value; end
    end

    function saveBeak()
        p1 = beak.p1; p2 = beak.p2; ii = ui.ses.frame.Value; % saved below
        save(fullfile(vids.folder, 'beak.mat'), 'p1', 'p2', 'ii');
        updateBeakList();
    end

    function enableBeakReview(on)
        [ui.ses.beak_list.Enable, ui.ses.beak_delete.Enable] = deal(on);
        if on
            updateBeakList();
        else
            ui.ses.beak_list.ItemsData = {}; ui.ses.beak_list.Items = {'(Label beak to review)'};
        end
    end

    function drawBeak()
        % Red + on the beak clicks for the frame shown (and a pending cam1 click)
        ax = [ui.ses.ax1 ui.ses.ax2];
        delete(findobj(ax, 'Tag', 'beak'));
        if isempty(beak); return; end
        ii = ui.ses.frame.Value;
        if any(cellfun(@(k) isequal(k, ii), ui.ses.beak_list.ItemsData)); ui.ses.beak_list.Value = ii; end
        pts = {beak.p1(ii,:), beak.p2(ii,:)};
        if ~isempty(beak.pending); pts{1} = beak.pending; end
        for cam = 1:2
            xy = pts{cam} - cropOffset(cam);
            if any(isnan(xy)); continue; end
            line(ax(cam), xy(1), xy(2), 'Marker', '+', 'Color', 'r', 'MarkerSize', 30, 'LineWidth', 1.5, ...
                'Tag', 'beak', 'PickableParts', 'none');
        end
    end

    function xy = cropOffset(cam)
        % Preview images are cropped to p_track(cam).cropX/cropY; beak.mat is in full-frame pixels
        xy = [0 0];
        if ~isempty(p_track(cam).cropX)
            xy = [p_track(cam).cropX(1) p_track(cam).cropY(1)] - 1;
        end
    end

    function showBirdFrames()
        d = requireFolder(ui.ses.folder.Value, 'behavior session');
        B = findBirdFrames(d, P.camfilename, P, true, @setStepProgress);
        if strcmp(vids.folder, d); vids.in_view = B.in_view; end % used by the preview navigation
        showStatusTable(ui.ses.table, checkSessionFolder(d, P)); % lists bird_frames.mat
    end

    function trackSession()
        d = requireFolder(ui.ses.folder.Value, 'behavior session');
        stop_requested = false;
        opts = struct;
        opts.P = P;
        opts.skip_empty_frames = ui.ses.skip.Value;
        opts.ah = [ui.ses.ax1 ui.ses.ax2];
        opts.stop_fcn = @checkStop;
        opts.progress_fcn = @trackProgress;
        cla(ui.ses.ax1); cla(ui.ses.ax2);
        if opts.skip_empty_frames
            findBirdFrames(d, P.camfilename, P, false, @setStepProgress); % first, so its progress shows too (cached for trackEye)
            step_progress = NaN;
        end
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

    function trackProgress(done, total)
        ui.ses.progress.Text = sprintf('Tracked %i / %i frames', done, total);
        setStepProgress(done/max(1, total));
    end

    function setStepProgress(f)
        step_progress = f;
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
            'untracked behavior sessions are tracked first, with src/defaultTrackerParams.m (not the Analyze behavior tab settings). ' ...
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
    function closeGUI()
        if ~isempty(rec.state)
            sel = uiconfirm(fig, 'Stop the recording and close?', 'Recording', ...
                'Options', {'Stop and close', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
            if ~strcmp(sel, 'Stop and close'); return; end
        end
        delete(fig); % releaseCameras runs as the figure's DeleteFcn
    end

    function releaseCameras()
        % Figure deleted (closed, or deleted any other way): finish any
        % recording and disconnect, so SpinView or a new GUI can open the cameras.
        % Each step is attempted even if an earlier one fails.
        steps = {@() stop(rec.timer), @() delete(rec.timer), @() stopEyeRecording(rec.state), ...
            @() stopLive(), @() closeEyeCameras(cams)};
        if isempty(rec.state); steps(1:3) = []; end
        for s = steps
            try
                s{1}();
            catch err
                fprintf(2, 'eyetrackGUI closing: %s\n', err.message);
            end
        end
        rec.state = []; cams = [];
    end

    function runStep(name, fn, capture)
        % Run fn, report errors in the log and a dialog. If capture, copy the
        % command window output into the log. The status bar only shows what's
        % running (with moving dots and elapsed time); results go to the log,
        % "done" only for steps over 2 s so quick clicks don't fill it.
        t0 = tic;
        step_progress = NaN;
        busy = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.5, 'BusyMode', 'drop', ...
            'TimerFcn', @(src,~) showBusy(name, src.TasksExecuted, toc(t0)));
        status_label.Text = [name '...'];
        fig.Pointer = 'watch';
        drawnow
        start(busy);
        if capture
            tmp = [tempname '.txt'];
            diary(tmp);
        end
        try
            fn();
            ok = true;
        catch err
            ok = false;
        end
        stop(busy); delete(busy);
        if isvalid(fig); status_label.Text = 'Ready'; end
        if capture
            diary off
            if isfile(tmp)
                txt = fileread(tmp);
                delete(tmp);
                if ~isempty(strtrim(txt)); logMsg(strtrim(txt)); end
            end
        end
        if isvalid(fig); fig.Pointer = 'arrow'; end
        if ok && toc(t0) > 2
            logMsg(sprintf('%s done (%.0f s)', name, toc(t0)));
        end
        if ~ok
            logMsg(sprintf('%s failed: %s', name, err.message));
            fprintf(2, '%s\n', getReport(err, 'extended', 'hyperlinks', 'off'));
            if isvalid(fig); uialert(fig, err.message, [name ' failed']); end
        end
    end

    function showBusy(name, n, elapsed)
        % Status bar while a step runs: moving dots, elapsed time, and % done if known
        txt = sprintf('%s%s  %.0f s', name, repmat('.', 1, mod(n, 4)), elapsed);
        if ~isnan(step_progress)
            txt = sprintf('%s  (%.0f%% done)', txt, 100*step_progress);
        end
        status_label.Text = txt;
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
    % only the fields editable in the Settings tab; the rest always come from eyetrackParams.m
    editable = {'calib_root', 'data_root', 'square_size', 'axes_thresh', 'downsample_eye', 'beak_skip_frames'};
    fn = intersect(fieldnames(saved), editable);
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

function img = showFrames(ax, I)
% Draw one gray frame per axes; returns the image objects for updating CData
img = gobjects(1, numel(ax));
for k = 1:numel(ax)
    cla(ax(k));
    img(k) = imagesc(ax(k), I{k}, [0 255]);
    colormap(ax(k), gray); axis(ax(k), 'image');
    ax(k).XTick = []; ax(k).YTick = [];
end
end

function tf = isNetworkFolder(d)
% True for \\server\... paths and mapped network drives like Z:
tf = startsWith(d, '\\');
if ~tf && numel(d) > 1 && d(2) == ':'
    tf = System.IO.DriveInfo(d(1)).DriveType == System.IO.DriveType.Network;
end
end

function items = captureItems(P)
% Calibration images the Capture panel can take. exposure_ms is in ms (NaN =
% the camera's current setting); file is where each camera's image is saved,
% with %i = camera number and <next> = the next unused checkerboard pair number;
% hint is shown under the dropdown when the item is selected; kind picks the
% check run right after capture (showAndCheck).
items = struct( ...
    'label', {'Checkerboard pair', 'Light 1: LED spot', 'Light 1: mirror checkerboard', ...
              'Light 2: LED spot', 'Light 2: mirror checkerboard', 'Axes triangle'}, ...
    'exposure_ms', {NaN, P.exposure_led_spot_ms, P.exposure_mirror_checkerboard_ms, ...
                    P.exposure_led_spot_ms, P.exposure_mirror_checkerboard_ms, NaN}, ...
    'file', {'cam%i\<next>.bmp', 'lights\cam%i_light1.bmp', 'lights\cam%i_light1_checkerboard.bmp', ...
             'lights\cam%i_light2.bmp', 'lights\cam%i_light2_checkerboard.bmp', 'axes\cam%i.bmp'}, ...
    'kind', {'checkerboard', 'led', 'mirror', 'led', 'mirror', 'axes'}, ...
    'hint', {'Hold the checkerboard still in a new position and angle for each pair (4-10 pairs).', ...
             'Orient the mirror so light 1 is visible in both cameras. Save the LED spot and the mirror checkerboard without moving anything.', ...
             'Orient the mirror so light 1 is visible in both cameras. Save the LED spot and the mirror checkerboard without moving anything.', ...
             'Orient the mirror so light 2 is visible in both cameras. Save the LED spot and the mirror checkerboard without moving anything.', ...
             'Orient the mirror so light 2 is visible in both cameras. Save the LED spot and the mirror checkerboard without moving anything.', ...
             'Also record the triangle in QTM and export axes\qtm.mat with markers labeled p0, px, py.'});
end

function files = lightFiles(d)
% All 8 light images: cam1/cam2 x light 1/2 x LED spot/mirror checkerboard
files = {};
for cam = 1:2
    for light = 1:2
        base = fullfile(d, 'lights', sprintf('cam%i_light%i', cam, light));
        files = [files, {[base '.bmp'], [base '_checkerboard.bmp']}]; %#ok<AGROW>
    end
end
end

function swapLightFiles(d)
% Rename light 1 images to light 2 and vice versa (both cameras, both kinds)
for cam = 1:2
    for suffix = {'', '_checkerboard'}
        f1 = fullfile(d, 'lights', sprintf('cam%i_light1%s.bmp', cam, suffix{1}));
        f2 = fullfile(d, 'lights', sprintf('cam%i_light2%s.bmp', cam, suffix{1}));
        tmp = [f1 '.swap'];
        movefile(f1, tmp); movefile(f2, f1); movefile(tmp, f2);
    end
end
end

function files = captureFiles(d, item)
% Full paths where a capture item is saved, {cam1 file, cam2 file}.
% <next> = the lowest pair number not used in cam1 or cam2 (fills gaps left by deletes)
n = 1;
while isfile(fullfile(d, 'cam1', sprintf('%i.bmp', n))) || isfile(fullfile(d, 'cam2', sprintf('%i.bmp', n)))
    n = n + 1;
end
name = strrep(item.file, '<next>', sprintf('%i', n));
files = {fullfile(d, strrep(name, '%i', '1')), fullfile(d, strrep(name, '%i', '2'))};
end

function c = yesNo(tf)
c = repmat({'no'}, 1, numel(tf));
c(tf) = {'yes'};
end

function pairs = savedImagePairs(d)
% Saved calibration images in folder d, as pairs to show side by side:
% checkerboard pairs (cam1 and cam2 with the same file name), each
% light/camera (LED spot and mirror checkerboard), and the axes images.
% kinds says which check (showAndCheck) applies to each file.
pairs = struct('label', {}, 'files', {}, 'kinds', {});
names = union(fileNames(fullfile(d, 'cam1')), fileNames(fullfile(d, 'cam2')));
[~, order] = sort(str2double(regexprep(names, '\.\w+$', ''))); % 1, 2, ..., 10
for name = names(order)
    pairs(end+1) = struct('label', ['Checkerboard pair ' regexprep(name{1}, '\.\w+$', '')], ...
        'files', {{fullfile(d, 'cam1', name{1}), fullfile(d, 'cam2', name{1})}}, ...
        'kinds', {{'checkerboard', 'checkerboard'}}); %#ok<AGROW>
end
for light = 1:2
    for cam = 1:2
        base = fullfile(d, 'lights', sprintf('cam%i_light%i', cam, light));
        files = {[base '.bmp'], [base '_checkerboard.bmp']};
        if any(cellfun(@isfile, files))
            pairs(end+1) = struct('label', sprintf('Light %i, cam%i', light, cam), 'files', {files}, ...
                'kinds', {{'led', 'mirror'}}); %#ok<AGROW>
        end
    end
end
files = {fullfile(d, 'axes', 'cam1.bmp'), fullfile(d, 'axes', 'cam2.bmp')};
if any(cellfun(@isfile, files))
    pairs(end+1) = struct('label', 'Axes', 'files', {files}, 'kinds', {{'axes', 'axes'}});
end
end

function names = fileNames(folder)
[~, n, e] = cellfun(@fileparts, listImageFiles(folder), 'UniformOutput', false);
names = strcat(n, e);
end

function [ok, txt] = showAndCheck(ax, I, kind, name, P)
% Show one calibration image and run the detection calibration will use on
% it, so a bad image can be retaken right away. kind: 'checkerboard', 'led'
% (LED spot), 'mirror' (mirror checkerboard), or 'axes'. Returns false if
% the detection failed; txt is the result, '<name>: <what was found>'.
cla(ax);
imagesc(ax, I, [0 255]); colormap(ax, gray); axis(ax, 'image');
ax.XTick = []; ax.YTick = [];
hold(ax, 'on');
switch kind
    case 'checkerboard'
        [pts, board] = detectCheckerboardPoints(I);
        ok = ~isempty(pts);
        if ok
            plot(ax, pts(:,1), pts(:,2), 'g+');
            txt = sprintf('checkerboard %ix%i found', board(1), board(2));
        end
    case 'mirror'
        [u, mask] = detectMirrorCheckerboard(I);
        ok = any(mask);
        if ok
            plot(ax, u(mask,1), u(mask,2), 'go');
            txt = sprintf('mirror checkerboard: %i corners', nnz(mask));
        end
    case 'led'
        [xy, area] = detectLedSpot(I);
        ok = ~isempty(xy);
        if ok
            plot(ax, xy(1), xy(2), 'r+', 'MarkerSize', 20, 'LineWidth', 1.5);
            txt = sprintf('LED spot at (%.0f, %.0f), %i px', xy(1), xy(2), area);
        end
    case 'axes'
        [p, bounds, n_found] = detectAxesMarkers(I, P.axes_thresh);
        ok = ~isempty(p);
        for k = 1:numel(bounds); plot(ax, bounds{k}(:,2), bounds{k}(:,1), 'y'); end
        if ok
            plot(ax, p(:,1), p(:,2), 'r+', 'MarkerSize', 15, 'LineWidth', 1.5);
            txt = '3 markers found';  % named p0/px/py at calibration, from both cameras
        else
            txt = sprintf('%i round saturated markers (need exactly 3)', n_found);
        end
end
hold(ax, 'off');
if ~ok && ~strcmp(kind, 'axes')
    txt = 'NOT FOUND';
end
txt = sprintf('%s: %s', name, txt);
title(ax, txt, 'Interpreter', 'none');
end
