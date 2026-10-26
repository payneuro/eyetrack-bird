function [H, Ht, stats] = runEyetrackSingle(filepath_eye, downsample_eye, P, correct_offset)
% [H, Ht, stats] = runEyetrackSingle(filepath_eye, downsample_eye, P, correct_offset)
% Run one session and save head_calibration.mat in the session folder.
% P defaults to eyetrackParams; downsample_eye overrides P.downsample_eye.
% Also plots the camera-QTM check (plotYawCheck): each eye's position in the
% head vs head yaw, which should be flat.
% correct_offset - true: first fit a shift + rotation about vertical of the
%                  eye-camera points relative to QTM (fitCameraOffset), apply it
%                  to the pupil, cornea and beak points, then analyze. The
%                  offset is saved in H.camera_offset. Default false.

if ~exist('P','var') || isempty(P); P = eyetrackParams(); end
if exist('downsample_eye','var') && ~isempty(downsample_eye)
    P.downsample_eye = downsample_eye;
end
if ~exist('correct_offset','var') || isempty(correct_offset); correct_offset = false; end
[~, name] = fileparts(filepath_eye);

%% Run eye tracking (will skip if already run)
opts = struct('run_beak', true, 'resume_beak', false, 'resume_eye', true, 'crop_qtm', false);
S = processSession(filepath_eye, P, opts);
up = [0 0 1] * S.A.R_head * S.A.R_45; % QTM vertical in the common frame

%% Optional: remove a shift of the eye cameras relative to QTM
H_offset = []; before = [];
if correct_offset
    [H0, ~, ~, Eout0] = analyzeEyetrack(S.E, S.p_pupil, S.p_cornea, S.p_beak, S.Q, P.downsample_eye, S.dist_pc, false);
    before = struct('H', H0, 'Eout', Eout0); % shown under the corrected check figure
    offset = fitCameraOffset(Eout0, up);
    S.p_pupil = offset.apply(S.p_pupil);
    S.p_cornea = offset.apply(S.p_cornea);
    S.p_beak = offset.apply(S.p_beak);
    H_offset = rmfield(offset, 'apply');
    fprintf('Camera offset applied: shift [%.2f %.2f %.2f] mm, yaw %.2f deg\n', offset.t, offset.yaw_deg);
end

%% Analyze results
[H, Ht, stats, Eout] = analyzeEyetrack(S.E, S.p_pupil, S.p_cornea, S.p_beak, S.Q, P.downsample_eye, S.dist_pc);
stats.yaw_slopes = {plotYawCheck(H, Eout, true, name, before, up)}; % camera-QTM check: mm/deg, rows left/right eye, columns x/y/z
H.folder_eye_calib = filepath_eye;
H.folder_camera_calib = S.filepath_camera;
H.camera_offset = H_offset; % [] unless correct_offset
Ht.folder = filepath_eye;
disp(Ht)

%% Save results
save(fullfile(filepath_eye, 'head_calibration.mat'),'-struct','H');
save(fullfile(filepath_eye, 'head_calibration_template.mat'),'Ht');
