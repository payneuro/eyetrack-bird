function saved = startEyeCamerasLive(cams, exposure_us)
% saved = startEyeCamerasLive(cams, exposure_us)
% Start both cameras free-running (hardware trigger off) for a live view.
% Read the newest frame with peekdata(cams(k).vid, 1), then flushdata.
% exposure_us (optional, empty = keep current) applies while live.
% Pass saved to stopEyeCamerasLive to stop and restore the settings.

if ~exist('exposure_us', 'var'); exposure_us = []; end
saved = struct('TriggerMode', cell(1, numel(cams)), 'ExposureTime', []);
for k = 1:numel(cams)
    saved(k).TriggerMode = cams(k).src.TriggerMode;
    saved(k).ExposureTime = cams(k).src.ExposureTime;
    cams(k).src.TriggerMode = 'Off';
    if ~isempty(exposure_us)
        setCameraExposure(cams(k), exposure_us);
    end
    cams(k).vid.FramesPerTrigger = Inf;
    cams(k).vid.LoggingMode = 'memory';
    start(cams(k).vid);
end
