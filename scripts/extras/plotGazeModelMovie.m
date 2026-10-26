function plotGazeModelMovie(H, video_file)
% plotGazeModelMovie(H, video_file)
% Paper figure: 3D model of the bird's eyes (spheres with gaze arrows) and
% beak (cone) in the head frame, tilted 25 deg beak-down, rotated 90 deg and
% saved as a movie.
% H          - head geometry from analyzeEyetrack (runEyetrackSingle / runEyetrackAll)
% video_file - movie to write (default 'rotation_movie.avi'; '' = no movie)

if ~exist('video_file', 'var'); video_file = 'rotation_movie.avi'; end
r_eye  = 1.8;  % radius eye
eyecolor = .9*[1 1 1];
gaze_color = [67 127 138]/255;
a = 6; % length eye arrows
cyl_radius = .2; % eye arrow
cone_radius = .4;  % eye arrow
ftilt = @(p) rotateAbout(p, [0 1 0]', 25); % tilt beak down by X degrees

p_head_local = H.p_head(:)';
vx_head_local = H.R_head(:,1)';
b = norm(H.p_beak(:)' - p_head_local); % tip of beak
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
set(gca,'XTickLabel','','YTickLabel','','ZTickLabel','')
box on
view([0, 15]);
axis equal; axis vis3d;
grid on
lighting gouraud; % Apply Gouraud lighting for smooth shading
material([0.6 0.4 0.1 10 .5]); % Adjusted material properties
light('Position', [5 5 5], 'Style', 'infinite'); % Light source from one direction
light('Position', [-5 -5 10], 'Style', 'infinite'); % Another light source for soft reflections
xlim([0 20]-5); ylim([-.5 .5]*20);zlim([0 20]-13)
drawnow
if isempty(video_file); return; end

% Rotate the view 90 deg about z in 180 steps and record each frame
video_obj = VideoWriter(video_file);
video_obj.FrameRate = 30;
open(video_obj);
rotation_steps = 180;
step_angle = 90 / rotation_steps;
for k = 1:rotation_steps
    view([k * step_angle, 15]); % azimuth changes, elevation stays at 15
    drawnow;
    writeVideo(video_obj, getframe(gcf));
end
close(video_obj);
disp(['Movie saved as ', video_file]);
end
