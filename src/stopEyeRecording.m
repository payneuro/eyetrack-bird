function result = stopEyeRecording(rec)
% result = stopEyeRecording(rec)
% Stop a recording from startEyeRecording, finish writing both videos, and
% restore each camera's exposure (trigger mode stays on the hardware trigger).
% result - table with frames acquired and written per camera, the files,
%          and any error

acquired = zeros(2, 1); written = zeros(2, 1); err = {''; ''};
for k = 1:2
    stop(rec.cams(k).vid);
end
for k = 1:2
    vid = rec.cams(k).vid;
    acquired(k) = vid.FramesAcquired;
    feval(vid.FramesAcquiredFcn, vid, []); % save the frames left in memory
    state = vid.UserData;
    if strcmp(rec.format, 'raw')
        t = tic; % let the disk logger catch up
        while vid.DiskLoggerFrameCount < vid.FramesAcquired && toc(t) < 120
            pause(0.2);
        end
        written(k) = vid.DiskLoggerFrameCount;
        writer = vid.DiskLogger;
        close(writer);
    else
        written(k) = state.written;
        state.pipe.Close();
        state.proc.WaitForExit(120000);
        if state.proc.ExitCode ~= 0
            state.error = strtrim([state.error sprintf(' ffmpeg exit code %i', state.proc.ExitCode)]);
        end
    end
    err{k} = state.error;
    vid.FramesAcquiredFcn = '';
    triggerconfig(vid, 'immediate'); % as before recording; the camera's TriggerMode stays On
    vid.FramesPerTrigger = 1;
    vid.TriggerRepeat = 0;
    vid.LoggingMode = 'memory';
    flushdata(vid);
    vid.UserData = [];
    rec.cams(k).src.ExposureTime = rec.exposure0(k);
end
result = table((1:2)', acquired, written, rec.files(:), err, ...
    'VariableNames', {'cam', 'acquired', 'written', 'file', 'error'});
