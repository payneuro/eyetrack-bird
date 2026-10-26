function [E, p] = trackEye(filepath_eye, p, camfilename, opts)
% [E, p] = trackEye(filepath_eye, p, camfilename, opts)
% Track pupil and corneal reflections in both eye videos, frame by frame.
% Saves eye.mat every 100 frames; if eye.mat has an 'ii' field, the next run
% resumes from the last tracked frame.
%
% opts (all optional):
%   ah           - [ax1 ax2] axes to draw into (default: new figure)
%   stop_fcn     - @() logical, checked each frame; true saves and stops
%   progress_fcn - @(done, total) frames to track done so far and in all
%                  (only frames with the bird when skipping), every 100 frames
%   show_summary - plot pupil/CR traces at the end (default true)
%   skip_empty_frames - skip frames without the bird (findBirdFrames); they
%                  stay NaN (default P.skip_empty_frames)
%   P            - eyetrackParams for findBirdFrames (default eyetrackParams())

if ~exist('opts','var'); opts = struct; end
if ~isfield(opts,'stop_fcn'); opts.stop_fcn = @() false; end
if ~isfield(opts,'progress_fcn'); opts.progress_fcn = @(ii,N) []; end
if ~isfield(opts,'show_summary'); opts.show_summary = true; end
if ~isfield(opts,'P'); opts.P = eyetrackParams(); end
if ~isfield(opts,'skip_empty_frames'); opts.skip_empty_frames = opts.P.skip_empty_frames; end
disp(filepath_eye)

% Load the high res video
[vid1, vid2, N_eye] = openEyeVideos(filepath_eye, camfilename);
fprintf('Frames: %i\n', N_eye)
frameRate = vid1.FrameRate;

%% Set up figure
plot_handles1 = [];
plot_handles2 = [];
if isfield(opts,'ah') && all(isgraphics(opts.ah))
    plot_handles1.ah = opts.ah(1);
    plot_handles2.ah = opts.ah(2);
    cla(opts.ah(1)); cla(opts.ah(2));
else
    figure;
    plot_handles1.ah = subplot(1,2,1);
    apos =  [0.0125    0.025    0.45    0.95];
    set(plot_handles1.ah,'Pos',apos);
    plot_handles2.ah = subplot(1,2,2);
    set(plot_handles2.ah,'Pos',apos+[0.5 0 0 0]); drawnow
end

%% Frames to track
in_view = true(N_eye, 1);
if opts.skip_empty_frames
    B = findBirdFrames(filepath_eye, camfilename, opts.P);
    n = min(N_eye, numel(B.in_view));
    in_view(1:n) = B.in_view(1:n); % kept in frames_in_view.mat, not E (E's fields all get filtered later)
end
n_done = cumsum(in_view); % frames to track up to each frame, for progress_fcn

%% Plot an example frame to get pupil and iris thresholds
if ~isfield(p,'example_t') || isempty(p(1).example_t)
    p(1).example_t = 0;
end
ii_example = min(N_eye, max(1, round(p(1).example_t*frameRate)));
if ~in_view(ii_example) && any(in_view(ii_example:end)) % first frame with the bird from there
    ii_example = ii_example - 1 + find(in_view(ii_example:end), 1);
end
[I1, I2] = readEyeFrames(vid1, vid2, ii_example, p);

% Run pupil and CR detection in each image
[pupil1_temp,cr1_temp, ~, ~, points1] = detectPupilCR(I1, p(1).edge_thresh0, p(1));
[pupil2_temp,cr2_temp, ~, ~, points2] = detectPupilCR(I2, p(2).edge_thresh0, p(2));
plot_handles1 = detectPupilCRPlot(I1, p(1), plot_handles1, pupil1_temp, squeeze(cr1_temp), points1);
plot_handles2 = detectPupilCRPlot(I2, p(2), plot_handles2, pupil2_temp, squeeze(cr2_temp), points2);

disp('Adjust pupil and iris intensities and quit/restart if needed')

clear I1 I2 % to save memory

%% Init
if ~exist(fullfile(filepath_eye,'eye.mat'),'file')
    E = [];
    E.pupil1 = NaN(N_eye,5);
    E.cr1 = NaN(N_eye,3, p(1).nCRs);
    E.pupil2 = NaN(N_eye,5);
    E.cr2 = NaN(N_eye,3, p(1).nCRs);
    E.resid1 = NaN(N_eye,1);
    E.resid2 = NaN(N_eye,1);
    E.points_fraction1 = NaN(N_eye,1);
    E.points_fraction2 = NaN(N_eye,1);
    ii_start = 1;
else
    old = load(fullfile(filepath_eye,'eye.mat'));
    E = old.E;
    ii_start = find(~isnan(E.pupil1(:,1)),1, 'last')+1;
    if isempty(ii_start); ii_start = 1; end
    p(1).pupil_start = old.p(1).pupil_start;
    p(2).pupil_start = old.p(2).pupil_start;
    clear old
end

% Initialize eye results, different settings for each camera
edge_thresh1 = p(1).edge_thresh0;
edge_thresh2 = p(2).edge_thresh0;
bad_frame_count = 0;

%% Loop over camera frames
for ii = ii_start:N_eye

    if opts.stop_fcn()
        save(fullfile(filepath_eye,'eye.mat'),'E','p','ii')
        fprintf('Stopped at frame %i. Run again to resume.\n', ii)
        return
    end

    if ~in_view(ii) % bird out of view: leave NaN, search the whole frame when it's back
        p(1).pupil_start = [NaN NaN];
        p(2).pupil_start = [NaN NaN];
        edge_thresh1 = p(1).edge_thresh0;
        edge_thresh2 = p(2).edge_thresh0;
        if mod(ii, 100)==0; opts.progress_fcn(n_done(ii), n_done(end)); end
        continue
    end

    % Load image
    [I1, I2] = readEyeFrames(vid1, vid2, ii, p);

    % Run pupil and CR detection in each image
    [E.pupil1(ii,:),E.cr1(ii,:,:), edge_thresh1, E.resid1(ii), points1] = ...
        detectPupilCR(I1, max(p(1).min_edge_thresh+4,edge_thresh1+4), p(1));
    [E.pupil2(ii,:), E.cr2(ii,:,:), edge_thresh2, E.resid2(ii), points2] = ...
        detectPupilCR(I2, max(p(2).min_edge_thresh+4,edge_thresh2+4), p(2));

    plot_handles1 = detectPupilCRPlot(I1, p(1), plot_handles1, E.pupil1(ii,:), squeeze(E.cr1(ii,:,:)), points1);
    plot_handles2 = detectPupilCRPlot(I2, p(2), plot_handles2, E.pupil2(ii,:), squeeze(E.cr2(ii,:,:)), points2);

    % If either one fails, reset position of both
    if isnan(E.pupil1(ii,1)) || isnan(E.pupil2(ii,1))
        E.pupil1(ii,:) = NaN;  E.pupil2(ii,:) = NaN;
        bad_frame_count = bad_frame_count+1;
        edge_thresh1 = p(1).edge_thresh0;
        edge_thresh2 = p(2).edge_thresh0;
        if bad_frame_count>=p(1).max_bad_frames
            p(1).pupil_start = [NaN NaN];
            p(2).pupil_start = [NaN NaN];
        end
    else
        % Init pupil search from last location
        p(1).pupil_start = E.pupil1(ii,1:2);
        p(2).pupil_start = E.pupil2(ii,1:2);
        bad_frame_count = 0;
    end

    if mod(ii, 100)==0
        fprintf('%i/%i\n', ii, N_eye)
        opts.progress_fcn(n_done(ii), n_done(end));
        save(fullfile(filepath_eye,'eye.mat'),'E','p','ii')
    end
end
save(fullfile(filepath_eye,'eye.mat'),'E','p')
opts.progress_fcn(n_done(end), n_done(end));


%% Plot results
if opts.show_summary
    [~, session] = fileparts(filepath_eye);
    figure;
    subplot(2,1,1); plot(E.pupil1(:,1:2)); legend({'x','y'})
    ylabel('Pixels (cropped image)')
    title([session ': camera 1 pupil center'], 'Interpreter', 'none')
    subplot(2,1,2); plot(E.pupil2(:,1:2)); legend({'x','y'})
    xlabel('Eye frame #'); ylabel('Pixels (cropped image)')
    title('Camera 2 pupil center')
    linkaxes

    figure;
    subplot(2,1,1); plot(E.cr1(:,1:2)); legend({'x','y'})
    ylabel('Pixels (cropped image)')
    title([session ': camera 1 corneal reflection a'], 'Interpreter', 'none')
    subplot(2,1,2); plot(E.cr2(:,1:2)); legend({'x','y'})
    xlabel('Eye frame #'); ylabel('Pixels (cropped image)')
    title('Camera 2 corneal reflection a')
    linkaxes
    drawnow
end
