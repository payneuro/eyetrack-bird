function slopes = plotYawCheck(H, Eout, plot_on, name, before, up)
% slopes = plotYawCheck(H, Eout, plot_on, name, before, up)
% Camera-to-QTM check: each eye's position in the head frame vs head yaw.
% With the eye cameras and QTM aligned, an eye stays at the same place in
% the head whatever the head's yaw (flat lines). If the eye cameras shifted
% relative to QTM after the axes calibration, positions drift with yaw, and
% each eye drifts along a different head axis because the eyes are seen at
% different yaws. To fit and remove such a shift (shift + rotation about
% vertical), run runEyetrackSingle(session_folder, [], [], true).
% H, Eout - from analyzeEyetrack
% name    - session name for the figure title (optional)
% before  - struct with fields H and Eout from the uncorrected analysis
%           (optional): plotted underneath in grey, with dashed fit lines
% up      - 1 x 3 vertical in the common frame, about which yaw is measured
%           (optional, default [0 0 1]; runEyetrackSingle passes QTM's vertical)
% slopes  - 2 x 3: rows left, right eye; columns x, y, z; mm per degree of yaw

if ~exist('name', 'var'); name = ''; end
if ~exist('before', 'var'); before = []; end
if ~exist('up', 'var') || isempty(up); up = [0 0 1]; end
up = up(:)' / norm(up);
eye_names = {'Left eye', 'Right eye'};
axis_names = {'x: toward beak', 'y: toward left eye', 'z: up'};
colors = {[0 0.75 0.85], [0 0.2 0.9]}; % left cyan, right blue (as in analyzeEyetrack)
sets = {H, Eout, [], '-k'}; % {H, Eout, color (empty = per eye), fit line}
if ~isempty(before)
    sets = [{before.H, before.Eout, [0.65 0.65 0.65], '--'}; sets];
end
fits = cell(size(sets, 1), 2, 3); % fitted [intercept slope] per set, eye, axis
pos = cell(size(sets, 1), 2);     % {yaw, position} per set and eye
for k = 1:size(sets, 1)
    [ph, yaw] = headFramePositions(sets{k, 1}, sets{k, 2}, up);
    masks = {sets{k, 2}.mask_eye_L, sets{k, 2}.mask_eye_R};
    for e = 1:2
        m = masks{e} & ~isnan(ph(:,1));
        y = unwrapAroundMean(yaw(m));
        pos{k, e} = {y, ph(m, :)};
        for a = 1:3
            if nnz(m) >= 2; fits{k, e, a} = [ones(nnz(m), 1) y] \ ph(m, a); end
        end
    end
end
slopes = NaN(2, 3);
for e = 1:2
    for a = 1:3
        if ~isempty(fits{end, e, a}); slopes(e, a) = fits{end, e, a}(2); end
    end
end
if ~plot_on; return; end

fig = figure('Name', ['Camera-QTM check ' name]);
tl = tiledlayout(fig, 2, 3, 'TileSpacing', 'compact');
for e = 1:2
    for a = 1:3
        ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on');
        for k = 1:size(sets, 1)
            [yaw, ph] = pos{k, e}{:};
            if isempty(fits{k, e, a}); continue; end
            col = sets{k, 3}; if isempty(col); col = colors{e}; end
            scatter(ax, yaw, ph(:, a), 10, col, 'filled', 'MarkerFaceAlpha', .5);
            yl = [min(yaw) max(yaw)];
            plot(ax, yl, fits{k, e, a}(1) + fits{k, e, a}(2)*yl, sets{k, 4}, 'Color', 'k', 'LineWidth', 1.5);
        end
        xlabel(ax, 'Head yaw (deg)'); ylabel(ax, [axis_names{a} ' (mm)']);
        if isempty(before)
            txt = {sprintf('%s %s: %+.3f mm/deg', eye_names{e}, axis_names{a}(1), slopes(e, a))};
        else
            txt = {sprintf('%s %s: %+.3f -> %+.3f mm/deg', eye_names{e}, axis_names{a}(1), fits{1, e, a}(2), slopes(e, a))};
        end
        if e == 1 && a == 1 % session and what to look for, in the first panel's title
            what = 'camera-QTM check (lines should be flat)';
            if ~isempty(before); what = 'camera-QTM check, grey/dashed = before correction'; end
            txt = [{sprintf('%s %s', name, what)}, txt];
        end
        title(ax, txt, 'Interpreter', 'none', 'FontSize', 9);
    end
end
xlabel(tl, ['Sloped lines = eye cameras moved relative to QTM. To fit and remove the shift: check Correct offset, or ' ...
    'runEyetrackSingle(session_folder, [], [], true)'], 'Interpreter', 'none');
drawnow
end

function [ph, yaw] = headFramePositions(H, Eout, up)
% Per-frame eye positions in the head frame, and head yaw: heading of the
% beak axis about the vertical up (common frame)
ph = (H.R_head' * (Eout.p_eye_local' - H.p_head))';
e1 = [1 0 0] - dot([1 0 0], up)*up; e1 = e1/norm(e1); % horizontal axes
e2 = cross(up, e1);
N = size(ph, 1);
yaw = NaN(N, 1);
for j = 1:N
    vx = squeeze(Eout.R_rigidbody_ds(j,:,:)) * H.R_head(:,1);
    yaw(j) = atan2d(dot(vx, e2), dot(vx, e1));
end
end

function yaw = unwrapAroundMean(yaw)
% Put angles within +-180 deg of their circular mean, so an eye seen around
% +-180 deg isn't split to both ends of the axis
mu = atan2d(mean(sind(yaw), 'omitnan'), mean(cosd(yaw), 'omitnan'));
yaw = mu + mod(yaw - mu + 180, 360) - 180;
end
