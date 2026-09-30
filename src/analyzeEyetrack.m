function [H, Ht, stats, Eout] = analyzeEyetrack(Eraw, p_pupil0, p_cornea0, p_beak,  Q_raw, downsample_eye, dist_pc)
% [H, Ht, stats, Eout] = analyzeEyetrack(Eraw, p_pupil0, p_cornea0, p_beak, Q_raw, downsample_eye, dist_pc)
% Clean the eye tracking, then fit each eye's position and gaze direction and
% the beak tip in the head (rigid-body) frame. Inputs are in the common frame
% (alignCommonReferenceFrame).
% H     - head/eye/beak geometry relative to the rigid body
% Ht    - one-row summary table (eye angles relative to the beak)
% stats - spread of eye angles and pupil-cornea distance
% Eout  - per-frame left/right eye masks and eye-in-head vectors

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
plotEye(E)
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

% Smooth then downsample head to match eye
temp = [];
temp.p = p_rigidbody;
temp.R = shiftdim(R_rigidbody,2);
temp = processStruct(temp, @(x) smooth(x, downsample_eye, 'moving'));
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
max_eye_deviation = 1; % (mm)
nstd = 3;
% getMax = @(x) median(x,'omitnan') + max_eye_deviation;
% getMin= @(x) median(x,'omitnan') - max_eye_deviation;

getMax = @(x) mean(x,'omitnan') + nstd*std(x,'omitnan');
getMin= @(x) mean(x,'omitnan') - nstd*std(x,'omitnan');

figure
subplot(2,2,1)
histogram(p_eye_local(:,1), [-inf 0:.1:18 inf]); xlabel('p_eye_local (x coord/lateral pos, mm)','interp','none')
hold on; title('Lateral eye position (cyan = L/R split, red = mean \pm 3 SD cutoffs)'); ylabel('Frame count')
dashedline(divide_RL, ylim,6,'Color','c');
dashedline(getMin(p_eye_local(mask_eye_R,1)), ylim,6,'Color','r');
dashedline(getMax(p_eye_local(mask_eye_R,1)), ylim,6,'Color','r');

dashedline(getMin(p_eye_local(mask_eye_L,1)), ylim,6,'Color','r');
dashedline(getMax(p_eye_local(mask_eye_L,1)), ylim,6,'Color','r');

subplot(2,2,2)
min_p_eye_local2 = getMin(p_eye_local(:,2));
max_p_eye_local2 = getMax(p_eye_local(:,2));
histogram(p_eye_local(:,2), [-inf min_p_eye_local2-4:.1:max_p_eye_local2+4 inf]); xlabel('p_eye_local (y coord/anterior pos, mm)','interp','none')
hold on; title('Anterior eye position (red = cutoffs)'); ylabel('Frame count')
dashedline(min_p_eye_local2, ylim,6,'Color','r');
dashedline(max_p_eye_local2, ylim,6,'Color','r');


subplot(2,2,3)
histogram(p_eye_local(:,3), [-inf -35:.1:-25 inf]); xlabel('p_eye_local (z coord/dorsal pos, mm)','interp','none')
hold on; title('Dorsal eye position (red = cutoffs)'); ylabel('Frame count')
dashedline(getMin(p_eye_local(:,3)), ylim,6,'Color','r');
dashedline(getMax(p_eye_local(:,3)), ylim,6,'Color','r');

subplot(2,2,4)
histogram(v_eye(:,2),-1:.05:0); xlabel('v_eye (y)','interp','none')
hold on; title('Eye vector y component, common frame (red = cutoffs)'); ylabel('Frame count')
dashedline(getMin(v_eye(:,2)), ylim,6,'Color','r');
dashedline(getMax(v_eye(:,2)), ylim,6,'Color','r');
drawnow

% Mask position 
mask_lateral = false(length(p_eye_local),1);
mask_lateral(mask_eye_R) =  p_eye_local(mask_eye_R,1)>getMax(p_eye_local(mask_eye_R,1)) | p_eye_local(mask_eye_R,1)<getMin(p_eye_local(mask_eye_R,1));
mask_lateral(mask_eye_L) =  p_eye_local(mask_eye_L,1)>getMax(p_eye_local(mask_eye_L,1)) | p_eye_local(mask_eye_L,1)<getMin(p_eye_local(mask_eye_L,1));
mask_anterior= p_eye_local(:,2)>getMax(p_eye_local(:,2)) | p_eye_local(:,2)<getMin(p_eye_local(:,2)) ;
mask_dorsal= p_eye_local(:,3)>getMax(p_eye_local(:,3)) | p_eye_local(:,3)<getMin(p_eye_local(:,3)) ;

% Mask angle: check if y axis (towards cameras) is way off
mask_vector = v_eye(:,2)>getMax(v_eye(:,2)) | v_eye(:,2)<getMin(v_eye(:,2)) ;

mask_pos = mask_lateral | mask_anterior | mask_dorsal | mask_vector;
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

%% Plot local eye position in 3d (in rigid body coordinates)
ds = 6; % downsample for plotting

figure;
scatter3(p_eye_local(1:ds:end,1),p_eye_local(1:ds:end,2), p_eye_local(1:ds:end,3),30, 'k.'); hold on;% Plot the raw data points
a = 6;
for ii = 1:ds:N_eye
    if ~isnan(p_eye_local(ii,1))
        plot3(p_eye_local(ii,1) + a*[0 v_eye_local(ii,1)], ...
            p_eye_local(ii,2)+ a*[0 v_eye_local(ii,2)],...
            p_eye_local(ii,3)+ a*[0 v_eye_local(ii,3)],'k','LineWidth',.25);
    end
end

% Plot means
a = 6;
b = norm(p_beak_local-p_head_local);
msize = 60;
scatter3(p_head_local(1), p_head_local(2),p_head_local(3), msize, 'om','Filled')
scatter3(p_eye_R_local(1), p_eye_R_local(2), p_eye_R_local(3), msize, 'oc','Filled')
scatter3(p_eye_L_local(1), p_eye_L_local(2), p_eye_L_local(3), msize, 'oc','Filled')
plot3(p_eye_R_local(1)+[0 v_eye_R_local(1)*a], p_eye_R_local(2)+[0 v_eye_R_local(2)*a], p_eye_R_local(3)+[0 v_eye_R_local(3)*a], '-c','LineWidth',2) % Plot the mean local eye vectors
plot3(p_eye_L_local(1)+[0 v_eye_L_local(1)*a], p_eye_L_local(2)+[0 v_eye_L_local(2)*a], p_eye_L_local(3)+[0 v_eye_L_local(3)*a], '-c','LineWidth',2)

% Plot beak
mask = find(~isnan(p_beak(:,1)));
colormap(jet)
scatter3(p_beak_local_all(mask,1),p_beak_local_all(mask,2), p_beak_local_all(mask,3),10^2,'.k'); hold on; % Plot the raw data points
scatter3(p_beak_local(:,1),p_beak_local(:,2), p_beak_local(:,3),40,'^m'); hold on;
plot3(p_head_local(1)+[0 vx_head_local(1)*b], p_head_local(2)+[0 vx_head_local(2)*b], p_head_local(3)+[0 vx_head_local(3)*b], '-m','LineWidth',2)

axis vis3d;     axis equal
xlabel('x');   ylabel('y'); zlabel('z')
set(gca,'Pos',[0 0 1 1])
view([0 0 1])
view([1 0 0])
grid on
drawnow

%% Plot local eye position in 2d (in head coordinates)
% Get local vectors of eye relative to head
v_eye_local_head = v_eye_local*H.R_head;
p_eye_local_head = (H.R_head'*(p_eye_local - p_head_local)')';
p_eye_R_head = H.R_head'*(H.p_eye_R - p_head_local(:));
p_eye_L_head = H.R_head'*(H.p_eye_L - p_head_local(:));
v_beak_head = H.R_head'*vx_head_local'; % should be [1 0 0]
color_pts = [67 127 138]/255;
a = 6; % length mean eyes
c = 6; % length individ eyes
b = norm(p_beak_local-p_head_local); % length beak
msize = 20;
lw = 1;

% Top view
% %{
figure;
h_top = scatter(p_eye_local_head(1:ds:end,1),p_eye_local_head(1:ds:end,2),20,color_pts,'filled'); hold on;% Plot the raw data points
for ii = 1:ds:N_eye
    if ~isnan(p_eye_local_head(ii,1))
        plot(p_eye_local_head(ii,1) + c*[0 v_eye_local_head(ii,1)],...
            p_eye_local_head(ii,2)+ c*[0 v_eye_local_head(ii,2)],'Color',color_pts,'LineWidth',.25);
    end
end

% Plot eye means
h_top(2) = scatter(p_eye_R_head(1), p_eye_R_head(2),msize, 'oc','Filled');
scatter(p_eye_L_head(1), p_eye_L_head(2),  msize, 'oc','Filled')
h_top(3) = plot(p_eye_R_head(1)+[0 H.v_eye_R_head(1)*a], p_eye_R_head(2)+[0 H.v_eye_R_head(2)*a], '-c','LineWidth',lw); % Plot the mean local eye vectors
plot(p_eye_L_head(1)+[0 H.v_eye_L_head(1)*a], p_eye_L_head(2)+[0 H.v_eye_L_head(2)*a],'-c','LineWidth',lw)

% Plot beak
scatter(0,0, msize, 'ok','Filled')
h_top(4) = plot([0 v_beak_head(1)*b], [0 v_beak_head(2)*b], '-k','LineWidth',lw);

xlabel('x position (mm)');   ylabel('y position (mm)');
title('Eyes in head frame, top view (x toward beak, y toward left eye)')
legend(h_top, {'Eye per frame (with gaze vector)', 'Mean eye position', 'Mean gaze vector', 'Head origin to beak'}, 'Location', 'eastoutside')
set(gca,'Pos',[0.1 0.2 .7 .7])
% shrink
% view(-90, 90) %# Swap the axes
set(gca, 'ydir', 'reverse');
set(gca, 'xdir', 'reverse');
axis equal;
xlim([-2 19]); ylim(11*[-1 1])
set(gca,'XTick',0:5:15,'YTick',-10:5:10)
fixticks
drawnow

%% Side view
figure;
h_side = scatter(p_eye_local_head(1:ds:end,1),p_eye_local_head(1:ds:end,3),20,color_pts,'filled'); hold on;% Plot the raw data points
for ii = 1:ds:N_eye
    if ~isnan(p_eye_local_head(ii,1))
        plot(p_eye_local_head(ii,1) + c*[0 v_eye_local_head(ii,1)],...
            p_eye_local_head(ii,3)+ c*[0 v_eye_local_head(ii,3)],'Color',color_pts,'LineWidth',.25);
    end
end

% Plot eye means
h_side(2) = scatter(p_eye_R_head(1), p_eye_R_head(3),msize, 'oc','Filled');
scatter(p_eye_L_head(1), p_eye_L_head(3),  msize, 'oc','Filled')
h_side(3) = plot(p_eye_R_head(1)+[0 H.v_eye_R_head(1)*a], p_eye_R_head(3)+[0 H.v_eye_R_head(3)*a], '-c','LineWidth',lw); % Plot the mean local eye vectors
plot(p_eye_L_head(1)+[0 H.v_eye_L_head(1)*a], p_eye_L_head(3)+[0 H.v_eye_L_head(3)*a],'-c','LineWidth',lw)

% Plot beak
scatter(0,0, msize, 'ok','Filled')
h_side(4) = plot([0 v_beak_head(1)*b], [0 v_beak_head(3)*b], '-k','LineWidth',lw);

xlabel('x position (mm)');   ylabel('z position (mm)');
title('Eyes in head frame, side view (x toward beak, z up)')
legend(h_side, {'Eye per frame (with gaze vector)', 'Mean eye position', 'Mean gaze vector', 'Head origin to beak'}, 'Location', 'eastoutside')
set(gca,'Pos',[0.1 0.2 .7 .7])
shrink
axis equal;
xlim([-2 19]); ylim(11*[-1 1])
set(gca,'XTick',0:5:15,'YTick',-10:5:10)
fixticks
drawnow
%}

%% Plot 3d animation of bird gaze model & record video
%{
r_eye  = 1.8;  % radius eye
eyecolor = .9*[1 1 1];
gaze_color = [67 127 138]/255;
a = 6; % length eye arrows
cyl_radius = .2; % eye arrow
cone_radius = .4;  % eye arrow
ftilt = @(p) rotateAbout(p, [0 1 0]', 25); % tilt beak down by X degrees

b = norm(p_beak_local-p_head_local); % tip of beak
p_eye_R_head = H.R_head'*(H.p_eye_R - p_head_local(:));
p_eye_L_head = H.R_head'*(H.p_eye_L - p_head_local(:));
v_beak_head = H.R_head'*vx_head_local'; % should be [1 0 0]
p_eye_R_head = ftilt(p_eye_R_head);
p_eye_L_head = ftilt(p_eye_L_head);
v_beak_head = ftilt(v_beak_head);
v_eye_R_head = ftilt(H.v_eye_R_head);
v_eye_L_head = ftilt(H.v_eye_L_head);

% Plot the sphere
figure;
plot3deye(p_eye_R_head, v_eye_R_head, r_eye, 1, eyecolor); hold on;
plot3deye(p_eye_L_head, v_eye_L_head, r_eye, 1, eyecolor); hold on;

% Plot arrows
p1 = p_eye_R_head;
p2 = p_eye_R_head+v_eye_R_head*a;
plot3darrow(p1, p2,cyl_radius, cone_radius, gaze_color)
p1 = p_eye_L_head;
p2 = p_eye_L_head+v_eye_L_head*a;
plot3darrow(p1, p2,cyl_radius, cone_radius, gaze_color)

% Plot beak
lbeak = 8; % mm approx length of chickadee beak
plot3dcone((b-lbeak)*v_beak_head, b*v_beak_head, 1.5, .5*[1 1 1])
% xlabel('x position (mm)');   ylabel('y position (mm)'); zlabel('z position (mm)')
set(gca,'XTickLabel','','YTickLabel','','ZTickLabel','')
box on
axis equal; axis vis3d; 
grid on
lighting gouraud; % Apply Gouraud lighting for smooth shading
material([0.6 0.4 0.1 10 .5]); % Adjusted material properties
% camlight headlight; % Additional soft light in the camera direction
hl(1) = light('Position', [5 5 5], 'Style', 'infinite'); % Light source from one direction
hl(2) = light('Position', [-5 -5 10], 'Style', 'infinite'); % Another light source for soft reflections

xlim([0 20]-5); ylim([-.5 .5]*20);zlim([0 20]-13)
    view([0, 15]); % View azimuth changes, elevation stays at 30



% Setup for video recording
video_filename = 'rotation_movie.avi';  % Name of the output video file
video_obj = VideoWriter(video_filename); % Create a video writer object
video_obj.FrameRate = 30;                % Set frame rate (higher for smoother animation)
open(video_obj);                         % Open the video writer

% Define rotation parameters
rotation_steps = 180;         % Number of steps for 90-degree rotation
total_rotation = 90;         % Total degrees to rotate
step_angle = total_rotation / rotation_steps; % Step size in degrees

% Rotate the view step-by-step and capture each frame
for k = 1:rotation_steps
    % Rotate the view by step_angle around the z-axis
    view([k * step_angle, 15]); % View azimuth changes, elevation stays at 30
    drawnow;  % Update the figure
    
    % Capture the current frame and write it to the video
    frame = getframe(gcf);
    writeVideo(video_obj, frame);
end

% Close the video writer object
close(video_obj);
disp(['Movie saved as ', video_filename]);

% Play the video (optional)
implay(video_filename);
%}

%% Plot example for paper: head in world, eye in world, and eye in head
%{
mask_eye = mask_eye_R | mask_eye_L; % this mask excludes bad data points
% mask_eye = true(size(mask_eye_R));

% Get the head vector (eye midpoint to beak) in common QTM coordinates
R_head = nan(3,3,N_head);
R_head(:,1,:) = localToGlobalVector(R_rigidbody, vx_head_local);
R_head(:,2,:) = localToGlobalVector(R_rigidbody, vy_head_local);
R_head(:,3,:) = localToGlobalVector(R_rigidbody, vz_head_local);

hs = plotHeadEye(t_head, R_head, t_eye, v_eye, v_eye_local_head, mask_eye);


% For example IND102_220707a!
xlim([101 103.5]) 
yrange = 36;
ylim(hs(1), -166 + [0 yrange])
ylim(hs(2), -118 + [0 yrange])
ylim(hs(3), 25 + [0 yrange])
%}

%% Plot histogram of angular speed for head vs. eye in head
%{
mask_eye = mask_eye_R;
R_head_ds = R_head(:,:,ind_downsample);
v_head_ds = squeeze(R_head_ds(:,1,:))';
plotHeadEyeSpeed(t_eye, v_head_ds, v_eye_local_head, mask_eye);

%}

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
figure('Units','Centi','Pos',[14   12   16   8]);
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

    hs(which_eye+1) = subplot(1,2,which_eye+1);
    delta_theta(mask_eye) = theta-theta_mean;
    delta_phi(mask_eye) = phi-phi_mean;
    scatter(theta-theta_mean, phi-phi_mean,9, 'c','MarkerEdgeAlpha',.3)
    axis equal
    a = 30; xlim([-a a]); ylim([-a a])
    grid on
    xlabel('Horizontal (°)')
    ylabel('Vertical (°)')
    eye_names = {'L', 'R'};
    title(sprintf('%s eye in head, relative to its mean (%i frames)', eye_names{which_eye+1}, nnz(mask_eye)))
    
end
    std_thetas = nanstd(delta_theta);
    std_phis = nanstd(delta_phi);
    
set(hs,'TickLength',[0 0])
set(hs,'XTick',-30:10:30,'YTick',-30:10:30)
set(hs,'XTickLabelRotationMode','manual')
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

fixticks
drawnow

Eout = struct;
Eout.mask_eye_R = mask_eye_R;
Eout.mask_eye_L = mask_eye_L;
Eout.v_eye_local_head = v_eye_local_head;
Eout.t_eye = t_eye;


%% Get the stdev of eye angles across both eyes



%% Plot the horizontal angle of the eye in local rigid body reference frame v. anterior position (in rigid body ref frame for now)

figure
h_angle_eye_local = atan2d(v_eye_local(:,2), v_eye_local(:,1)); % in deg
h_angle_eye_local = wrapTo180(90-h_angle_eye_local);
h_angle_eye_local_R = nanmean(h_angle_eye_local(mask_eye_R)); % in deg
h_angle_eye_local_L = nanmean(h_angle_eye_local(mask_eye_L)); % in deg
ylims1 = [-1 1]*.8;
msize = 5;

hs = subplot(1,2,1);
plot(h_angle_eye_local(mask_eye_L),p_eye_local(mask_eye_L,2)-p_eye_L_local(2),'c.','MarkerSize',msize);
xlabel('Horizontal angle (°)')
ylabel('Anterior pos. (mm)')
title('L eye: anterior position vs. horizontal angle (rigid-body frame)')
ylim(ylims1); xlim([-20 20]+h_angle_eye_local_L)
grid on; axis square

hs(2) = subplot(1,2,2);
plot(h_angle_eye_local(mask_eye_R),p_eye_local(mask_eye_R,2)-p_eye_R_local(2), 'c.','MarkerSize',msize);
xlabel('Horizontal angle (°)')
title('R eye: anterior position vs. horizontal angle')
ylim(ylims1); xlim([-20 20]+h_angle_eye_local_R)
grid on; axis square

set(hs,'YTick',-.8:.4:.8)
set(hs,'TickLength',[0 0])
fixticks
drawnow

[rhoL, pvalL] = corrcoef(h_angle_eye_local(mask_eye_L), p_eye_local(mask_eye_L,2));
[rhoR, pvalR] = corrcoef(h_angle_eye_local(mask_eye_R), p_eye_local(mask_eye_R,2));
stats.antpos_hang_r = [rhoL(2) rhoR(2)];
stats.antpos_hang_p = [pvalL(2) pvalR(2)];
