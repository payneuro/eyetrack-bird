function [p, bounds, n_found, I_smooth] = detectAxesMarkers(I, thresh)
% [p, bounds, n_found, I_smooth] = detectAxesMarkers(I, thresh)
% The three saturated markers of the axes triangle in one camera image (used
% by calibrateAxesBW, and by the GUI right after capture). The image is
% smoothed (Gaussian, sigma 5 px) and thresholded at thresh; the three largest
% regions are the markers.
% p        - 3 x 2 marker centers [x y], sorted p0 (corner), px, py; empty if
%            fewer than 3 regions
% bounds   - their outlines, for plotting
% n_found  - number of regions above thresh
% I_smooth - the smoothed image

I = double(I);
if size(I,3) == 3
    I = rgb2gray(I);
end
sigma = 5;
I_smooth = imfilter(I, fspecial('gaussian', [ceil(2.5*sigma) ceil(2.5*sigma)], sigma), 'symmetric');
above = I_smooth > thresh;
regions = regionprops(above, 'Area', 'Centroid');
bounds = bwboundaries(above);
n_found = numel(regions);
p = [];
if n_found < 3
    bounds = {};
    return
end

% Three biggest regions
[~, order] = sort([regions.Area]);
regions = regions(order(end-2:end))';
bounds = bounds(order(end-2:end))';
p = cell2mat({regions.Centroid}');

% Sort into p0, px, py: py is highest in the image, px rightmost, p0 the other
[~, ind_y] = min(p(:,2));
[~, ind_x] = max(p(:,1));
ind_0 = find(~ismember(1:3, [ind_y ind_x]));
p = p([ind_0; ind_x; ind_y], :);
