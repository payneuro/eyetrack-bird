function [H, Ht, stats] = runEyetrackAll(filepath_eye_root, downsample_eye, ploton, P, track_opts)
% [H, Ht, stats] = runEyetrackAll(filepath_eye_root, downsample_eye, ploton, P, track_opts)
% Loop eye tracking over all of the files starting with given string and
% combine them into one head/eye calibration for the bird.
% filepath_eye_root - find all folders with this root, e.g. Z:\...\behavior\HC13_2*
% downsample_eye - downsampling between QTM -> eye cameras (usually 5 or 6) - must be the
% same for all files to be combined
% ploton - plot eye angle diagnostics (default 1)
% P - eyetrackParams (optional)
% track_opts - passed to trackEye (optional)
% x axis = mean of p_eyes to beak. y axis pointing left, z axis up
% Results are saved to <bird>_all next to the session folders.

if ~exist('ploton','var') || isempty(ploton); ploton = 1; end
if ~exist('P','var') || isempty(P); P = eyetrackParams(); end
if ~exist('track_opts','var'); track_opts = struct; end
if exist('downsample_eye','var') && ~isempty(downsample_eye)
    P.downsample_eye = downsample_eye;
end

data_root = fileparts(filepath_eye_root);
a = dir(filepath_eye_root);
a = a([a.isdir] & ~endsWith({a.name}, '_all')); % skip combined-results folder
folders = {a.name};
if isempty(folders)
    error('No session folders match %s', filepath_eye_root)
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

    %% Run eye tracking (will skip if already run). Beak clicks only for the first session
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
    figure; plot(v_eye,'.'); title('Eye vector, common frame'); legend({'x','y','z'})
    figure; plot([yawd_eye pitchd_eye],'.-'); title('Eye yaw and pitch (deg)'); legend({'yaw','pitch'})
    figure; histogram(yawd_eye-90, -50:1:50); xlabel('Yaw - 90 (deg)')
    figure; histogram(yawd_eye, -180:1:180); xlabel('Yaw (deg)')
    drawnow
end


%% Analyze results for all session for this bird
a = strfind(filepath_eye_root,'_');
filepath_eye = [filepath_eye_root(1:a(end)-1) '_all'];
disp(filepath_eye)

[H, Ht, stats, Eout] = analyzeEyetrack(E_all, p_pupil_all, p_cornea_all, p_beak_all, Q_all,  P.downsample_eye, dist_pc_all);
drawnow;
H.folder_eye_calib = folders;
H.folder_camera_calib = '';
Ht.folder = {filepath_eye};
disp(Ht)
disp(stats)


%% Save results
if ~isfolder(filepath_eye); mkdir(filepath_eye); end
save(fullfile(filepath_eye, 'head_calibration.mat'),'-struct','H');
save(fullfile(filepath_eye, 'head_calibration_template.mat'),'Ht');
save(fullfile(filepath_eye, 'head_calibration_stats.mat'),'stats');
save(fullfile(filepath_eye, 'head_calibration_data.mat'),'-struct','Eout');
save(fullfile(filepath_eye, 'head_calibration_qualisys.mat'),'-struct','Q_all');
