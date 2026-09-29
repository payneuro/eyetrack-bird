function [T, info] = checkSessionFolder(filepath_eye, P)
% [T, info] = checkSessionFolder(filepath_eye, P)
% Table of a session's inputs and pipeline outputs. info has the frame
% counts and the matched calibration folder.

if ~exist('P','var'); P = eyetrackParams(); end
item = {}; ok = []; note = {};
    function add(name, is_ok, msg)
        item{end+1,1} = name; ok(end+1,1) = is_ok; note{end+1,1} = msg;
    end

info = struct('N_eye', [NaN NaN], 'fps_eye', NaN, 'N_head', NaN, 'fps_head', NaN, 'filepath_camera', '');

% Videos
for cam = 1:2
    d = dir(fullfile(filepath_eye, sprintf(P.camfilename, cam)));
    if isempty(d)
        add(sprintf('Video cam%i', cam), false, sprintf('no file matching %s', sprintf(P.camfilename, cam)));
        continue
    end
    try
        v = VideoReader(fullfile(d(1).folder, d(1).name));
        info.N_eye(cam) = round(v.Duration*v.FrameRate);
        info.fps_eye = v.FrameRate;
        add(sprintf('Video cam%i', cam), numel(d) == 1, sprintf('%s: %i frames, %.1f Hz', d(1).name, info.N_eye(cam), v.FrameRate));
    catch err
        add(sprintf('Video cam%i', cam), false, err.message);
    end
end

% QTM
f = fullfile(filepath_eye, 'qtm.mat');
if isfile(f)
    try
        Q = getfield(load(f), 'qtm');
        info.N_head = Q.Frames;
        info.fps_head = Q.FrameRate;
        n_expected = min(info.N_eye) * P.downsample_eye;
        add('QTM qtm.mat', true, sprintf('%i frames at %g Hz (videos x %i = %i)', ...
            Q.Frames, Q.FrameRate, P.downsample_eye, n_expected));
    catch err
        add('QTM qtm.mat', false, err.message);
    end
else
    add('QTM qtm.mat', false, 'missing');
end

% Calibration
try
    info.filepath_camera = findCalibrationFolder(filepath_eye, P.calib_root);
    has = isfile(fullfile(info.filepath_camera, 'calib.mat')) && isfile(fullfile(info.filepath_camera, 'axes.mat'));
    if has
        msg = info.filepath_camera;
    elseif isfolder(info.filepath_camera)
        msg = [info.filepath_camera ' (not processed yet)'];
    else
        msg = [info.filepath_camera ' (folder not found)'];
    end
    add('Calibration', has, msg);
catch err
    add('Calibration', false, err.message);
end

% Pipeline outputs
add('beak.mat (beak clicks)', isfile(fullfile(filepath_eye,'beak.mat')), beakNote(filepath_eye));
add('eye.mat (tracking)', isfile(fullfile(filepath_eye,'eye.mat')), eyeNote(filepath_eye));
add('eye_triangulate.mat', isfile(fullfile(filepath_eye,'eye_triangulate.mat')), '3D pupil/cornea/beak');
add('head_calibration.mat', isfile(fullfile(filepath_eye,'head_calibration.mat')), 'final head/eye geometry');

T = table(item, logical(ok), note, 'VariableNames', {'item','ok','note'});
end

function msg = beakNote(filepath_eye)
f = fullfile(filepath_eye,'beak.mat');
msg = '';
if isfile(f)
    b = load(f, 'p1');
    msg = sprintf('%i points', nnz(~isnan(b.p1(:,1))));
end
end

function msg = eyeNote(filepath_eye)
f = fullfile(filepath_eye,'eye.mat');
msg = '';
if isfile(f)
    s = whos('-file', f);
    if any(strcmp({s.name}, 'ii'))
        e = load(f, 'ii');
        msg = sprintf('partial, stopped at frame %i', e.ii);
    else
        msg = 'complete';
    end
end
end
