function [ffmpeg, gpu_ok, version] = findFfmpeg(ffmpeg)
% [ffmpeg, gpu_ok, version] = findFfmpeg(ffmpeg)
% Locate ffmpeg.exe: the given path (P.ffmpeg) if it exists, else ffmpeg on
% the system PATH, else ''. With more outputs, also test whether it can
% encode H.264 on the NVIDIA GPU (h264_nvenc; fails if the driver is too old
% for this ffmpeg version) and return its version string.

if ~isfile(ffmpeg)
    [status, out] = system('where ffmpeg');
    if status == 0
        ffmpeg = strtrim(extractBefore([out newline], newline));
    else
        ffmpeg = '';
    end
end
gpu_ok = false; version = '';
if nargout < 2 || isempty(ffmpeg); return; end
[~, out] = system(sprintf('"%s" -version', ffmpeg));
version = char(regexp(out, '(?<=ffmpeg version )\S+', 'match', 'once'));
status = system(sprintf(['"%s" -hide_banner -loglevel error -f lavfi -i color=gray:s=320x240:r=50 ' ...
    '-frames:v 10 -c:v h264_nvenc -pix_fmt yuv420p -f null -'], ffmpeg));
gpu_ok = status == 0;
end
