function saved = startEyeCamerasLive(cams, exposure_us)
% saved = startEyeCamerasLive(cams, exposure_us)
% Start both cameras streaming (camera hardware trigger off) for a live view.
% Grab the newest frame at any time with getsnapshot(cams(k).vid). The
% toolbox trigger is 'manual' and never fired, so frames are not logged and
% memory doesn't fill. exposure_us (optional, empty = keep current) applies
% while live. Pass saved to stopEyeCamerasLive to stop and restore settings.

if ~exist('exposure_us', 'var'); exposure_us = []; end
saved = struct('TriggerMode', cell(1, numel(cams)), 'ExposureTime', []);
for k = 1:numel(cams)
    saved(k).TriggerMode = cams(k).src.TriggerMode;
    saved(k).ExposureTime = cams(k).src.ExposureTime;
    cams(k).src.TriggerMode = 'Off';
    if ~isempty(exposure_us)
        setCameraExposure(cams(k), exposure_us);
    end
    triggerconfig(cams(k).vid, 'manual');
    start(cams(k).vid);
end
