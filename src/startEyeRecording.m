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
rec = struct('cams', cams, 'format', format, 'files', {files}, 'exposure0', [cams(1).src.ExposureTime, cams(2).src.ExposureTime]);

for k = 1:2
    vid = cams(k).vid;
    if ~isempty(exposure_us)
        setCameraExposure(cams(k), exposure_us);
    end
    cams(k).src.TriggerMode = 'On'; % frame on each TTL (trigger source and edge as set up in SpinView)
    triggerconfig(vid, 'immediate');
    vid.FramesPerTrigger = Inf;
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
