function S = processSession(filepath_eye, P, opts)
% S = processSession(filepath_eye, P, opts)
% Run one session through calibration lookup, beak labeling, eye tracking,
% triangulation, and conversion to the common reference frame.
%
% P    - eyetrackParams (paths, downsample_eye, ...)
% opts - optional fields:
%   run_beak    (true)  ask for beak clicks if beak.mat doesn't exist
%   resume_beak (false) add more beak clicks to an existing beak.mat
%   resume_eye  (true)  resume a partial eye.mat
%   crop_qtm    (true)  drop QTM frames past the end of the eye videos
%   p_track     ([])    tracker settings for a new eye.mat (default defaultTrackerParams)
%   track_opts  (struct) passed to trackEye
%
% S has fields E, p_pupil, p_cornea, p_beak (common frame), Q (common frame),
% dist_pc, filepath_camera, C, A.

if ~exist('P','var') || isempty(P); P = eyetrackParams(); end
if ~exist('opts','var'); opts = struct; end
defaults = struct('run_beak', true, 'resume_beak', false, 'resume_eye', true, ...
    'crop_qtm', true, 'p_track', [], 'track_opts', struct);
fn = fieldnames(defaults);
for ii = 1:numel(fn)
    if ~isfield(opts, fn{ii}); opts.(fn{ii}) = defaults.(fn{ii}); end
end
disp(filepath_eye)

%% Get camera calibration -- folder must be named same date as recording, e.g. 220831
filepath_camera = findCalibrationFolder(filepath_eye, P.calib_root);
disp(filepath_camera)
[C, A] = calibrateCameras(filepath_camera, P);
checkCameraOrder(C);

%% Load Qualysis rigid body
Q = getfield(load(fullfile(filepath_eye,'qtm.mat')),'qtm');
N_head = Q.Frames;

%% Run eye tracking (will skip if already run)
[E, p_pupil_cam, p_cornea_cam, p_beak_cam] = processEyetrack(filepath_eye, P.camfilename, C, ...
    opts.resume_beak, opts.run_beak, opts.resume_eye, opts.p_track, opts.track_opts, P.beak_skip_frames);
[p_pupil_cam, p_cornea_cam, dist_pc] = correctLengthP_CR(p_pupil_cam, p_cornea_cam);
N_eye = length(E.resid1);
fprintf('Video frames %i, predicted QTM frames %i, actual QTM frames %i\n', ...
    N_eye, N_eye*P.downsample_eye, N_head)

% Crop QTM if longer than eye cameras
if opts.crop_qtm && N_head > N_eye*P.downsample_eye
    warning('Cropping QTM')
    Q.RigidBodies.Positions = Q.RigidBodies.Positions(1,:,1:N_eye*P.downsample_eye);
    Q.RigidBodies.Rotations = Q.RigidBodies.Rotations(1,:,1:N_eye*P.downsample_eye);
    N_head = N_eye*P.downsample_eye;
end

Q_raw = [];
Q_raw.N_head = N_head;
Q_raw.fps_head = Q.FrameRate;
Q_raw.p_rigidbody = squeeze(Q.RigidBodies.Positions(1,:,1:N_head))';
Q_raw.R_rigidbody = reshape(Q.RigidBodies.Rotations(1,:,1:N_head), [3,3,N_head]); % [X Y Z]

%% Convert to common reference frame
Q_common = Q_raw;
[p_pupil_common, p_cornea_common, p_beak_common, Q_common.p_rigidbody, Q_common.R_rigidbody]...
    = alignCommonReferenceFrame(A, p_pupil_cam, p_cornea_cam, p_beak_cam, Q_raw.p_rigidbody, Q_raw.R_rigidbody);

S = struct('E', E, 'p_pupil', p_pupil_common, 'p_cornea', p_cornea_common, ...
    'p_beak', p_beak_common, 'Q', Q_common, 'dist_pc', dist_pc, ...
    'filepath_camera', filepath_camera, 'C', C, 'A', A);
