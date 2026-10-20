function [I, exposure_used] = snapEyeCameras(cams, exposure_us)
% [I, exposure_used] = snapEyeCameras(cams, exposure_us)
% Grab one still frame from each camera (I{1} = cam1, I{2} = cam2) for
% calibration images. The hardware trigger is switched off for the snap and
% the cameras are free-running, so the two frames are taken one after the
% other (~0.5 s apart): only use for targets that are not moving.
% exposure_us (optional, empty = keep current) is used for this snap only.
% exposure_used is what the cameras actually applied (they round to their
% own step, e.g. 6000 -> 5997 us). Trigger mode and exposure are restored
% afterward, also on error.

if ~exist('exposure_us', 'var'); exposure_us = []; end
n = numel(cams);
trigger0 = cell(1, n);
exposure0 = zeros(1, n);
for k = 1:n
    trigger0{k} = cams(k).src.TriggerMode;
    exposure0(k) = cams(k).src.ExposureTime;
end
restore = onCleanup(@() restoreSettings(cams, trigger0, exposure0));

I = cell(1, n);
exposure_used = zeros(1, n);
for k = 1:n
    cams(k).src.TriggerMode = 'Off';
    if ~isempty(exposure_us)
        w = warning('off', 'all'); % "adjusted by the camera" rounding notice
        cams(k).src.ExposureTime = exposure_us;
        warning(w);
    end
    exposure_used(k) = cams(k).src.ExposureTime;
    I{k} = getsnapshot(cams(k).vid);
end
end

function restoreSettings(cams, trigger0, exposure0)
for k = 1:numel(cams)
    if isvalid(cams(k).vid)
        cams(k).src.ExposureTime = exposure0(k);
        cams(k).src.TriggerMode = trigger0{k};
    end
end
end
