function [p, bounds, n_found, I_smooth] = detectAxesMarkers(I, thresh)
% [p, bounds, n_found, I_smooth] = detectAxesMarkers(I, thresh)
% The three axes-triangle markers in one camera image (used by
% calibrateAxesBW, and by the GUI right after capture). The image is smoothed
% (Gaussian, sigma 5 px) and thresholded at thresh. Markers are the bright
% regions that are round and filled (circularity >= 0.75, solidity >= 0.93,
% area >= 1000 px); shiny highlights elsewhere are irregular and get skipped.
% p        - 3 x 2 marker centers [x y] (name them with matchAxesMarkers);
%            empty unless exactly 3 markers are found
% bounds   - outlines of the markers found, for plotting
% n_found  - number of marker-like regions (should be 3)
% I_smooth - the smoothed image

I = double(I);
if size(I,3) == 3
    I = rgb2gray(I);
end
sigma = 5;
I_smooth = imfilter(I, fspecial('gaussian', [ceil(2.5*sigma) ceil(2.5*sigma)], sigma), 'symmetric');
above = I_smooth > thresh;
regions = regionprops(above, 'Area', 'Centroid', 'Perimeter', 'Solidity');
bounds = bwboundaries(above, 'noholes');

circularity = 4*pi*[regions.Area] ./ [regions.Perimeter].^2;
is_marker = [regions.Area] >= 1000 & [regions.Solidity] >= 0.93 & circularity >= 0.75;
regions = regions(is_marker);
bounds = bounds(is_marker)';
n_found = numel(regions);

p = [];
if n_found == 3
    p = cell2mat({regions.Centroid}');
end
