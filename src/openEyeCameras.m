function cams = openEyeCameras(cam_serials)
% cams = openEyeCameras(cam_serials)
% Connect to the two Blackfly eye cameras through the Image Acquisition
% Toolbox GenICam (gentl) adaptor. cams(k) is camera k (cam1 = left,
% cam2 = right), matched by serial number, not by the adaptor's device order.
% cams(k).vid is the videoinput, cams(k).src its source (camera settings).
% Close with closeEyeCameras(cams). SpinView must not be connected to them.

old = imaqfind('Type', 'videoinput'); % left over from a GUI that closed without disconnecting
old = old(arrayfun(@(v) strcmpi(imaqhwinfo(v, 'AdaptorName'), 'gentl'), old));
if ~isempty(old)
    stop(old); delete(old);
end
info = imaqhwinfo('gentl');
cams = struct('vid', cell(1, 2), 'src', [], 'serial', cam_serials);
for k = 1:numel(info.DeviceInfo)
    vid = videoinput('gentl', info.DeviceInfo(k).DeviceID, 'Mono8');
    src = getselectedsource(vid);
    cam = find(strcmp(cam_serials, src.DeviceSerialNumber));
    if isempty(cam)
        delete(vid); % another camera
        continue
    end
    cams(cam).vid = vid;
    cams(cam).src = src;
end
missing = cellfun(@isempty, {cams.vid});
if any(missing)
    closeEyeCameras(cams);
    error('Camera(s) not found: serial %s. Check USB and that SpinView is closed.', ...
        strjoin(cam_serials(missing), ', '));
end
