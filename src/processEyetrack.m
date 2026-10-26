function [E, p_pupil, p_cornea, p_beak, p] = processEyetrack(filepath_eye,  camfilename, C,  resume_beak, run_beak, resume_eye, p_track, track_opts, beak_step)
% [E, p_pupil, p_cornea, p_beak, p] = processEyetrack(filepath_eye, camfilename, C,
%     resume_beak, run_beak, resume_eye, p_track, track_opts, beak_step)
% Get beak clicks (getBeak), track pupil and CRs (trackEye, or load eye.mat),
% and triangulate them into 3D camera-frame points (uncleaned, mm), cached in
% eye_triangulate.mat. C is the camera calibration from calibrateCameras.
%
% Optional:
% p_track          - tracker parameters (default defaultTrackerParams). Only used
%                    when eye.mat doesn't exist yet
% track_opts       - passed to trackEye (plot axes, stop/progress callbacks)
% beak_step        - frames between beak clicks (default P.preview_step_frames)
%
% Hannah Payne 2022

if ~exist('p_track','var') || isempty(p_track)
    p_track = defaultTrackerParams();
end
if ~exist('track_opts','var')
    track_opts = struct;
end
if ~exist('beak_step','var') || isempty(beak_step)
    P = eyetrackParams();
    beak_step = P.preview_step_frames;
end

%% Get beak
beak = getBeak(filepath_eye, camfilename, resume_beak, run_beak, beak_step);


%% Track eye
if ~exist(fullfile(filepath_eye, 'eye.mat'),'file')
    [E,p] = trackEye(filepath_eye, p_track, camfilename, track_opts); % TRACK THE PUPIL AND CR
else
    temp = load(fullfile(filepath_eye,'eye.mat'));
    E = temp.E;
    p = temp.p;

    % To resume where we left off
    if isfield(temp,'ii') && resume_eye
        [E,p] = trackEye(filepath_eye, p, camfilename, track_opts); % TRACK THE PUPIL AND CR
    end
end

N_eye = length(E.pupil1(:,1));


%% If beak is empty
if isempty(beak)
    beak.ii = 1; % index into video
    beak.p1 = NaN(N_eye,2);
    beak.p2 = NaN(N_eye,2);
end

%% Convert pupil and corneal reflections from image to camera world coordinates
% eye_triangulate.mat is a cache: rebuilt only when what it's computed from
% (tracking, beak clicks, calibration) differs from what it was built with
source = inputHash(E, p, beak, C);
f_cache = fullfile(filepath_eye, 'eye_triangulate.mat');
rebuild = ~isfile(f_cache) || ~ismember('source', who('-file', f_cache)) || ...
    ~strcmp(getfield(load(f_cache, 'source'), 'source'), source);
if rebuild
    p_cornea = NaN(N_eye, 3);
    p_pupil = NaN(N_eye, 3);
    Ef = uncropEyeCoords(E, p); % tracking ran on cropped images; triangulation needs full-frame pixels
    nanmask = ~isnan(Ef.pupil1(:,1)) & ~isnan(Ef.cr1(:,1,2)) & ~isnan(Ef.pupil2(:,1)) & ~isnan(Ef.cr2(:,1,2));
    [p_cornea(nanmask,:), p_pupil(nanmask,:)] = estimatepandc(...
        C.stereo_params, C.p_light1, C.p_light2,...
        Ef.pupil1(nanmask,1:2),Ef.pupil2(nanmask,1:2),...
        Ef.cr1(nanmask,1:2,1),Ef.cr2(nanmask,1:2,1),...
        Ef.cr1(nanmask,1:2,2),Ef.cr2(nanmask,1:2,2));

    p_beak = NaN(N_eye, 3);
    mask_beak = ~isnan(beak.p1(:,1)) & ~isnan(beak.p2(:,1));
    if any(mask_beak)
        p_beak(mask_beak,:) = triangulate(...
            undistortPoints(beak.p1(mask_beak,:), C.stereo_params.CameraParameters1), ...
            undistortPoints(beak.p2(mask_beak,:), C.stereo_params.CameraParameters2), C.stereo_params);
    end

    save(f_cache, 'p_pupil', 'p_cornea', 'p_beak', 'source')
else
    temp = load(f_cache, 'p_pupil', 'p_cornea', 'p_beak');
    p_pupil = temp.p_pupil;
    p_cornea= temp.p_cornea;
    p_beak = temp.p_beak;
end
end

function h = inputHash(E, p, beak, C)
% MD5 of everything the triangulation uses: pupil/CR positions, the crop,
% the beak clicks, and the calibration (stereo parameters and light positions)
crop = {};
if isfield(p, 'cropX'); crop = {p.cropX, p.cropY}; end
inputs = {E.pupil1, E.pupil2, E.cr1, E.cr2, crop, beak.p1, beak.p2, ...
    toStruct(C.stereo_params), C.p_light1, C.p_light2};
md = java.security.MessageDigest.getInstance('MD5');
md.update(getByteStreamFromArray(inputs));
h = sprintf('%02x', typecast(md.digest(), 'uint8'));
end
