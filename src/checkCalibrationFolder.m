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

% Axes
has = [isfile(fullfile(filepath_camera,'axes','cam1.bmp')), ...
       isfile(fullfile(filepath_camera,'axes','cam2.bmp')), ...
       numel(dir(fullfile(filepath_camera,'axes','*.mat'))) == 1];
add('Axes images + QTM', all(has), missingNote({'cam1.bmp','cam2.bmp','one .mat QTM export'}, has));

% Results
add('calib.mat (stereo + lights)', isfile(fullfile(filepath_camera,'calib.mat')), 'written by calibration');
add('axes.mat (common frame)', isfile(fullfile(filepath_camera,'axes.mat')), 'written by calibration');

T = table(item, logical(ok), note, 'VariableNames', {'item','ok','note'});
end

function msg = missingNote(names, has)
if all(has)
    msg = 'ok';
else
    msg = ['missing ' strjoin(names(~has), ', ')];
end
end
