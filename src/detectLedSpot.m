function [xy, area] = detectLedSpot(I)
% [xy, area] = detectLedSpot(I)
% The LED's reflection in a light-calibration image: the centroid [x y]
% (pixels) of the largest saturated (255) region, and its area in pixels.
% xy is empty if nothing is saturated.

regions = regionprops(I == 255);
if isempty(regions)
    xy = [];
    area = 0;
    return
end
[area, idx] = max([regions.Area]);
xy = regions(idx).Centroid;
