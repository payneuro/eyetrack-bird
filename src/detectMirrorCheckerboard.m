function [u, mask] = detectMirrorCheckerboard(I)
% [u, mask] = detectMirrorCheckerboard(I)
% Checkerboard corners on the mirror in a light-calibration image (used by
% calibrateLights, and by the GUI right after capture). Partial boards are
% allowed: u is N x 2 pixels in a standard order, with NaN rows for corners
% not found; mask marks the found ones. u is empty if no board was found.

I = localcontrast(I);
MinCornerMetric = 0.15; % default 0.15, decrease e.g. 0.12 to get more corner detections
[u, board_size] = detectCheckerboardPoints(I, 'PartialDetections', true, 'MinCornerMetric', MinCornerMetric);
if isempty(u) || isempty(board_size)
    u = zeros(0, 2);
    mask = false(0, 1);
    return
end

% Reshape x and y
ux = reshape(u(:,1), board_size-1);
uy = reshape(u(:,2), board_size-1);

% Standardize the orientation
if nanmean(u(1:(board_size(1)-1):end,2)) > nanmean(u(board_size(1)-1:(board_size(1)-1):end,2))
    ux = flipud(ux);
    uy = flipud(uy);
end
if nanmean(u(1:(board_size(1)-1),1)) > nanmean(u(end-board_size(1)+2:end,1))
    ux = fliplr(ux);
    uy = fliplr(uy);
end

u = [ux(:) uy(:)];
mask = ~isnan(u(:,1));
