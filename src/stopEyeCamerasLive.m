function stopEyeCamerasLive(cams, saved)
% stopEyeCamerasLive(cams, saved)
% Stop the live view started by startEyeCamerasLive and restore each
% camera's trigger mode and exposure.

for k = 1:numel(cams)
    if ~isvalid(cams(k).vid); continue; end
    if isrunning(cams(k).vid); stop(cams(k).vid); end
    flushdata(cams(k).vid);
    cams(k).src.ExposureTime = saved(k).ExposureTime;
    cams(k).src.TriggerMode = saved(k).TriggerMode;
end
