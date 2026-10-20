function rec = startEyeRecording(cams, folder, format, P, exposure_us)
% rec = startEyeRecording(cams, folder, format, P, exposure_us)
% Arm both cameras on their hardware trigger (the QTM TTL) and save every
% frame they take to folder as cam1/cam2 videos. Frames only arrive once
% QTM starts sending pulses. Stop with stopEyeRecording(rec).
% format      - 'h264': compressed on the GPU while recording (ffmpeg at
%               P.ffmpeg, NVIDIA H.264, quality qp 18) -> cam1.mp4, cam2.mp4
%               'raw': uncompressed -> cam1.avi, cam2.avi (~2.8 MB/frame)
% exposure_us - exposure during recording (empty = keep current)
% Each camera's running state (frames written, last frame, ffmpeg pipe) is
% kept in cams(k).vid.UserData.

ext = struct('h264', '.mp4', 'raw', '.avi');
files = {fullfile(folder, ['cam1' ext.(format)]), fullfile(folder, ['cam2' ext.(format)])};
if any(cellfun(@isfile, files))
    error('%s already has camera videos; use a new session folder.', folder);
end
if strcmp(format, 'h264')
    [ffmpeg, gpu_ok, version] = findFfmpeg(P.ffmpeg); % before touching the cameras
    if isempty(ffmpeg)
        error(['ffmpeg not found at %s or on the PATH, so compressed recording can''t start. ' ...
            'See the ffmpeg row in the Settings tab''s requirements list, or choose Raw.'], P.ffmpeg);
    elseif ~gpu_ok
        error(['ffmpeg %s (%s) can''t encode on the NVIDIA GPU (h264_nvenc). ffmpeg 8+ needs a newer NVIDIA ' ...
            'driver: update the driver or use ffmpeg 7.1 (Settings tab, ffmpeg row), or choose Raw.'], version, ffmpeg);
    end
    P.ffmpeg = ffmpeg;
end
rec = struct('cams', cams, 'format', format, 'files', {files}, 'exposure0', [cams(1).src.ExposureTime, cams(2).src.ExposureTime], ...
    'trigger', {cell(1, 2)});

for k = 1:2
    vid = cams(k).vid;
    if ~isempty(exposure_us)
        setCameraExposure(cams(k), exposure_us);
    end
    % Hardware trigger in the toolbox too: with 'immediate' the adaptor turns
    % the camera's TriggerMode off at start and the camera runs free (~60 fps)
    triggerconfig(vid, 'hardware', 'DeviceSpecific', 'DeviceSpecific');
    setHardwareTrigger(cams(k).src, P); % one frame per TTL
    vid.FramesPerTrigger = 1;
    vid.TriggerRepeat = Inf;
    state = struct('written', 0, 'last', [], 'proc', [], 'pipe', [], 'error', '');
    if strcmp(format, 'raw')
        vid.LoggingMode = 'disk&memory'; % disk = the video; memory only feeds the preview
        writer = VideoWriter(files{k}, 'Grayscale AVI');
        writer.FrameRate = P.eye_fps;
        vid.DiskLogger = writer;
    else
        vid.LoggingMode = 'memory';
        [state.proc, state.pipe] = startEncoder(P, vid.VideoResolution, files{k});
    end
    vid.UserData = state;
    vid.FramesAcquiredFcnCount = 10;
    vid.FramesAcquiredFcn = @saveFrames;
end
for k = 1:2
    start(cams(k).vid);
end
for k = 1:2 % read back after start, which is when the adaptor applies its own settings
    [rec.trigger{k}, is_on] = triggerSettings(cams(k).src);
    if ~is_on
        stopEyeRecording(rec);
        cellfun(@delete, rec.files(cellfun(@isfile, rec.files))); % empty videos
        error('cam%i trigger mode is off after starting (%s), so it would run free. Not recording.', k, rec.trigger{k});
    end
end
end

function [txt, is_on] = triggerSettings(src)
names = intersect({'TriggerSelector', 'TriggerMode', 'TriggerSource', 'TriggerActivation', 'TriggerOverlap', 'ExposureMode'}, ...
    fieldnames(propinfo(src)), 'stable');
txt = strjoin(cellfun(@(n) sprintf('%s=%s', n, src.(n)), names, 'UniformOutput', false), ', ');
is_on = strcmp(src.TriggerMode, 'On');
end

function setHardwareTrigger(src, P)
% Set every trigger setting explicitly (don't rely on what SpinView left):
% each rising edge on P.trigger_line starts one frame
info = propinfo(src);
src.TriggerMode = 'Off'; % the camera only accepts trigger changes while off
if isfield(info, 'TriggerSelector'); src.TriggerSelector = 'FrameStart'; end
src.TriggerSource = P.trigger_line;
src.TriggerActivation = 'RisingEdge';
if isfield(info, 'ExposureMode'); src.ExposureMode = 'Timed'; end
src.TriggerMode = 'On';
end

function [proc, pipe] = startEncoder(P, res, file)
% ffmpeg reading raw gray frames from stdin and writing H.264 (MATLAB-readable 4:2:0)
proc = System.Diagnostics.Process;
proc.StartInfo.FileName = P.ffmpeg;
proc.StartInfo.Arguments = sprintf(['-y -loglevel error -f rawvideo -pix_fmt gray -s %ix%i -r %g -i - ' ...
    '-c:v h264_nvenc -preset p4 -rc constqp -qp 18 -pix_fmt yuv420p "%s"'], res(1), res(2), P.eye_fps, file);
proc.StartInfo.UseShellExecute = false;
proc.StartInfo.RedirectStandardInput = true;
proc.StartInfo.CreateNoWindow = true;
proc.Start();
pipe = proc.StandardInput.BaseStream;
end

function saveFrames(vid, ~)
% FramesAcquiredFcn: take the frames in memory, send them to ffmpeg (h264),
% and keep the newest one for the preview. Raw video is written by the disk logger.
state = vid.UserData;
n = vid.FramesAvailable;
if n == 0 || ~isempty(state.error); return; end
try
    F = getdata(vid, n);                     % H x W x 1 x n
    F = reshape(F, size(F, 1), size(F, 2), []);
    if ~isempty(state.pipe)
        buf = NET.convertArray(reshape(permute(F, [2 1 3]), [], 1), 'System.Byte'); % ffmpeg reads row by row
        state.pipe.Write(buf, 0, buf.Length);
        state.written = state.written + n;
    end
    state.last = F(:,:,end);
catch err
    state.error = err.message;
end
vid.UserData = state;
end
