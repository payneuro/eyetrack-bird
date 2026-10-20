function T = checkCalibrationFolder(filepath_camera)
% T = checkCalibrationFolder(filepath_camera)
% Table of the files calibrateCameras needs, whether each is present, and a
% note. T.ok is true when an item is ready.

item = {}; ok = []; note = {};

    function add(name, is_ok, msg)
        item{end+1,1} = name; ok(end+1,1) = is_ok; note{end+1,1} = msg;
    end

% Checkerboard images
n = zeros(1,2);
for cam = 1:2
    n(cam) = numel(listImageFiles(fullfile(filepath_camera, sprintf('cam%i',cam))));
end
add('Checkerboard cam1', n(1) >= 4, sprintf('%i images (need 4-10)', n(1)));
add('Checkerboard cam2', n(2) >= 4 && n(2) == n(1), sprintf('%i images (must match cam1)', n(2)));

% Lights
for cam = 1:2
    for light = 1:2
        f1 = sprintf('cam%i_light%i.bmp', cam, light);
        f2 = sprintf('cam%i_light%i_checkerboard.bmp', cam, light);
        has1 = isfile(fullfile(filepath_camera, 'lights', f1));
        has2 = isfile(fullfile(filepath_camera, 'lights', f2));
        add(sprintf('Light %i, cam%i', light, cam), has1 && has2, missingNote({f1, f2}, [has1 has2]));
    end
end

% Axes: both images plus the QTM export (one .mat with markers labeled p0, px, py)
has = [isfile(fullfile(filepath_camera,'axes','cam1.bmp')), ...
       isfile(fullfile(filepath_camera,'axes','cam2.bmp'))];
msg = missingNote({'cam1.bmp','cam2.bmp'}, has);
[qtm_ok, qtm_msg] = checkAxesQtm(fullfile(filepath_camera,'axes'));
if ~qtm_ok
    if all(has); msg = qtm_msg; else; msg = [msg '; ' qtm_msg]; end
end
add('Axes images + QTM', all(has) && qtm_ok, msg);

% Results
add('calib.mat (stereo + lights)', isfile(fullfile(filepath_camera,'calib.mat')), 'written by calibration');
add('axes.mat (common frame)', isfile(fullfile(filepath_camera,'axes.mat')), 'written by calibration');

T = table(item, logical(ok), note, 'VariableNames', {'item','ok','note'});
end

function [ok, msg] = checkAxesQtm(folder)
% The axes QTM export: exactly one .mat in folder, with labeled markers p0, px, py
ok = false;
f = dir(fullfile(folder, '*.mat'));
if isempty(f)
    msg = 'missing QTM export (.mat)';
    return
elseif numel(f) > 1
    msg = sprintf('%i .mat files; keep only the QTM export', numel(f));
    return
end
try
    s = load(fullfile(folder, f.name));
    q = s.(f.name(1:end-4)); % QTM names the variable after the file
    labels = q.Trajectories.Labeled.Labels;
catch
    msg = [f.name ' is not a QTM export with labeled trajectories'];
    return
end
missing = setdiff({'p0', 'px', 'py'}, labels);
if isempty(missing)
    ok = true;
    msg = 'ok';
else
    msg = [f.name ' missing labels ' strjoin(missing, ', ')];
end
end

function msg = missingNote(names, has)
if all(has)
    msg = 'ok';
else
    msg = ['missing ' strjoin(names(~has), ', ')];
end
end
