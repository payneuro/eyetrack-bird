function off = fitCameraOffset(Eout, up, allow_vertical)
% off = fitCameraOffset(Eout, up, allow_vertical)
% Fit one rigid correction of the eye-camera points in the common frame,
%   p -> p + t + yaw * (up x (p - c))   (rotation about vertical only),
% that makes each eye's position in the rigid-body frame as constant as
% possible across frames (linear least squares, each eye's mean position
% free). Use when the eye cameras may have shifted relative to QTM after
% the axes calibration (see plotYawCheck). Called by
% runEyetrackSingle(session_folder, [], [], true).
% Eout - from analyzeEyetrack (per-frame eye positions and head poses)
% up   - 1 x 3 vertical (QTM z) in the common frame
% allow_vertical - false (default): the shift t is horizontal only, since the
%                  cameras sit on the floor; true: t may have a vertical part
% off.t (mm), off.yaw_deg, off.center (rotation center: middle of the eye
% points, mm), off.apply = @(p) corrected N x 3 points (small-angle rotation; exact to ~0.1 mm for a few degrees)

if ~exist('allow_vertical', 'var') || isempty(allow_vertical); allow_vertical = false; end
R = Eout.R_rigidbody_ds; r = Eout.p_rigidbody_ds; pl = Eout.p_eye_local;
eyes = {Eout.mask_eye_L & ~isnan(pl(:,1)), Eout.mask_eye_R & ~isnan(pl(:,1))};
pw = NaN(size(pl)); % eye positions in the common frame
for j = find(eyes{1} | eyes{2})'
    pw(j,:) = (squeeze(R(j,:,:)) * pl(j,:)')' + r(j,:);
end
c = mean(pw(eyes{1} | eyes{2}, :), 1);
up = up(:)' / norm(up);
if allow_vertical
    T = eye(3);           % shift = T * s, s free (3)
else
    T = null(up);         % two horizontal directions
end
ns = size(T, 2);

% Frame j of eye e:  R_j'(p_j - r_j) + R_j' T s + R_j' (yaw * up x (p_j - c)) = m_e
% unknowns [s (ns); yaw (1); m_L (3); m_R (3)]
n = nnz(eyes{1}) + nnz(eyes{2});
A = zeros(3*n, ns + 7); y = zeros(3*n, 1);
row = 0;
for e = 1:2
    for j = find(eyes{e})'
        Rj = squeeze(R(j,:,:));
        rows = row + (1:3);
        A(rows, 1:ns) = Rj' * T;
        A(rows, ns + 1) = Rj' * cross(up, pw(j,:) - c)';
        A(rows, ns + 1 + (e-1)*3 + (1:3)) = -eye(3);
        y(rows) = -pl(j,:)';
        row = row + 3;
    end
end
x = A \ y;
t = (T * x(1:ns))'; w = x(ns + 1) * up;
off = struct('t', t, 'yaw_deg', rad2deg(x(ns + 1)), 'center', c, 'allow_vertical', allow_vertical, ...
    'apply', @(p) p + t + cross(repmat(w, size(p, 1), 1), p - c, 2));
end
