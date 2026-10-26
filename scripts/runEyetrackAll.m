function [H, Ht, stats, skipped] = runEyetrackAll(filepath_eye_root, downsample_eye, ploton, P, track_opts)
% [H, Ht, stats, skipped] = runEyetrackAll(filepath_eye_root, downsample_eye, ploton, P, track_opts)
% Loop eye tracking over all of the files starting with given string and
% combine them into one head/eye calibration for the bird.
% filepath_eye_root - find all folders with this root, e.g. Z:\...\behavior\HC13_2*
% downsample_eye - downsampling between QTM -> eye cameras (usually 5 or 6) - must be the
% same for all files to be combined
% ploton - plot the per-bird diagnostic figures (default 1)
% P - eyetrackParams (optional)
% track_opts - passed to trackEye (optional)
% x axis = mean of p_eyes to beak. y axis pointing left, z axis up
% Nothing is saved: the combined results are returned (Ht.folder = bird name).
% Sessions missing a video, qtm.mat, or a processed same-day calibration are
% skipped; skipped lists them with the reason.

if ~exist('ploton','var') || isempty(ploton); ploton = 1; end
if ~exist('P','var') || isempty(P); P = eyetrackParams(); end
if ~exist('track_opts','var'); track_opts = struct; end
if exist('downsample_eye','var') && ~isempty(downsample_eye)
    P.downsample_eye = downsample_eye;
end

data_root = fileparts(filepath_eye_root);
[~, bird] = fileparts(filepath_eye_root);
bird = strtok(bird, '_'); % e.g. HC13 from ...HC13_2*
a = dir(filepath_eye_root);
a = a([a.isdir] & ~endsWith({a.name}, '_all')); % skip old <bird>_all results folders (no longer made)
folders = {a.name};
if isempty(folders)
    error('No session folders match %s', filepath_eye_root)
end

% Skip sessions that can't be analyzed: missing a video, qtm.mat, or a
% processed calibration from the same day
needed = {'Video cam1', 'Video cam2', 'QTM qtm.mat', 'Calibration'};
keep = true(size(folders));
skipped = {};
for ii = 1:numel(folders)
    T = checkSessionFolder(fullfile(data_root, folders{ii}), P);
    T = T(ismember(T.item, needed), :);
    if ~all(T.ok)
        keep(ii) = false;
        bad = T(~T.ok, :);
        skipped{end+1} = sprintf('%s: %s', folders{ii}, strjoin(strcat(bad.item, {' ('}, bad.note, {')'}), '; ')); %#ok<AGROW>
        warning('Skipping %s', skipped{end});
    end
end
folders = folders(keep);
if isempty(folders)
    error('None of the session folders matching %s can be analyzed (see warnings above)', filepath_eye_root)
end
Q_all = [];
Q_all.N_head = 0;
Q_all.p_rigidbody  = [];
Q_all.R_rigidbody = [];
E_all = [];
E_all.pupil1 = [];
E_all.cr1 = [];
E_all.pupil2 = [];
E_all.cr2 = [];
E_all.resid1 = [];
E_all.resid2 = [];
E_all.points_fraction1 = [];
E_all.points_fraction2 = [];


p_pupil_all= [];
p_cornea_all = [];
p_beak_all =[];
dist_pc_all = [];

for ii  = 1:length(folders)
    filepath_eye = fullfile(data_root, folders{ii});

    %% Run eye tracking (will skip if already run). Beak clicks only for the first session analyzed
    opts = struct('run_beak', ii==1, 'resume_beak', false, 'resume_eye', true, ...
        'crop_qtm', true, 'track_opts', track_opts);
    S = processSession(filepath_eye, P, opts);
    E = S.E;
    N_eye = length(E.resid1);

    E_all.pupil1 = [E_all.pupil1; E.pupil1];
    E_all.cr1 = cat(1,E_all.cr1, E.cr1);
    E_all.pupil2 = [E_all.pupil2; E.pupil2];
    E_all.cr2 = cat(1, E_all.cr2, E.cr2);
    E_all.resid1 = [E_all.resid1; E.resid1];
    E_all.resid2 = [E_all.resid2; E.resid2];
    try
        E_all.points_fraction1 = [E_all.points_fraction1; E.points_fraction1];
        E_all.points_fraction2 = [E_all.points_fraction2; E.points_fraction2];
    catch % Early recordings didn't calculate this
        E_all.points_fraction1 = [E_all.points_fraction1; NaN(N_eye,1)];
        E_all.points_fraction2 = [E_all.points_fraction2; NaN(N_eye,1)];
    end

    %% Combine files
    p_pupil_all = [p_pupil_all; S.p_pupil]; %#ok<AGROW>
    p_cornea_all = [p_cornea_all; S.p_cornea]; %#ok<AGROW>
    p_beak_all = [p_beak_all; S.p_beak]; %#ok<AGROW>
    dist_pc_all = [dist_pc_all; S.dist_pc]; %#ok<AGROW>

    Q_all.fps_head = S.Q.fps_head;
    Q_all.N_head = Q_all.N_head + S.Q.N_head;
    Q_all.p_rigidbody = [Q_all.p_rigidbody; S.Q.p_rigidbody];
    Q_all.R_rigidbody = cat(3, Q_all.R_rigidbody, S.Q.R_rigidbody); % [X Y Z]

end


%% Plot the distribution of eye angles relative to common reference frame (which is roughly aligned between the two cameras)
if ploton
    % Get a unit vector pointing in the direction of the eye
    v_eye = (p_pupil_all-p_cornea_all)./sqrt(sum((p_pupil_all-p_cornea_all).^2, 2));

    % Get the horizontal angle (relative to the world/motor)
    yaw_eye = -real(squeeze(atan2(v_eye(:,2), v_eye(:,1))));
    pitch_eye = atan2(v_eye(:,3), sqrt(v_eye(:,1).^2 + v_eye(:,2).^2));
    yawd_eye = rad2deg(yaw_eye);
    pitchd_eye = rad2deg(pitch_eye);
    figure; plot(v_eye,'.'); legend({'x','y','z'})
    xlabel('Eye frame # (all sessions)'); ylabel('Unit vector component')
    title([bird ': eye vector (pupil - cornea), common frame'], 'Interpreter', 'none')
    figure; plot([yawd_eye pitchd_eye],'.-'); legend({'yaw','pitch'})
    xlabel('Eye frame # (all sessions)'); ylabel('Angle (deg)')
    title([bird ': eye yaw and pitch, common frame'], 'Interpreter', 'none')
    figure
    subplot(1,2,1); histogram(yawd_eye, -180:1:180); xlabel('Yaw (deg)'); ylabel('Frame count')
    title([bird ': eye yaw, common frame'], 'Interpreter', 'none')
    subplot(1,2,2); histogram(yawd_eye-90, -50:1:50); xlabel('Yaw - 90 (deg)'); ylabel('Frame count')
    title('Zoom: within 50 deg of 90')
    drawnow
end


%% Analyze results for all sessions of this bird (returned, not saved)
[H, Ht, stats] = analyzeEyetrack(E_all, p_pupil_all, p_cornea_all, p_beak_all, Q_all,  P.downsample_eye, dist_pc_all, ploton);
drawnow;
H.folder_eye_calib = folders;
H.folder_camera_calib = '';
Ht.folder = {bird};
disp(Ht)
disp(stats)
