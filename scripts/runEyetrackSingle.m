function [H, Ht] = runEyetrackSingle(filepath_eye, downsample_eye, P)
% [H, Ht] = runEyetrackSingle(filepath_eye, downsample_eye, P)
% Run one session and save head_calibration.mat in the session folder.
% P defaults to eyetrackParams; downsample_eye overrides P.downsample_eye.

if ~exist('P','var') || isempty(P); P = eyetrackParams(); end
if exist('downsample_eye','var') && ~isempty(downsample_eye)
    P.downsample_eye = downsample_eye;
end

%% Run eye tracking (will skip if already run)
opts = struct('run_beak', true, 'resume_beak', false, 'resume_eye', true, 'crop_qtm', false);
S = processSession(filepath_eye, P, opts);

%% Analyze results
[H, Ht] = analyzeEyetrack(S.E, S.p_pupil, S.p_cornea, S.p_beak, S.Q, P.downsample_eye, S.dist_pc);
H.folder_eye_calib = filepath_eye;
H.folder_camera_calib = S.filepath_camera;
Ht.folder = filepath_eye;
disp(Ht)

%% Save results
save(fullfile(filepath_eye, 'head_calibration.mat'),'-struct','H');
save(fullfile(filepath_eye, 'head_calibration_template.mat'),'Ht');
