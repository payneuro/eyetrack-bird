function [H, Ht, stats, Eout] = analyzeEyetrack(Eraw, p_pupil0, p_cornea0, p_beak,  Q_raw, downsample_eye, dist_pc, plot_on)
% [H, Ht, stats, Eout] = analyzeEyetrack(Eraw, p_pupil0, p_cornea0, p_beak, Q_raw, downsample_eye, dist_pc, plot_on)
% Clean the eye tracking, then fit each eye's position and gaze direction and
% the beak tip in the head (rigid-body) frame. Inputs are in the common frame
% (alignCommonReferenceFrame).
% H     - head/eye/beak geometry relative to the rigid body
% Ht    - one-row summary table (eye angles relative to the beak)
% stats - spread of eye angles and pupil-cornea distance
% Eout  - per-frame left/right eye masks, eye-in-head vectors, eye positions and head poses
% plot_on - draw the diagnostic figures (default true); results are the same either way

if ~exist('plot_on', 'var') || isempty(plot_on); plot_on = true; end

%% Load Qualisys rigid body
N_head = Q_raw.N_head;
fps_head = Q_raw.fps_head;
p_rigidbody = Q_raw.p_rigidbody;
R_rigidbody = Q_raw.R_rigidbody;

%% Get camera calibration
N_eye = size(Eraw.pupil1,1);
t_head = (0:N_head-1)/fps_head;
dt_eye = 1/fps_head*downsample_eye; % 1/fps
t_eye = (0:N_eye-1)'*dt_eye;
Eraw.t = t_eye;

%% Clean up eye tracking results
scale = 1;
[E, nanmask] = cleanEye(Eraw,scale);
if plot_on; plotEye(E); end
p_pupil = p_pupil0;
p_cornea = p_cornea0;
p_pupil(nanmask,:) = NaN;
p_cornea(nanmask,:) = NaN;

% Exclude points where the pupil-ccc distance is too far off from the median
thresh_dist_p_c = 0.1; % Fraction away from median distance to exclude
K = median(dist_pc,'omitnan'); % (mm)
mask_dist_pc = (abs(dist_pc - K)/K)> thresh_dist_p_c*scale;
p_pupil(mask_dist_pc,:) = NaN;
p_cornea(mask_dist_pc,:) = NaN;
mean_pupil_cc = nanmean(dist_pc(~mask_dist_pc));
fprintf('Mean pupil-ccc distance: %.2f mm. mask_dist_p_c %.3f\n', mean_pupil_cc, mean(mask_dist_pc))


%% Calculate eye locations/vectors and head locations/vectors relative to common axis reference frame
% Get a unit vector pointing in the direction of the eye
v_eye = (p_pupil-p_cornea)./sqrt(sum((p_pupil-p_cornea).^2, 2));
v_eye_common = v_eye; % per frame; v_eye is reused below for each eye's mean

% Smooth then downsample head to match eye
temp = [];
temp.p = p_rigidbody;
temp.R = shiftdim(R_rigidbody,2);
temp = processStruct(temp, @(x) movingAverage(x, downsample_eye)); % = smooth(x, n, 'moving')
ind_downsample = 1:downsample_eye:N_eye*downsample_eye-1;
p_rigidbody_ds = temp.p(ind_downsample,:);
R_rigidbody_ds = temp.R(ind_downsample,:,:);



%% Get eye points+vectors in local rigidbody frame.
% Take eye to be center of corneal curvature. This is not exactly correct,
% but we don't know which point the eye rotates about anyway. This doesn't
% affect the angle.
% Could be corrected (prior to alignCommonReferenceFrame) to be ~1.0 mm farther away along the camera axis, which is half the radius of the cornea (cornea diameter = 4.13 mm in Carolina chickadees, Moore 2013))
p_eye = p_cornea;

p_eye_local = NaN(N_eye,3);
v_eye_local = NaN(N_eye,3);
for jj = 1:N_eye
    p_eye_local(jj,:) = squeeze(R_rigidbody_ds(jj,:,:))'*(p_eye(jj,:)-p_rigidbody_ds(jj,:))';
    v_eye_local(jj,:) = squeeze(R_rigidbody_ds(jj,:,:))'*(v_eye(jj,:))';
end


%% Get beak in local rigidbody frame


% Convert from common world coords to local rigidbody coordinates
p_beak_local_all = NaN(N_eye,3);
for jj = 1:N_eye
    p_beak_local_all(jj,:) = squeeze(R_rigidbody_ds(jj,:,:))'*(p_beak(jj,:) - p_rigidbody_ds(jj,:))';
end
p_beak_local = mean(p_beak_local_all,'omitnan');
d_beak = sqrt(sum((p_beak_local_all-p_beak_local).^2,2));
beak_inds = find(~isnan(d_beak));
beak_dists = d_beak(~isnan(d_beak));
disp(table(beak_inds, beak_dists))

%% Determine orientation and categorize eyes as left and right
p_head_local_temp = nanmean(p_eye_local,1); % very approximate
vx_head_local = (p_beak_local-p_head_local_temp)/norm(p_beak_local-p_head_local_temp);
flag_reverse = false;
if dot(vx_head_local, [0 1 0])<0
    flag_reverse = true;
    warning('reverse eye orientation')
end

divide_RL = 10;
if flag_reverse
    mask_eye_R = p_eye_local(:,1)<divide_RL; 
    mask_eye_L = p_eye_local(:,1)>divide_RL;
else
    mask_eye_R = p_eye_local(:,1)>divide_RL; 
    mask_eye_L = p_eye_local(:,1)<divide_RL;
end

%% Get mask for eye positions that are out of range
% Outliers: modified z-score M = 0.6745*(x - median)/MAD above max_z
% (Iglewicz & Hoaglin 1993), so the cutoffs are median +- max_z*MAD/0.6745.
% Unlike mean +- SD, outlier clusters barely move them.
max_z = 3.5;
MAD = @(x) median(abs(x - median(x,'omitnan')),'omitnan');
getMax = @(x) median(x,'omitnan') + max_z*MAD(x)/0.6745;
getMin = @(x) median(x,'omitnan') - max_z*MAD(x)/0.6745;

% Position cutoffs per eye and per axis (lateral, anterior, dorsal):
% cut(eye, [min max], axis), eye 1 = right, 2 = left
eye_masks = {mask_eye_R, mask_eye_L};
cut = NaN(2, 2, 3);
for e = 1:2
    for a = 1:3
        x = p_eye_local(eye_masks{e}, a);
        cut(e, :, a) = [getMin(x) getMax(x)];
    end
end

if plot_on
figure
axis_names = {'x coord/lateral', 'y coord/anterior', 'z coord/dorsal'};
cut_txt = sprintf('cutoffs |M| = %g: cyan = left eye, blue = right eye', max_z); % modified z-score
eye_colors = {[0 0.2 0.9], [0 0.75 0.85]}; % cut(1,...) = right eye (blue), cut(2,...) = left eye (cyan)
titles = {{'Lateral eye position', ['black = L/R split, ' cut_txt]}, {'Anterior eye position', cut_txt}, {'Dorsal eye position', cut_txt}};
edges = {0:.1:18, min(cut(:,1,2))-4:.1:max(cut(:,2,2))+4, -35:.1:-25};
for a = 1:3
    subplot(2,2,a)
    histogram(p_eye_local(:,a), [-inf edges{a} inf]); xlabel(['p_eye_local (' axis_names{a} ' pos, mm)'],'interp','none')
    hold on; title(titles{a}); ylabel('Frame count')
    if a == 1; dashedline(divide_RL, ylim,6,'Color','k'); end
    for e = 1:2
        dashedline(cut(e,1,a), ylim,6,'Color',eye_colors{e});
        dashedline(cut(e,2,a), ylim,6,'Color',eye_colors{e});
    end
end

subplot(2,2,4)
histogram(v_eye(:,2),-1:.05:0); xlabel('v_eye (y)','interp','none')
hold on; title({'Eye vector y component, common frame', sprintf('red = modified z-score cutoff (|M| = %g)', max_z)}); ylabel('Frame count')
dashedline(getMin(v_eye(:,2)), ylim,6,'Color','r');
dashedline(getMax(v_eye(:,2)), ylim,6,'Color','r');
drawnow
end

% Mask position 
mask_out = false(length(p_eye_local), 3); % outside its eye's cutoffs, per axis
for e = 1:2
    for a = 1:3
        x = p_eye_local(eye_masks{e}, a);
        mask_out(eye_masks{e}, a) = x < cut(e,1,a) | x > cut(e,2,a);
    end
end

% Mask angle: check if y axis (towards cameras) is way off
mask_vector = v_eye(:,2)>getMax(v_eye(:,2)) | v_eye(:,2)<getMin(v_eye(:,2)) ;

mask_pos = any(mask_out, 2) | mask_vector;
p_eye_local(mask_pos,:) = NaN;
v_eye_local(mask_pos,:) = NaN;

% Update L/R eye masks to exclude NaNs
if flag_reverse
    mask_eye_R = p_eye_local(:,1)<divide_RL; % ***Update this automatically?
    mask_eye_L = p_eye_local(:,1)>divide_RL;
else
    mask_eye_R = p_eye_local(:,1)>divide_RL; % ***Update this automatically?
    mask_eye_L = p_eye_local(:,1)<divide_RL;
end

%% Store the mean vector and origin for each eye, plus the average beak location, in the head frame

% Get means for each eye
p_eye_R_local = mean(p_eye_local(mask_eye_R,:),1,'omitnan');
p_eye_L_local = mean(p_eye_local(mask_eye_L,:),1,'omitnan');
v_eye_R_local = mean(v_eye_local(mask_eye_R,:),1,'omitnan'); v_eye_R_local = v_eye_R_local/norm(v_eye_R_local);
v_eye_L_local = mean(v_eye_local(mask_eye_L,:),1,'omitnan'); v_eye_L_local = v_eye_L_local/norm(v_eye_L_local);

% Get the mean "head position": the mean of the two eyes
p_meaneye_local = mean([p_eye_R_local; p_eye_L_local]);

% use mean of two eyes:
p_head_local = p_meaneye_local;

% OR get the intersection point of the two eye vectors:
% A1 = p_eye_R_local;
% A2 = p_eye_R_local+v_eye_R_local;
% B1 = p_eye_L_local;
% B2 = p_eye_L_local+v_eye_L_local;
% nA = dot(cross(B2-B1,A1-B1)',cross(A2-A1,B2-B1)')';
% nB = dot(cross(A2-A1,A1-B1)',cross(A2-A1,B2-B1)')';
% d = dot(cross(A2-A1,B2-B1)',cross(A2-A1,B2-B1)')';
% A0 = A1 + bsxfun(@times, nA./d, A2-A1);
% B0 = B1 + bsxfun(@times, nB./d, B2-B1);
% p_head_local = (A0+B0)/2;


%% Get the mean "head vector": from mean of eyes to beak
% TODO: it would be better to first define the y axis (line connecting two
% eyes), THEN define the x axis (midpoint of two eyes to tip of beak),
% since the beak measurement is less reliable. 
vx_head_local = (p_beak_local-p_head_local)/norm(p_beak_local-p_head_local);

% Define a rotation matrix to convert from the local rigid body reference frame to the "head" (beak-eyes) reference frame.
vy_head_local = (p_eye_L_local - p_eye_R_local)/norm(p_eye_L_local-p_eye_R_local);
vy_head_local = vy_head_local - dot(vy_head_local, vx_head_local)*vx_head_local; % Get component of vy that is orthogonal to vx
vy_head_local= vy_head_local/norm(vy_head_local);
vz_head_local = cross(vx_head_local, vy_head_local);
R_head_local = [vx_head_local(:) vy_head_local(:) vz_head_local(:)];
% x = pointing from eye intersection to beak, y = pointing to the left, z = pointing up (airplane coords, so +pitch = upwards, +yaw = ?

% Save the results of this head/eye/beak calibration!! All measurements are
% relative to the QTM rigid body reference frame
H = [];
H.p_head = p_head_local(:);
H.p_beak = p_beak_local(:);
H.R_head = R_head_local; % This is the head coordinates (beak, left, up) relative to the rigid body ref frame
H.p_eye_R = p_eye_R_local(:);
H.p_eye_L = p_eye_L_local(:);
H.v_eye_R = v_eye_R_local(:);
H.v_eye_L = v_eye_L_local(:);

% Add local vectors of eye relative to head
H.v_eye_R_head = H.R_head'*H.v_eye_R;
H.v_eye_L_head = H.R_head'*H.v_eye_L;

%% Eye and beak positions: 3D view (rigid-body frame) and top, side, front views (head frame), one figure
% Eye positions and gaze vectors in the head frame (x toward beak, y toward left eye, z up)
v_eye_local_head = v_eye_local*H.R_head;
p_eye_local_head = (H.R_head'*(p_eye_local - p_head_local)')';
p_eye_R_head = H.R_head'*(H.p_eye_R - p_head_local(:));
p_eye_L_head = H.R_head'*(H.p_eye_L - p_head_local(:));
v_beak_head = H.R_head'*vx_head_local'; % should be [1 0 0]
ds = 6; % plot every 6th frame
a = 6; % (mm) length of the mean gaze vectors
c = 6; % (mm) length of the per-frame gaze vectors
b = norm(p_beak_local-p_head_local); % (mm) eye midpoint to beak

if plot_on
tl = tiledlayout(figure, 2, 2, 'TileSpacing', 'compact');

% 3D, rigid-body frame
ax = nexttile(tl); hold(ax, 'on');
scatter3(ax, p_eye_local(1:ds:end,1), p_eye_local(1:ds:end,2), p_eye_local(1:ds:end,3), 30, 'k.'); % per-frame eyes
for ii = 1:ds:N_eye
    if ~isnan(p_eye_local(ii,1))
        plot3(ax, p_eye_local(ii,1) + a*[0 v_eye_local(ii,1)], p_eye_local(ii,2) + a*[0 v_eye_local(ii,2)], ...
            p_eye_local(ii,3) + a*[0 v_eye_local(ii,3)], 'k', 'LineWidth', .25);
    end
end
msize3 = 60;
scatter3(ax, p_head_local(1), p_head_local(2), p_head_local(3), msize3, 'om', 'Filled')
scatter3(ax, p_eye_R_local(1), p_eye_R_local(2), p_eye_R_local(3), msize3, 'oc', 'Filled')
scatter3(ax, p_eye_L_local(1), p_eye_L_local(2), p_eye_L_local(3), msize3, 'oc', 'Filled')
plot3(ax, p_eye_R_local(1)+[0 v_eye_R_local(1)*a], p_eye_R_local(2)+[0 v_eye_R_local(2)*a], p_eye_R_local(3)+[0 v_eye_R_local(3)*a], '-c', 'LineWidth', 2)
plot3(ax, p_eye_L_local(1)+[0 v_eye_L_local(1)*a], p_eye_L_local(2)+[0 v_eye_L_local(2)*a], p_eye_L_local(3)+[0 v_eye_L_local(3)*a], '-c', 'LineWidth', 2)
mask = find(~isnan(p_beak(:,1)));
scatter3(ax, p_beak_local_all(mask,1), p_beak_local_all(mask,2), p_beak_local_all(mask,3), 10^2, '.m'); % beak clicks
scatter3(ax, p_beak_local(:,1), p_beak_local(:,2), p_beak_local(:,3), 40, '^m');
plot3(ax, p_head_local(1)+[0 vx_head_local(1)*b], p_head_local(2)+[0 vx_head_local(2)*b], p_head_local(3)+[0 vx_head_local(3)*b], '-m', 'LineWidth', 2)
xlabel(ax, 'x (mm)'); ylabel(ax, 'y (mm)'); zlabel(ax, 'z (mm)');
view(ax, 3) % 3D angle before vis3d, which fixes the zoom for the current view
axis(ax, 'equal'); axis(ax, 'vis3d'); % rotate by hand without distortion
grid(ax, 'on')

% 2D views, head frame: {horizontal axis, vertical axis, title, reverse both axes}
color_pts = 'k'; % per-frame eyes and gaze lines
msize = 20;
lw = 1;
names = {'x position (mm)', 'y position (mm)', 'z position (mm)'};
views = {1, 2, {'Head frame, top view', 'x toward beak, y toward left eye'}, true; ...
         1, 3, {'Side view', 'x toward beak, z up'}, false; ...
         2, 3, {'Front view', 'y toward left eye, z up'}, false};
for k = 1:size(views, 1)
    [dh, dv] = views{k, 1:2};
    ax = nexttile(tl); hold(ax, 'on');
    h = scatter(ax, p_eye_local_head(1:ds:end,dh), p_eye_local_head(1:ds:end,dv), 20, color_pts, 'filled'); % per-frame eyes
    for ii = 1:ds:N_eye
        if ~isnan(p_eye_local_head(ii,1))
            plot(ax, p_eye_local_head(ii,dh) + c*[0 v_eye_local_head(ii,dh)], ...
                p_eye_local_head(ii,dv) + c*[0 v_eye_local_head(ii,dv)], 'Color', color_pts, 'LineWidth', .25);
        end
    end
    h(2) = scatter(ax, p_eye_R_head(dh), p_eye_R_head(dv), msize, 'oc', 'Filled');
    scatter(ax, p_eye_L_head(dh), p_eye_L_head(dv), msize, 'oc', 'Filled')
    h(3) = plot(ax, p_eye_R_head(dh)+[0 H.v_eye_R_head(dh)*a], p_eye_R_head(dv)+[0 H.v_eye_R_head(dv)*a], '-c', 'LineWidth', lw);
    plot(ax, p_eye_L_head(dh)+[0 H.v_eye_L_head(dh)*a], p_eye_L_head(dv)+[0 H.v_eye_L_head(dv)*a], '-c', 'LineWidth', lw)
    scatter(ax, 0, 0, msize, 'om', 'Filled') % head origin (eye midpoint)
    h(4) = plot(ax, [0 v_beak_head(dh)*b], [0 v_beak_head(dv)*b], '-m', 'LineWidth', lw);
    xlabel(ax, names{dh}); ylabel(ax, names{dv});
    title(ax, views{k, 3})
    if views{k, 4}
        set(ax, 'ydir', 'reverse', 'xdir', 'reverse');
    end
    axis(ax, 'equal');
    lims = {[-2 19], 11*[-1 1], 11*[-1 1]}; % x, y, z
    xlim(ax, lims{dh}); ylim(ax, lims{dv})
    ticks = {0:5:15, -10:5:10, -10:5:10};
    set(ax, 'XTick', ticks{dh}, 'YTick', ticks{dv})
    grid(ax, 'on')
end
lgd = legend(h, {'Eye per frame (with gaze vector)', 'Mean eye position', 'Mean gaze vector', 'Head origin to beak'});
lgd.Layout.Tile = 'south'; % below all views, so they stay the same size
set(tl.Children(isgraphics(tl.Children, 'axes')), 'TickDir', 'out', 'Box', 'off') % fixticks warns on tiled axes
drawnow
end

%% Optional figures (gaze model movie, head/eye example traces):
% scripts/extras/, using H, Eout and Q_raw from this function

%% Save as a template for use with old data:
Ht = table;
vx_template_local = (p_beak_local-p_meaneye_local)/norm(p_beak_local-p_meaneye_local);

% Define a rotation matrix to convert from the local rigid body reference frame to the "head" (beak-eyes) reference frame.
vy_template_local = (p_eye_L_local - p_eye_R_local)/norm(p_eye_L_local-p_eye_R_local);
vy_template_local = vy_template_local - dot(vy_template_local, vx_template_local)*vx_template_local; % Get component of vy that is orthogonal to vx
vy_template_local= vy_template_local/norm(vy_template_local);
vz_template_local = cross(vx_template_local, vy_template_local);
R_template_local = [vx_template_local(:) vy_template_local(:) vz_template_local(:)]; % Defined in rigid body ref frame
% x axis = mean of p_eyes to beak. y axis pointing left, z axis up

v_template_beak = R_template_local'*H.R_head(:,1); % beak vector (from eye-intersect to tip) in this eye-mean ref frame

v_template_L = R_template_local'*H.v_eye_L ;  % left eye vector in this eye-mean reference frame
v_template_R = R_template_local'*H.v_eye_R ;  % right eye vector in this eye-mean reference frame
Ht.p_head =  (R_template_local'*(p_head_local(:)-p_meaneye_local(:)))'; % eye-intersection relative to this eye-mean reference frame

% Set y coordinate to zero because it should be symmetric -- equivalent to
% averaging vectors from both eyes?
Ht.p_head(2)  = 0;

theta_phi = @(v) [atan2d(v(2,:), v(1,:)); acosd(v(3,:)/norm(v))];
theta_phi_L = theta_phi(v_template_L);
theta_phi_R = theta_phi(v_template_R);
theta_phi_beak = theta_phi(v_template_beak);

% Take the average theta and phi of both eyes and beak
theta_eye = (theta_phi_L(1)-theta_phi_R(1))/2;
phi_eye = mean([theta_phi_L(2) theta_phi_R(2)]);

Ht.theta_beak = 0;
Ht.theta_eye = theta_eye;
Ht.phi_beak = theta_phi_beak(2);
Ht.phi_eye = phi_eye;


%% Scatter plot of gaze in polar coords
if plot_on; figure; end
hs  = gobjects(1,2);
nframes= [];
v_eye_local_head = v_eye_local*H.R_head;
angle_offset = NaN(size(mask_eye_R));
delta_theta = NaN(size(mask_eye_R));
delta_phi = NaN(size(mask_eye_R));
for which_eye  = [0 1]
    if which_eye == 1
        mask_eye = mask_eye_R;
        v_eye = H.v_eye_R_head;
    else
        mask_eye = mask_eye_L;
        v_eye = H.v_eye_L_head;
    end
     theta_mean = atan2d(v_eye(2), v_eye(1));
        phi_mean = acosd(v_eye(3));
        
        % Get the overall angular offset from the mean eye vector
    angle_offset(mask_eye) = acosd(dot(v_eye_local_head(mask_eye,:)', repmat(v_eye, 1, nnz(mask_eye))));
    
    % Get local vectors of eye relative to head    
    theta = atan2d(v_eye_local_head(mask_eye,2), v_eye_local_head(mask_eye,1));
    phi = acosd(v_eye_local_head(mask_eye,3));
    nframes(which_eye+1) = nnz(mask_eye);

    delta_theta(mask_eye) = theta-theta_mean;
    delta_phi(mask_eye) = phi-phi_mean;
    if plot_on
        hs(which_eye+1) = subplot(1,2,which_eye+1);
        scatter(theta-theta_mean, phi-phi_mean,9, 'c','MarkerEdgeAlpha',.3)
        axis equal
        a = 30; xlim([-a a]); ylim([-a a])
        grid on
        xlabel('Horizontal (°)')
        ylabel('Vertical (°)')
        eye_names = {'L', 'R'};
        title(sprintf('%s eye in head, relative to its mean (%i frames)', eye_names{which_eye+1}, nnz(mask_eye)))
    end

end
    std_thetas = nanstd(delta_theta);
    std_phis = nanstd(delta_phi);
    
if plot_on
    set(hs,'TickLength',[0 0])
    set(hs,'XTick',-30:10:30,'YTick',-30:10:30)
    set(hs,'XTickLabelRotationMode','manual')
end
median_deviation = median(angle_offset,'omitnan');
fprintf('Std horiz ang. %.2f deg, Std vert ang. %.2f deg \n',std_thetas, std_phis)
fprintf('Median overall deviation%.3f\n', median_deviation)
% fprintf('Std dists %.3f\n', median([dists{1}; dists{2}]))
stats = table;
stats.std_theta = std_thetas;
stats.std_phi = std_phis;
stats.median_overall = median_deviation;
stats.nframes = nframes;
stats.mean_pupil_cc = mean_pupil_cc;

if plot_on
    fixticks
    drawnow
end

Eout = struct;
Eout.mask_eye_R = mask_eye_R;
Eout.mask_eye_L = mask_eye_L;
Eout.v_eye_local_head = v_eye_local_head;
Eout.t_eye = t_eye;
Eout.p_eye_local = p_eye_local;       % per-frame eye position, rigid-body frame (NaN = excluded)
Eout.R_rigidbody_ds = R_rigidbody_ds; % per-frame rigid-body orientation and position, common frame
Eout.p_rigidbody_ds = p_rigidbody_ds;
Eout.v_eye = v_eye_common;              % per-frame eye vector (pupil - cornea), common frame


%% Correlation of anterior eye position with horizontal angle (rigid-body frame)
h_angle_eye_local = atan2d(v_eye_local(:,2), v_eye_local(:,1)); % in deg
h_angle_eye_local = wrap180(90-h_angle_eye_local);
[rhoL, pvalL] = corrcoef(h_angle_eye_local(mask_eye_L), p_eye_local(mask_eye_L,2));
[rhoR, pvalR] = corrcoef(h_angle_eye_local(mask_eye_R), p_eye_local(mask_eye_R,2));
stats.antpos_hang_r = [rhoL(2) rhoR(2)];
stats.antpos_hang_p = [pvalL(2) pvalR(2)];
