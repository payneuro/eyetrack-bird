function  A = calibrateAxesBW(filepath_axes, stereo_params, thresh)


%% Get the axes in the QTM reference frame
rprops1 = dir(fullfile(filepath_axes, '*.mat'));
A_head = getfield(load(fullfile(filepath_axes, rprops1.name)),rprops1.name(1:end-4));
p0_head  = mean(A_head.Trajectories.Labeled.Data(strcmp(A_head.Trajectories.Labeled.Labels,'p0'),1:3,:),3);
p1_head  = mean(A_head.Trajectories.Labeled.Data(strcmp(A_head.Trajectories.Labeled.Labels,'px'),1:3,:),3);
p2_head  = mean(A_head.Trajectories.Labeled.Data(strcmp(A_head.Trajectories.Labeled.Labels,'py'),1:3,:),3);

p_head = [p0_head; p1_head; p2_head];

fprintf('QTM AXES: x dist: %.2f mm, y dist %.2f mm\n',sqrt(sum((p1_head-p0_head).^2)), sqrt(sum((p2_head-p0_head).^2)))

vx_head = (p1_head-p0_head)/norm(p1_head-p0_head);
vy_head_temp = (p2_head-p0_head)/norm(p2_head-p0_head);
vz_head = cross(vx_head, vy_head_temp);
vz_head = vz_head/norm(vz_head);
vy_head = -cross(vx_head, vz_head);
vy_head = vy_head/norm(vy_head);
R_head = [vx_head(:) vy_head(:) vz_head(:)];

% Rotate 45 deg around x axis
R_45 = [1 0 0; 0 cosd(315) -sind(315); 0 sind(315) cosd(315)];

%% Dual camera reference frame
temp1 = dir(fullfile(filepath_axes, 'cam1.bmp'));
temp2 = dir(fullfile(filepath_axes, 'cam2.bmp'));

axes_filename_cam1 = fullfile(filepath_axes, temp1.name);
axes_filename_cam2 = fullfile(filepath_axes, temp2.name);

% Saturated markers in each camera (detectAxesMarkers), then matched between
% cameras and named p0, px, py from the triangle's shape (matchAxesMarkers)
[p_eye1, bounds1, n1, I1b] = detectAxesMarkers(imread(axes_filename_cam1), thresh);
[p_eye2, bounds2, n2, I2b] = detectAxesMarkers(imread(axes_filename_cam2), thresh);
if isempty(p_eye1) || isempty(p_eye2)
    error(['Found %i (cam1) and %i (cam2) round saturated markers; need exactly 3 in each. ' ...
        'Retake axes\\cam1.bmp/cam2.bmp with the markers saturated (and nothing else round and saturated).'], n1, n2);
end
[p_eye1, p_eye2] = matchAxesMarkers(p_eye1, p_eye2, stereo_params);

% Plot results for dual cameras
figure('Pos',[  36         558        1204         420]);
subplot(1,2,1);
imagesc(I1b); colormap(gray); axis image; hold on
for ii = 1:3    
   plot(bounds1{ii}(:,2), bounds1{ii}(:,1),'y')
end
title('Axes markers, camera 1 (red = p0, green = px, blue = py)')
scatter(p_eye1(:,1),p_eye1(:,2), 50,[1 0 0; 0 1 0; 0 0 1],'filled')

subplot(1,2,2);
imagesc(I2b); colormap(gray); axis image; hold on
for ii = 1:3    
   plot(bounds2{ii}(:,2), bounds2{ii}(:,1),'y')
end
title('Axes markers, camera 2')
scatter(p_eye2(:,1),p_eye2(:,2), 50,[1 0 0; 0 1 0; 0 0 1],'filled')
drawnow


%% Undistort and triangulate points in dual camera reference frame
[p_eye, reprojection_errors] = triangulate(undistortPoints(p_eye1,stereo_params.CameraParameters1),...
    undistortPoints(p_eye2,stereo_params.CameraParameters2),stereo_params);

% Swap y and z, then invert new z, to specify similar orientation to
% Qualisys - unnecessary
% R_align = [1 0 0; 0 0 -1; 0 1 0];
% p_eye = p_eye*R_align;

p0_eye = p_eye(1,:);
p1_eye = p_eye(2,:);
p2_eye = p_eye(3,:);

fprintf('EYE AXES:  x dist: %.2f mm, y dist %.2f mm\n',sqrt(sum((p1_eye-p0_eye).^2)), sqrt(sum((p2_eye-p0_eye).^2)))

% The cameras and QTM must see the same triangle (past calibrations agree to < 0.3 mm)
legs_eye = [norm(p1_eye - p0_eye), norm(p2_eye - p0_eye)];
legs_qtm = [norm(p1_head - p0_head), norm(p2_head - p0_head)];
if any(abs(legs_eye - legs_qtm) > 2)
    error(['The axes markers found by the cameras (legs %.1f and %.1f mm) don''t match QTM''s triangle ' ...
        '(%.1f and %.1f mm). Check the axes images and the QTM labels p0, px, py.'], legs_eye, legs_qtm);
end

vx_eye = (p1_eye-p0_eye)/norm(p1_eye-p0_eye);
vy_eye_temp = (p2_eye-p0_eye)/norm(p2_eye-p0_eye);
vz_eye = cross(vx_eye, vy_eye_temp);
vz_eye = vz_eye/norm(vz_eye);
vy_eye = -cross(vx_eye, vz_eye);
vy_eye = vy_eye/norm(vy_eye);
R_eye = [vx_eye(:) vy_eye(:) vz_eye(:)];

A = [];
A.R_eye = R_eye;
A.R_head = R_head;
A.R_45 = R_45;
A.p0_eye = p0_eye;
A.p0_head = p0_head;

%% [x y z] Sanity checks of common axis
p_head_local = (p_head - p0_head)*R_head;
p_head_local2 = p_head_local*R_45; % Rotate around x axis by 45 deg to account to keep vertical truly vertical (axes is titled 45 so both camera and QTM can see it)

figure; subplot(2,2,1)
scatter3(p_head_local(:,1), p_head_local(:,2), p_head_local(:,3),50,[1 0 0; 0 1 0; 0 0 1],'filled'); axis equal; axis vis3d
xlabel('x (mm)'); ylabel('y (mm)'); zlabel('z (mm)');
title('QTM axes (red = p0, green = px, blue = py)')

subplot(2,2,2);
scatter3(p_head_local2(:,1), p_head_local2(:,2), p_head_local2(:,3),50,[1 0 0; 0 1 0; 0 0 1],'filled'); axis equal; axis vis3d
xlabel('x (mm)'); ylabel('y (mm)'); zlabel('z (mm)');
title('QTM axes, rotated 45 deg')

p_eye_local = (p_eye - p0_eye)*R_eye;
p_eye_local2 = p_eye_local*R_45; % Rotate around x axis by 45 deg to keep vertical truly vertical (axes is titled 45 so both camera and QTM can see it)

subplot(2,2,3);
scatter3(p_eye_local(:,1), p_eye_local(:,2), p_eye_local(:,3),50,[1 0 0; 0 1 0; 0 0 1],'filled'); axis equal; axis vis3d
xlabel('x (mm)'); ylabel('y (mm)'); zlabel('z (mm)');
title('Eye-camera axes')

subplot(2,2,4);
scatter3(p_eye_local2(:,1), p_eye_local2(:,2), p_eye_local2(:,3),50,[1 0 0; 0 1 0; 0 0 1],'filled'); axis equal; axis vis3d
xlabel('x (mm)'); ylabel('y (mm)'); zlabel('z (mm)');
title('Eye-camera axes, rotated 45 deg')
drawnow


disp('Reprojection errors: ')
disp(reprojection_errors)
