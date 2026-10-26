function [hs, R_head] = plotHeadEyeExample(H, Eout, Q_raw, time_window, yaw_starts)
% [hs, R_head] = plotHeadEyeExample(H, Eout, Q_raw, time_window, yaw_starts)
% Paper figure: horizontal angle over time of the head in the world, the eye
% in the world, and the eye in the head (plotHeadEye).
% H, Eout     - from analyzeEyetrack
% Q_raw       - rigid body as passed to analyzeEyetrack (R_rigidbody, N_head, fps_head)
% time_window - (s) x limits (optional; the paper used [101 103.5] for IND102_220707a)
% yaw_starts  - (deg) bottom of each panel's 36-deg y range (optional; paper: [-166 -118 25])
% R_head      - head axes in the common frame per QTM frame (for plotHeadEyeSpeedHist)

mask_eye = Eout.mask_eye_R | Eout.mask_eye_L; % this mask excludes bad data points
t_head = (0:Q_raw.N_head-1)/Q_raw.fps_head;

% Head axes (eye midpoint to beak, left, up) in common QTM coordinates
R_head = nan(3,3,Q_raw.N_head);
for k = 1:3
    R_head(:,k,:) = localToGlobalVector(Q_raw.R_rigidbody, H.R_head(:,k)');
end

hs = plotHeadEye(t_head, R_head, Eout.t_eye, Eout.v_eye, Eout.v_eye_local_head, mask_eye);
if exist('time_window', 'var') && ~isempty(time_window); xlim(time_window); end
if exist('yaw_starts', 'var') && ~isempty(yaw_starts)
    yrange = 36;
    for k = 1:3; ylim(hs(k), yaw_starts(k) + [0 yrange]); end
end
end
