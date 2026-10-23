function B = findBirdFrames(filepath_eye, camfilename, P, show, progress_fcn)
% B = findBirdFrames(filepath_eye, camfilename, P, show, progress_fcn)
% Find the video frames where the bird is in view, so tracking can skip the
% rest. Each frame is shrunk P.bird_shrink times per side (each pixel = mean
% of a block) and compared with a background: the median
% of every 10th frame. The bird drops out of the median as long as it moves
% around (tested with the bird in view 85% of the time); a bird sitting
% still in one spot for most of the session would become background. A frame
% has the bird if more than P.bird_frac_thresh of its pixels differ from the
% background by more than P.bird_pixel_thresh gray levels, in either camera.
% In-view stretches are padded by P.bird_pad_s on each side.
% Results are cached in bird_frames.mat and recomputed if the settings change.
%
% B.in_view  - N x 1 logical, true = track this frame
% B.frac     - N x 2 fraction of changed pixels per camera
% B.bg       - {cam1, cam2} background images (small)
% show         - plot the steps (default false)
% progress_fcn - @(fraction) called while the videos are read (optional)

if ~exist('show', 'var'); show = false; end
if ~exist('progress_fcn', 'var'); progress_fcn = @(f) []; end
settings = struct('frac_thresh', P.bird_frac_thresh, 'pad_s', P.bird_pad_s);
measure = struct('shrink', P.bird_shrink, 'pixel_thresh', P.bird_pixel_thresh); % changing these means re-reading the videos
cache = fullfile(filepath_eye, 'bird_frames.mat');
B = [];
if isfile(cache)
    B = getfield(load(cache), 'B');
    if ~isfield(B, 'measure') || ~isequal(B.measure, measure)
        B = [];
    elseif ~isequal(B.settings, settings)
        B = threshold(B, settings);
        save(cache, 'B');
    end
end
if isempty(B)
    [small, fps] = readSmallFrames(filepath_eye, camfilename, measure.shrink, progress_fcn);
    B = struct('fps', fps, 'measure', measure, 'frac', [], 'bg', {cell(1, 2)});
    N = min(size(small{1}, 3), size(small{2}, 3));
    for cam = 1:2
        B.bg{cam} = median(small{cam}(:,:,1:10:N), 3); % (choosing the darkest frames instead failed: lighting flicker)
        bg = single(B.bg{cam});
        for i0 = 1:5000:N % in chunks: a whole hour as single would need ~8 GB per camera
            ii = i0:min(N, i0 + 4999);
            B.frac(ii, cam) = squeeze(mean(abs(single(small{cam}(:,:,ii)) - bg) > measure.pixel_thresh, [1 2]));
        end
    end
    B = threshold(B, settings);
    save(cache, 'B');
end
fprintf('Bird in view in %i of %i frames (%.0f%%)\n', sum(B.in_view), numel(B.in_view), 100*mean(B.in_view));
if show
    plotBirdFrames(B, filepath_eye);
end
end

function B = threshold(B, settings)
B.settings = settings;
pad = round(settings.pad_s*B.fps);
B.in_view = movmax(any(B.frac > settings.frac_thresh, 2), [pad pad]);
end

function [small, fps] = readSmallFrames(filepath_eye, camfilename, scale, progress_fcn)
% Every frame of both videos at 1/scale size per side, gray. ffmpeg decodes
% ~1000 fps at 1/16; VideoReader (if ffmpeg is missing) is ~50 fps.
% Calls progress_fcn(fraction of both videos read) as it goes.
ffmpeg = findFfmpeg(eyetrackParams().ffmpeg);
small = cell(1, 2);
for cam = 1:2
    d = dir(fullfile(filepath_eye, sprintf(camfilename, cam)));
    file = fullfile(d(1).folder, d(1).name);
    v = VideoReader(file);
    fps = v.FrameRate;
    w = round(v.Width/scale); h = round(v.Height/scale);
    n_expected = round(v.Duration*fps);
    fprintf('Reading cam%i at 1/%i size... ', cam, scale);
    if ~isempty(ffmpeg)
        raw = [tempname '.raw'];
        % Run ffmpeg as a separate process and wait with drawnow, so a GUI
        % stays responsive (and its busy indicator moves) while it decodes
        proc = System.Diagnostics.Process;
        proc.StartInfo.FileName = ffmpeg;
        proc.StartInfo.Arguments = sprintf('-y -loglevel error -i "%s" -vf scale=%i:%i:flags=area,format=gray -f rawvideo "%s"', ...
            file, w, h, raw);
        proc.StartInfo.UseShellExecute = false;
        proc.StartInfo.CreateNoWindow = true;
        proc.Start();
        while ~proc.WaitForExit(250)
            f = dir(raw); % the output grows by w*h bytes per frame
            if ~isempty(f); progress_fcn((cam - 1 + min(1, f.bytes/(w*h*n_expected)))/2); end
            drawnow
        end
        if proc.ExitCode ~= 0; error('ffmpeg could not read %s (exit code %i)', file, proc.ExitCode); end
        fid = fopen(raw); x = fread(fid, Inf, 'uint8=>uint8'); fclose(fid); delete(raw);
        small{cam} = permute(reshape(x, w, h, []), [2 1 3]); % ffmpeg is row by row
    else
        small{cam} = zeros(h, w, v.NumFrames, 'uint8');
        for ii = 1:v.NumFrames
            I = readFrame(v);
            small{cam}(:,:,ii) = imresize(I(:,:,1), [h w], 'box');
            if mod(ii, 500) == 0; progress_fcn((cam - 1 + ii/v.NumFrames)/2); drawnow; end
        end
    end
    fprintf('%i frames\n', size(small{cam}, 3));
end
end

function plotBirdFrames(B, filepath_eye)
% Top: the background each camera's frames are compared with. Bottom: the
% fraction of changed pixels across the session, with the tracked frames.
[~, session] = fileparts(filepath_eye);
N = numel(B.in_view);
t = (1:N)'/B.fps;
fig = figure('Name', ['Bird frames ' session], 'Position', [60 60 1300 750]);
tl = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
for cam = 1:2
    ax = nexttile(tl);
    imagesc(ax, B.bg{cam}, [0 255]); colormap(ax, gray); axis(ax, 'image', 'off');
    title(ax, sprintf('%s cam%i background: median frame', session, cam), 'Interpreter', 'none');
end

ax = nexttile(tl, [1 2]);
area(ax, t, B.in_view*max(B.frac(:)), 'FaceColor', [0.85 0.95 0.85], 'EdgeColor', 'none'); hold(ax, 'on');
plot(ax, t, B.frac(:,1), t, B.frac(:,2));
yline(ax, B.settings.frac_thresh, 'r'); hold(ax, 'off');
xlim(ax, [0 t(end)]); xlabel(ax, 'Time (s)');
ylabel(ax, sprintf('Fraction of pixels > %i off', B.measure.pixel_thresh));
legend(ax, {'tracked', 'cam1', 'cam2', 'threshold'});
title(ax, sprintf('Across the session: tracked %i of %i frames (%.0f%%, green), padded %.2g s', ...
    sum(B.in_view), N, 100*mean(B.in_view), B.settings.pad_s));
drawnow
end
