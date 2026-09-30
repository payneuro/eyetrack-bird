function groundtruth


%% Eye groundtruth
% Equipment: Physik motors M660.45 motor with  C-867 controller
% 3d printed ear bar holder
% Dual camera setup
%
% Steps:
% Calibrate QTM (use triangular basis in back-left corner)
% Calibrate cameras using Eye track protocol in onenote
% Set up cameras & test recordingin (QTM + cameras + motor sweep 1 deg
% increments for 500 ms steps)
% Aenesthetize bird with iso & inject lethal K+X
% put in ear bars @ surgery suite
% Bring saline, eye swabs, dissection tools to behavior room
% Place bird in front of cameras and align to cameras, fix in place,
% include rigid body IR markers, set up motor 1D sweep parameters (500 ms
% stationary periods, 1 deg increments)
% After death, dissect skin away from eye, being careful not to get any
% feathers in the eye
% Immediately record - start qtm but wait for space bar, start both
% cameras, hit space bar to start qtm and start motor sweep. 



% datadir  = 'Z:\Hannah\eyetrack\groundtruth\eyeL_250307'; % *** USE
% datadir  = 'Z:\Hannah\eyetrack\groundtruth\eyeRpre_250307';
datadir  = 'Z:\Hannah\eyetrack\groundtruth\eyeR_250307'; % *** USE
datadir_camera = 'Z:\Hannah\eyetrack\calibration\250307';
downsample_eye = 8;
% ROS91: male


filename = 'qtm';
[~, session] = fileparts(datadir); % for figure titles
addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'src'))

%% Motor + qtm alignment in time and space
fprintf('[%s] Loading motor and QTM data\n', datestr(now,'HH:MM:SS'));
motor_pos = [];
csv_files = dir(fullfile(datadir, '*.csv'));
[~, idx] = sort(str2double(regexp({csv_files.name}, '\d+', 'match', 'once')));
file_names = {csv_files(idx).name};

for ii = 1:length(file_names)
    T = readtable(fullfile(datadir,file_names{ii}));
    motor_pos = [motor_pos; T{:,2}];
end

% remove duplicates
duplicates = find(abs(diff(motor_pos))<.1)+1;
motor_pos(duplicates) = [];

motor_pos = -motor_pos;
if contains(datadir,'250303')
elseif contains(datadir,'eyeL_250307')
motor_pos(21) = []; 
elseif contains(datadir,'eyeR_250307')
% motor_pos(end-1:end) = [];
end
motor_pos = motor_pos - min(motor_pos)-range(motor_pos)/2;

Q = getfield(load(fullfile(datadir, [filename '.mat'])),filename);
fps = Q.FrameRate;
nt = Q.Frames;
t_head = (0:nt-1)/fps;
p_rigidbody = squeeze(Q.RigidBodies(1).Positions(1,:,:))';
R_rigidbody = squeeze(Q.RigidBodies(1).Rotations(1,:,:));
R_rigidbody = reshape(R_rigidbody, [3,3,nt]); % [X Y Z]
% R = flip(R,3); % Flip because motor moves clockwise
yaw = real(squeeze(atan2(R_rigidbody(2,1,:), R_rigidbody(1,1,:))));
yawd = rad2deg(yaw); % Convert to degrees;

% Find edges in QTM  data
win_size = .25;
var_thresh = 0.01;
istart = find_stationary_periods(yawd, fps, win_size, var_thresh);

if contains(datadir,'250303')
istart([1 8 39 43 46 60]) = [];
elseif contains(datadir,'eyeL_250307')
istart([21 22 24 27 155 156]) = [];
elseif contains(datadir,'eyeR_250307')
istart(end-2:end) = [];
end
nt_measure = 0.333; % (s) time to measure for each "fixation"
ni_measure = round(nt_measure*fps);
if any(diff(istart)<ni_measure); error; end
if istart(1)==1; istart(1) = 2; end
istop = istart+ni_measure;
mask = false(size(yawd));
yaw_actual = NaN(size(yawd));
qtm_mean_pos = NaN(length(istart),1);
for ii = 1:min(length(istart), length(motor_pos))
    curr_mask = istart(ii):istop(ii);
    mask(curr_mask) = true;
    yaw_actual(curr_mask) = motor_pos(ii);
    qtm_mean_pos(ii) = mean(yawd(curr_mask));
end

err_temp = yawd(mask) - yaw_actual(mask);
qtm_offset = rad2deg(circ_mean(deg2rad(err_temp)));
yawd_center = wrapTo180(yawd - qtm_offset);
qtm_mean_pos = wrapTo180(qtm_mean_pos - qtm_offset);
err = yawd_center(mask) - yaw_actual(mask);

% Plot actual vs. measured
figure;
plot(motor_pos,'.k'); hold on
plot(qtm_mean_pos,'+r')
xlabel('Fixation #'); ylabel('Angle (deg)')
legend({'Motor command', 'QTM mean per fixation'})
title([session ': motor vs. QTM angle per fixation'], 'Interpreter', 'none')

figure; 
lims = [-25 25];
plot(lims, lims,'k-'); hold on
plot(yaw_actual(mask),yawd_center(mask), '.r','Clipping','off'); hold on
xlim(lims); ylim(lims); axis square
set(gca,'XTick',-180:10:180, 'YTick',-180:10:180)
xlabel('Actual (deg)'); ylabel('Measured (deg)')
fixticks
title([session ': head measurement (QTM) vs. motor'], 'Interpreter', 'none')

% Plot residuals
figure;
histogram(err, -0.2:.01:.2,'EdgeColor','none','FaceColor',.5*[1 1 1])
rmse = sqrt(mean(err.^2));
xlabel('QTM - motor (deg)'); ylabel('Frame count')
title(sprintf('%s: QTM head tracking error, RMSE = %.3f deg', session, rmse), 'Interpreter', 'none')
drawnow



%% Motor + eye comparison

% Process eye camera calibration
fprintf('[%s] Loading camera calibration\n', datestr(now,'HH:MM:SS'));
[C,A] = calibrateCameras(datadir_camera);

% Run eye tracking (or just load if already run)
fps_eye = fps/downsample_eye;
resume_beak = 0;
run_beak = 0;
resume_eye = 1;
camfilename = 'cam%i*.avi'; % Filename template for eye cameras
fprintf('[%s] Loading/triangulating eye tracking\n', datestr(now,'HH:MM:SS'));
[Eraw, p_pupil_cam, p_cornea_cam] = processEyetrack(datadir, camfilename,  C, resume_beak, run_beak, resume_eye);
N_eye = size(Eraw.pupil1,1);
t_eye = (0:N_eye-1)'/fps_eye;
Eraw.t = t_eye;
fprintf('[%s] Cleaning eye data\n', datestr(now,'HH:MM:SS'));
[E, nanmask] = cleanEye(Eraw);
plotEye(E)
drawnow
p_pupil_cam(nanmask,:) = NaN;
p_cornea_cam(nanmask,:) = NaN;

% Correct pupil length and exclude outliers, as in experiments
[p_pupil_correct, p_cornea_correct, dist_pc] = correctLengthP_CR(p_pupil_cam, p_cornea_cam);
thresh_dist_p_c = 0.1; % Fraction away from median distance to exclude
K = median(dist_pc,'omitnan'); % (mm)
mask_dist_pc = (abs(dist_pc - K)/K)> thresh_dist_p_c;
p_pupil_correct(mask_dist_pc,:) = NaN;
p_cornea_correct(mask_dist_pc,:) = NaN;
fprintf('Mean pupil-ccc distance: %.2f mm. Fraction mask_dist_p_c %.3f\n', nanmean(dist_pc(~mask_dist_pc)), mean(mask_dist_pc))


% Convert pupil and corneal reflection coordinates to common world reference frame
[p_pupil_common, p_cornea_common, p_beak_common, p_rigidbody_common, R_rigidbody_common]...
    = alignCommonReferenceFrame(A, p_pupil_correct, p_cornea_correct, [], p_rigidbody, R_rigidbody);
% [p_pupil_common, p_cornea_common, p_beak_common, p_rigidbody_common, R_rigidbody_common]...
%     = alignCommonReferenceFrame(A, p_pupil_cam, p_cornea_cam, [], p_rigidbody, R_rigidbody);

% Get a unit vector pointing in the direction of the eye
v_eye = (p_pupil_common-p_cornea_common)./sqrt(sum((p_pupil_common-p_cornea_common).^2, 2));

% Get the horizontal angle (relative to the world/motor)
yaw_eye = rad2deg(real(squeeze(atan2(v_eye(:,2), v_eye(:,1)))));
pitch_eye = rad2deg(atan2(v_eye(:,3), sqrt(v_eye(:,1).^2 + v_eye(:,2).^2)));


% Downsample motor data to compare eye and motor angles
fprintf('[%s] Comparing eye and motor angles\n', datestr(now,'HH:MM:SS'));
yaw_motor_resamp = interp1(t_head, yaw_actual, t_eye);
mask_resamp = interp1(t_head, double(mask), t_eye)>.5;



% Infer the motor angle at which the eye is centered between the two cameras -
% pupil 1 is midway between cr1a&b, pupil2 is midway between cra&b
pupil1x = E.pupil1(:,1);
cr1ax = E.cr1(:,1,1);
cr1bx = E.cr1(:,1,2);
pupil2x = E.pupil2(:,1);
cr2ax = E.cr2(:,1,1);
cr2bx = E.cr2(:,1,2);
pupil_norm1 = (pupil1x - cr1ax)./(cr1bx-cr1ax); % centered on camera 1 when = 0.5
pupil_norm2 = (pupil2x - cr2ax)./(cr2bx-cr2ax); % centered on camera 1 when = 0.5
pupil_norm_mean = mean([pupil_norm1 pupil_norm2],2);
pupil_norm_mean(mask_dist_pc) = NaN;
figure;
subplot(2,2,[1 2]);
plot([pupil_norm1 pupil_norm2 pupil_norm_mean],'.');
legend({'cam1', 'cam2', 'mean'})
xlabel('Eye frame #'); ylabel('Pupil x between CRs (0-1)')
title([session ': pupil position between the two CRs (0.5 = midway), used to define 0 deg'], 'Interpreter', 'none')

subplot(2,2,3);
plot(yaw_motor_resamp, pupil_norm_mean,'.'); hold on; plot(xlim, .5*[1 1],'k--');
b_motor = robustfit(yaw_motor_resamp, pupil_norm_mean);
plot(xlim, xlim*b_motor(2)+b_motor(1),'--r')
motor05 = (0.5-b_motor(1))/b_motor(2);
title(sprintf('vs. motor angle: 0.5 at %.1f deg', motor05)); xlabel('Motor (deg)'); ylabel('Pupil x between CRs (0-1)')

subplot(2,2,4); plot(yaw_eye, pupil_norm_mean,'.'); hold on; plot(xlim, .5*[1 1],'k--');
b_eye = robustfit(yaw_eye, pupil_norm_mean);
plot(xlim, xlim*b_eye(2)+b_eye(1),'--r')
eye05 = (0.5-b_eye(1))/b_eye(2);
title(sprintf('vs. eye angle: 0.5 at %.1f deg', eye05)); xlabel('Eye, common frame (deg)'); ylabel('Pupil x between CRs (0-1)')

yaw_motor_center = yaw_motor_resamp - motor05;
yaw_eye_center = yaw_eye-eye05;
motor_mean_center = motor_pos - motor05;

figure; plot(t_eye(mask_resamp), yaw_motor_center(mask_resamp),'k.');
hold on; plot(t_eye(mask_resamp), yaw_eye_center(mask_resamp),'r.');
xlabel('Time (s)'); ylabel('Horizontal angle (deg)')
legend('Motor','Eye tracking')
title([session ': horizontal angle during fixations, centered'], 'Interpreter', 'none')


err_eye = yaw_eye_center(mask_resamp) - yaw_motor_center(mask_resamp);
% outliers = isoutlier(err_temp,"mean");
% err_temp(outliers) = [];
% mean_err = mean(err_temp,'omitnan');
% err_eye = err_temp - mean_err;

% Get mean across saccade
istart_eye = find(diff(mask_resamp)>0)+1;
istop_eye = find(diff(mask_resamp)<0)+1;
eye_mean_center = NaN(length(istart_eye),1);
for ii = 1:length(istart_eye)
    curr_mask = istart_eye(ii):istop_eye(ii);
    num_valid = nnz(~isnan(yaw_eye_center(curr_mask)));
    if num_valid >= 5
    eye_mean_center(ii) = mean(yaw_eye_center(curr_mask),'omitnan');
    end
end
err_eye_mean = eye_mean_center  - motor_mean_center;
drawnow





% Single eye: color all points the same (the combined block below overrides this)
mask_eye = zeros(size(yaw_eye_center));
mask_eye_mean = zeros(size(err_eye_mean));

%%  UNCOMMENT TO LOAD PREVIOUS RESULTS AND PLOT COMBINED
% a = load('Z:\Hannah\eyetrack\groundtruth\eyeL_250307\results.mat');
% b = load('Z:\Hannah\eyetrack\groundtruth\eyeR_250307\results.mat');
% yaw_motor_center = [a.yaw_motor_center; b.yaw_motor_center];
% yaw_eye_center = [a.yaw_eye_center; b.yaw_eye_center];
% motor_mean_center = [a.motor_mean_center; b.motor_mean_center];
% eye_mean_center = [a.eye_mean_center; b.eye_mean_center];
% err_eye = [a.err_eye; b.err_eye];
% err_eye_mean = [a.err_eye_mean; b.err_eye_mean];
% mask_resamp = [a.mask_resamp; b.mask_resamp];
% mask_eye = [zeros(size(a.yaw_eye_center)); ones(size(b.yaw_eye_center))];
% mask_eye_mean = [zeros(size(a.err_eye_mean)); ones(size(b.err_eye_mean))];
% % END UNCOMMENT


mask_range = abs(yaw_motor_center)<30;
mask_range_mean = abs(motor_mean_center)<30;
err_eye_plot = err_eye(mask_range(mask_resamp)); % Restrict to +- 25 deg
err_eye_mean_plot = err_eye_mean(mask_range_mean);

figure;
subplot(1,2,1)
lims = [-30 35];
plot(lims, lims, '--k'); hold on
plot(lims, [0 0],'-k')
plot([0 0], lims,'-k')
scatter(yaw_motor_center(mask_resamp&mask_range), yaw_eye_center(mask_resamp&mask_range),5, mask_eye(mask_resamp&mask_range),'filled'); 
colormap cool
axis equal
xlim(lims); 
ylim([-30 35]);
xlabel('Motor (deg)')
ylabel('Eye tracking (deg)')
title([session ': by data point'], 'Interpreter', 'none')
fprintf('cyan = left eye, magenta = right eye\n+ angle = CCW rotation of bird relative to stationary camera\n')

ax_mean = subplot(1,2,2); cla
plot(lims, lims, '--k'); hold on
plot(lims, [0 0],'-k')
plot([0 0], lims,'-k')
scatter(motor_mean_center(mask_range_mean), eye_mean_center(mask_range_mean),5, mask_eye_mean(mask_range_mean),'filled'); 
axis equal
% axis square
xlim(lims); 
ylim(lims);
% set(gca,'XTick',-20:10:20,'YTick',-20:10:20)
xlabel('Motor (deg)')
ylabel('Eye tracking (deg)')
fixticks


figure; 
bins = -20:.5:20;
subplot(1,2,1)
histogram(err_eye_plot, bins,'EdgeColor','none','FaceColor',.5*[1 1 1]); hold on
% histogram(err_eye(mask_range(mask_resamp&~mask_eye)), bins,'EdgeColor','none','FaceColor','c'); hold on
% histogram(err_eye(mask_range(mask_resamp&mask_eye)), bins,'EdgeColor','none','FaceColor','m'); hold on
xlabel('Error (deg)'); ylabel('Frame count')
xlim([-10 10])
rmse = std(err_eye_plot,'omitnan');
title(sprintf('%s: eye error - frames, within +-30 deg (SD %.2f deg)', session, rmse), 'Interpreter', 'none')
fprintf('RMSE of eye tracking, frames = %.3f deg\n', rmse)
subplot(1,2,2)
histogram(err_eye_mean_plot, bins,'EdgeColor','none','FaceColor',.5*[1 1 1])
xlabel('Error (deg)'); ylabel('Fixation count')
xlim([-10 10])
rmse = std(err_eye_mean_plot,'omitnan');
title(sprintf('Eye error - fixations (SD %.2f deg)', rmse))
fprintf('RMSE of eye tracking, fixations = %.3f deg\n', rmse)
fixticks


% Get slope of correlation
nanmask = ~isnan(eye_mean_center)& mask_range_mean;
slope = motor_mean_center(nanmask)\(eye_mean_center(nanmask))
title(ax_mean, sprintf('Mean within fixations (slope %.3f)', slope))
drawnow

%% Save results
fprintf('[%s] Saving %s\n', datestr(now,'HH:MM:SS'), fullfile(datadir,'results.mat'));
save(fullfile(datadir,'results.mat'), 'yaw_motor_center','yaw_eye_center','motor_mean_center','eye_mean_center','err_eye','err_eye_mean', 'mask_resamp')


%% Compare to ellipse angle method
% Not fully worked out

x = E.pupil1(:,1);  % X position in image plane
y = E.pupil1(:,2);  % Y position in image plane
a = E.pupil1(:,3);  % X radius 
b = E.pupil1(:,4);  % b
long_axis   = 2 * max(a,b);
short_axis  = 2 * min(a,b);
phi = E.pupil1(:,5);  % Rotation angle in image plane

mask_a_major = a>b;
phi(mask_a_major) = -phi(mask_a_major);
alpha = acos(short_axis ./ long_axis);  % Angle of inclination from the camera
v_eye_ellipse1 = ([cos(phi) .* sin(alpha), sin(phi) .* sin(alpha), cos(alpha)]);

% Rx = [1  0  0;
%       0  0 -1;
%       0  1  0];
%   v_eye_ellipse1 = (Rx*v_eye_ellipse1')';
%   v_eye_ellipse1 = v_eye_ellipse1*A.R_eye*A.R_45;
yaw_eye_ellipse = rad2deg(real(squeeze(atan2(v_eye_ellipse1(:,2), v_eye_ellipse1(:,3)))));
% yaw_eye = rad2deg(real(squeeze(atan2(v_eye(:,2), v_eye(:,1)))));

figure; plot([yaw_eye_center yaw_eye_ellipse] ,'.')
xlabel('Eye frame #'); ylabel('Horizontal angle (deg)')
legend({'Dual-camera (centered)', 'Pupil ellipse, cam1'})
title([session ': dual-camera vs. single-camera ellipse angle (not worked out)'], 'Interpreter', 'none')

%% Load head ground truth data
fprintf('[%s] Head ground truth\n', datestr(now,'HH:MM:SS'));
datadir  = 'Z:\Hannah\eyetrack\groundtruth\head';
filename = 'qtm360_1_500ms';
filename_motor = 'scan_1.csv';

T = readtable(fullfile(datadir,filename_motor));
motor_pos = T{:,2};

Q = getfield(load(fullfile(datadir, [filename '.mat'])),filename);
fps = Q.FrameRate;
nt = sum(Q.Frames); % Sum for stiched files
R = squeeze(Q.RigidBodies(1).Rotations(1,:,:));
R = reshape(R, [3,3,nt]); % [X Y Z]
R = flip(R,3); % Flip because motor moves clockwise

% x axis = first column
% y axis = second column
% z axis = third column
% Yaw: rotate around original z axis
% Pitch: rotation around new y axis (up = positive)
% Roll: rotate around new x axis
yaw = real(squeeze(atan2(R(2,1,:), R(1,1,:))));
pitch = real(squeeze(asin(R(3,1,:))));
roll = real(squeeze(atan2(R(3,2,:), R(3,3,:))));
yaw = unwrap(yaw);
yawd = rad2deg(yaw); % Convert to degrees;

% Find edges
win_size= .25;
var_thresh = 0.01;
[istart, istop] = find_stationary_periods(yawd, fps, win_size, var_thresh);
nt_measure = 0.333; % (s) time to measure for each "fixation"
ni_measure = round(nt_measure*fps);
istop = istart+ni_measure;

% Get a mask and actual angles
d_actual = mean(diff(motor_pos)); % (deg) actual movement of motor
mask = false(size(yawd));
yaw_actual = NaN(size(yawd));
qtm_mean_pos = NaN(length(istart),1);
for ii = 1:10:length(istart) % Change interval here
    curr_mask = istart(ii):istop(ii);
    mask(curr_mask) = true;
    yaw_actual(curr_mask) = d_actual*(ii-1);
    qtm_mean_pos(ii) = mean(yawd(curr_mask));
end
err_temp = yawd(mask) - yaw_actual(mask);
yawd_center = yawd - mean(err_temp);
qtm_mean_pos = qtm_mean_pos - mean(err_temp);
err = yawd_center(mask) - yaw_actual(mask);

% Plot change detection
figure; plot(wrapTo180(yawd),'k.-'); hold on
plot(istart, ones(size(istart)),'+g')
plot(istop, ones(size(istop)),'+r')
plot(mask*100,'b')
xlabel('QTM frame #'); ylabel('Yaw (deg)')
legend({'QTM yaw', 'Stationary start', 'Stationary stop', 'Measurement mask (x100)'})
title(['Head ground truth (' filename '): detected stationary periods'], 'Interpreter', 'none')

% Plot actual vs. measured
figure; 
lims = [0 360];
plot(lims, lims,'k-'); hold on
% plot(yaw_actual(mask),yawd_center(mask), '.r','Clipping','off'); hold on
plot(motor_pos, qtm_mean_pos, '.r','Clipping','off'); hold on
xlim(lims); ylim(lims); axis square
set(gca,'XTick',0:60:360, 'YTick',0:60:360)
xlabel('Actual (deg)'); ylabel('Measured (deg)')
fixticks
title(['Head ground truth (' filename '): QTM vs. motor, 360 deg'], 'Interpreter', 'none')

% Plot residuals
figure;
histogram(err - mean(err), -0.2:.01:.2,'EdgeColor','none','FaceColor',.5*[1 1 1])
rmse = sqrt(mean(err.^2));
xlabel('QTM - motor, mean removed (deg)'); ylabel('Frame count')
title(sprintf('Head ground truth (%s): QTM error, RMSE = %.3f deg', filename, rmse), 'Interpreter', 'none')
fprintf('RMSE of QTM head tracking technique = %.3f deg\n', rmse)
drawnow











end

function [istart, istop] = find_stationary_periods(yawd, fps, win_size, var_thresh)
    % FIND_STATIONARY_PERIODS detects start and stop indices of stationary periods
    % based on a moving variance method.
    % 
    % Inputs:
    %   yawd - vector of motor position measurements
    %   fps - sampling rate in frames per second (default: 300)
    %   win_size - window size in seconds for variance calculation (default: 1s)
    %   var_thresh - threshold for variance to determine stationarity (default: auto)
    % 
    % Outputs:
    %   istart - indices of stationary period starts
    %   istop - indices of stationary period stops
    
    if nargin < 2, fps = 300; end
    if nargin < 3, win_size = 1; end % 1-second window
    if nargin < 4, var_thresh = []; end % Auto threshold if not provided

    % Convert window size to frames
    win_frames = round(win_size * fps);

    % Compute moving variance of yawd
    yawd_unwrap = rad2deg(unwrap(deg2rad(yawd)));
    mov_var = movvar(yawd_unwrap, win_frames);

    % Set automatic variance threshold if not provided
    if isempty(var_thresh)
        var_thresh = median(mov_var) * 100; % Adaptive thresholding
        figure; plot(mov_var,'.-');
        hold on; plot(diff(yawd_unwrap))
        plot(xlim, var_thresh*[1 1],'--r')
        xlabel('QTM frame #'); ylabel('deg^2 (variance) or deg (change)')
        legend({'Moving variance of yaw', 'Frame-to-frame yaw change', 'Stationary threshold'})
        title('Stationary-period detection (automatic threshold)')
    end

    % Identify stationary periods (variance below threshold)
    is_stationary = mov_var < var_thresh;

    % Find transitions
    transitions = diff([0; is_stationary; 0]);
    istart = find(transitions == 1);
    istop = find(transitions == -1) - 1;

    % Handle edge cases
    if istart(1) > istop(1)
        istop(1) = []; % Remove invalid first stop
    end
    if length(istart) > length(istop)
        istart(end) = []; % Remove unmatched start if necessary
    end
end