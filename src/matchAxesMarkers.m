function [p1, p2] = matchAxesMarkers(p1, p2, stereo_params)
% [p1, p2] = matchAxesMarkers(p1, p2, stereo_params)
% Match the three axes-triangle markers between cameras and name them, so
% it doesn't matter how the triangle or the cameras are oriented.
% p1, p2 - 3 x 2 marker centers [x y] from detectAxesMarkers, in any order
% Returns both reordered as [p0; px; py], where (as in QTM) p0 is the
% right-angle corner, px the end of the longer leg, py the end of the shorter.

% Pair cam2's markers with cam1's: the pairing that triangulates best
pairings = perms(1:3);
err = zeros(size(pairings, 1), 1);
u1 = undistortPoints(p1, stereo_params.CameraParameters1);
for k = 1:size(pairings, 1)
    u2 = undistortPoints(p2(pairings(k,:), :), stereo_params.CameraParameters2);
    [~, reproj] = triangulate(u1, u2, stereo_params);
    err(k) = mean(reproj);
end
[~, best] = min(err);
p2 = p2(pairings(best,:), :);

% Name them from the triangle's 3D shape
P = triangulate(u1, undistortPoints(p2, stereo_params.CameraParameters2), stereo_params);
opposite = [norm(P(2,:) - P(3,:)), norm(P(1,:) - P(3,:)), norm(P(1,:) - P(2,:))]; % side opposite each vertex
[~, i0] = max(opposite);            % p0 faces the hypotenuse
others = setdiff(1:3, i0);
leg = [norm(P(others(1),:) - P(i0,:)), norm(P(others(2),:) - P(i0,:))];
[~, order] = sort(leg, 'descend');  % longer leg ends at px
order = [i0, others(order)];
p1 = p1(order, :);
p2 = p2(order, :);
