% DETECTPUPILCR detects pupil and corneal reflection in the eye image
% Starburst Algorithm
%
% This source code is part of the starburst algorithm.
% Starburst algorithm is free; you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation; either version 2 of the License, or
% (at your option) any later version.
%
% Starburst algorithm is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with cvEyeTracker; if not, write to the Free Software
% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
%
% Starburst Algorithm - Version 1.0.0
% Part of the openEyes ToolKit -- http://hcvl.hci.iastate.edu/openEyes
% Release Date:
% Authors : Dongheng Li <donghengli@gmail.com>
%           Derrick Parkhurst <derrick.parkhurst@hcvl.hci.iastate.edu>
% Copyright (c) 2005
% All Rights Reserved.
%
% Modified  by Hannah Payne 
%
% Input:
% img             = input image
% edge_thresh     = starting edge_thresh used for pupil
% p.smoothSigma = 1;            % (pixels) smooth image

% p.pupilStart    = start point for starburst algorithm for pupil
% p.radiiPupil    = guess of pupil radius
% p.edgeThresh    = threshold for detecting pupil
%
% p.radiiCR       = guess of CR radius
% p.CRthresh      = threshold for CR
% p.CRfilter      = filter size for CR
%
%     p.CR_box_width = 200;         % (pixels) Crop image for faster CR search
%     p.pupil_downsamp = 2;    % (pixels) factor to downsample for initial pupil search
%     p.pupil_alpha = 2;            % Sensitivity to radial symmetry. 1 - slack, 3 - strict, ... and you can go higher
%     p.minfeatures = .9;           % (fraction, [0 1]) min features required for starburst pupil detection
%     p.ellipse_residual_thresh = 1.3; % Max mean residual to accept for final ellipse fit
%     p.max_radialSymTransform = -100; % If pupil guesses are bad, move higher to skip more frames
%     p.nCRs = 2;
%     p.edge_thresh0 = 128;       % Initial guess, increase if pupil fit is too small, decrease to run faster
%     p.max_bad_frames = 1;
%     p.min_edge_thresh = 4;
%     p.rerun = 1;                % Restart from the first frame
%     p.plot_on = 1;
%     p.debug_on = 0;
%     
% Output:
% pupil_ellipse = 5-vector of the ellipse parameters of pupil
%   [cx cy  a b theta]
%   cx - the x coordinate of ellipse center
%   cy - the y coordinate of ellipse center
%   a - the ellipse axis of x direction
%   b - the ellipse axis of y direction
%   theta - the orientation of ellipse
% CRout = 3-vector of the circle parameters of the corneal reflection
%   [crx cry crr]
%   crx - the x coordinate of circle center
%   cry - the y coordinate of circle center
%   crr - the radius of circle
% edge_thresh_new  = actual edge_thresh used for pupil
% mean_residual    = residual of pupil ellipse fit
% points           = actual points on pupil detected


function [pupil, CRout, edge_thresh_new,  mean_residual, points, points_fraction] = ...
    detectPupilCR(I, edge_thresh, p)

% Process inputs
I = single(I);

if p.smoothSigma
%     gaussian_smooth_image = @(I, sigma) imfilter(I, fspecial('gaussian', [ceil(2.5*sigma) ceil(2.5*sigma)], sigma), 'symmetric');
%     I = gaussian_smooth_image(I, p.smoothSigma);
    I = imgaussfilt(I, p.smoothSigma);
end


% I_cr = I - p.pupil_intensity;
% I_cr = I_cr/152*255; % TEmp hard coding

I_cr = I - p.pupil_intensity;
I_cr = I_cr*255/(3*(p.iris_intensity-p.pupil_intensity)); % For CR detection, brighten image so pupil ~0 and iris ~255*1/3; 
% I_cr(I_cr>255) =255; I_cr(I_cr<0) = 0;


I_pupil = I_cr*3; % For pupil detection, brighten image further so iris ~255*3/4 % *3
I_pupil(I_pupil>255) =255;


if p.debug_on
    figure
    subplot(1,2,1)
    image(I_cr); colormap(gray); title('I_cr','Interp','none'); axis image
    subplot(1,2,2)
    image(I_pupil); colormap(gray); title('I_pupil','Interp','none');axis image
    linkaxes
end

clear I % To save memory


% if numel(p.radiiCR)==1
%     p.radiiCR = round(p.radiiCR*[.75 1.23]);
% end

% if isempty(plot_handles) || ~isfield(plot_handles, 'ah')
%     plot_handles.ah = figure;
% end

% if p.debug_on
%     figure;
% end

% Init
pupil = NaN(1,5);
mean_residual = NaN;
CRx = NaN(1, p.nCRs);
CRy = NaN(1, p.nCRs);
CRr = NaN(1, p.nCRs);
CRout = NaN(3,p.nCRs);

points = [];
points.px0 = NaN;
points.py0 = NaN;
points.px1 = NaN;
points.py1 = NaN;
points_fraction = NaN;

edge_thresh_new = [];

if isempty(p.pupil_start) || any(isnan(p.pupil_start)) || p.pupil_start(1)==0
%% Find guess for pupil center using radial symmetry transform
      
    border_remove = 0.05;
    p.pupil_start = [NaN NaN];
    Ipupil_crop = I_pupil(1:p.pupil_downsamp:end, 1:p.pupil_downsamp:end);
    img_radial_pupil = radialSymTransform(Ipupil_crop, round(p.radiiPupil/p.pupil_downsamp * [.9 1.1]), p.pupil_alpha);  
%     alpha - radial strictness parameter.
%                    1 - slack, accepts features with bilateral symmetry.
%                    2 - a reasonable compromise.
%                    3 - strict, only accepts radial symmetry.

    img_radial_pupil = removeBorder(img_radial_pupil, border_remove);
    [min_radial_pupil, ind] = min(img_radial_pupil(:));
    [pupilY, pupilX] = ind2sub(size(Ipupil_crop), ind);
    pupilY = pupilY*p.pupil_downsamp;
    pupilX = pupilX*p.pupil_downsamp;
    if min_radial_pupil<p.max_radialSymTransform
        if p.debug_on; disp('min_radial_pupil < p.max_radialSymTransform'); end
        p.pupil_start = [pupilX pupilY];
    end
    
    if p.debug_on
        figure; subplot(1,2,1); image(Ipupil_crop)
        hold on; plot(pupilX/p.pupil_downsamp, pupilY/p.pupil_downsamp,'r+'); title('(Downsampled by p.pupil_downsamp)')
        subplot(1,2,2); imagesc(img_radial_pupil); title('Pupil start detection')
        linkaxes
    end
    
end

p.pupil_start = round(p.pupil_start);    
if isnan(p.pupil_start(1))  
    if p.debug_on; disp('pupil_start is nan'); end
    return
end


%% Find corneal reflections

% Subselect the image around the pupilStart
if isfield(p, 'CR_box_width') && ~isempty(p.CR_box_width)
    
    %%
    r = p.CR_box_width;
    start_x = max(1,p.pupil_start(1)-r/2);
    stop_x = min(size(I_cr, 2), p.pupil_start(1) + r/2);
    start_y = max(1,p.pupil_start(2)-r/2); % rows = y
    stop_y = min(size(I_cr, 1), p.pupil_start(2) + r/2);
    I_cr_crop  = I_cr(start_y:stop_y, start_x:stop_x); % cols = x
    % Slower but better:
    [A, crxy0, crr0] = CircularHoughGrd(I_cr_crop, p.radiiCR, p.CRthresh, p.CRfilter, 1);
    
    % Faster but worse:
    %     [crxy0,crr0,metric] = imfindcircles(Icr_crop,p.radiiCR, ...
    %         'ObjectPolarity','bright','Sensitivity',0.94,'EdgeThreshold',0.1);
    %     figure; imagesc(Icr_crop);  colormap gray;
    %     hold on; viscircles(crxy0, crr0,'Color','y');
    if p.debug_on
        figure; subplot(1,2,1); image(I_cr_crop); hold on ;       axis image
        subplot(1,2,2); imagesc(A); hold on
        plot(crxy0(:,1), crxy0(:,2),'+r')
        axis image
    end

    crxy0 = bsxfun(@plus, crxy0, [start_x start_y]-1);
else
            [A, crxy0, crr0] = CircularHoughGrd(I_cr, p.radiiCR, p.CRthresh, p.CRfilter, 1);
%     [crxy0,crr0,metric] = imfindcircles(I_cr,p.radiiCR, ...
%         'ObjectPolarity','bright','Sensitivity',0.93,'EdgeThreshold',0.1)
end

if isempty(crr0)
    if p.debug_on; disp('did not find any CRs'); end
    return
end



%% Remove CR glints
I_mask = false(size(I_pupil));
I_mask(round(crxy0(:,2)), round(crxy0(:,1))) = true;
I_mask = imdilate(I_mask,strel('disk', round(mean(p.radiiCR)*1.7))); % Expand the mask (changed from 1.3)
I_pupil_noCR = I_pupil;
I_pupil_noCR(I_mask) = NaN;
if p.debug_on
    figure;subplot(1,2,1); colormap(gray);  imagesc(I_mask); axis image
    subplot(1,2,2); imagesc(I_pupil_noCR); axis image
end
I_pupil = I_pupil_noCR;
    
%% Find pupil
mean_residual = NaN;
[px, py, edge_thresh_new, points.px0, points.py0] = starburstPupilContourDetection(I_pupil, p.pupil_start(1),...
    p.pupil_start(2), edge_thresh, p.radiiPupil, p.minfeatures);

if edge_thresh_new < p.min_edge_thresh
        if p.debug_on; disp('Starburst pupil detect failed, edge_thresh below p.min_edge_thresh'); end
    return
end

if length(points.px0)>20
    p_robustEllipse = [];
    p_robustEllipse.min_num = 2;  % min number of points per cluster
    p_robustEllipse.sigma = 1.15; % error threshold; searching process converges if excluding any subset does not reduce the energy up to certain rate σ
    p_robustEllipse.eta = 2.5;      % default 5. error threshold; in case there are much more outliers than average subset size so that removing any subset does not reduce the energy
    p_robustEllipse.inclusion_penalty = 6;
    p_robustEllipse.size_penalty = 10;
    p_robustEllipse.size_ellipse = mean(p.radiiPupil); % Guess to enforce correct pupil size (pixels)
    [points.px1, points.py1, ellipse_result1] = robustEllipse(points.px0, points.py0,p_robustEllipse, p.debug_on);
    
    
    % Do better fit of resulting points
    ellipse_result2 = fitEllipse(points.px1,points.py1);
    
    if isempty(ellipse_result2.x0) || ellipse_result2.b/ellipse_result2.a>3 || ellipse_result2.a/ellipse_result2.b>3
        if p.debug_on; disp('Pupil ellipse fit failed'); end
        return
    end
    % Find the ellipse residuals
    a = linspace(0,2*pi,200);
    ellipse_x = ellipse_result2.a*cos(a)*cos( ellipse_result2.phi) - sin( ellipse_result2.phi)*ellipse_result2.b*sin(a) + ellipse_result2.x0;
    ellipse_y = ellipse_result2.a*cos(a)*sin( ellipse_result2.phi) + cos( ellipse_result2.phi)*ellipse_result2.b*sin(a) + ellipse_result2.y0;
    residuals = NaN(length(points.px1),1);
    for ii = 1:length(points.px1)
        dist_sq = ((points.px1(ii) - ellipse_x(:)).^2 + (points.py1(ii) - ellipse_y(:)).^2);
        residuals(ii) = sqrt(min(dist_sq));
    end
    mean_residual = mean(residuals);
    if mean_residual < p.ellipse_residual_thresh
        pupil = [ellipse_result2.x0 ellipse_result2.y0 ellipse_result2.a ellipse_result2.b ellipse_result2.phi];
    end
    
    % Calculate the fraction of original point retained in the final fit
    points_fraction = length(points.px0)/length(points.px1);
    
end


%% Check for CR duplicates
i = 1;
crxy = [];
crr = [];
crr0_init = crr0;
crxy0_init = crxy0;
while ~isempty(crr0_init)%i<length(crr)
    distThresh = 10; % (px) minimum separation between CRs
    duplicates = sqrt(sum((repmat(crxy0_init(i,:),size(crxy0_init,1),1) - crxy0_init).^2,2)) < distThresh; % 30
    crxy(end+1,:) = mean(crxy0_init(duplicates,:),1);
    crr(end+1,:) = mean(crr0_init(duplicates,:),1);
    crr0_init(duplicates) = [];
    crxy0_init(duplicates,:) = [];
end

% If more than N CRs detected, sort by distance from pupil
if size(crxy,1)>p.nCRs
    dist = sqrt(sum((bsxfun(@minus, crxy, pupil(1:2))).^2, 2));
    [~, inds] = sort(dist);
    crxy = crxy(inds(1:p.nCRs),:);
    crr = crr(inds(1:p.nCRs),:);
end

% Sort remaining CRs by horizontal position
[crx, ind] = sort(crxy(:,1),1,'ascend');
cry = crxy(ind,2);
crr = crr(ind);

% Fill in other CRs with NaNs if not present
CRx(1:length(crx)) = crx;
CRy(1:length(cry)) = cry;
CRr(1:length(crr)) = crr;
CRout = [CRx; CRy; CRr];

% DEBUG: Plot CR circles
if p.debug_on
    figure
    imagesc(I_cr);
    axis image; colormap(gray)
    a = 0:.001:2*pi; hold on
    for ii = 1:length(crr0)
        plot(crr0(ii).*cos(a) + crxy0(ii,1), crr0(ii).*sin(a)+crxy0(ii,2),'c')
    end
    for ii = 1:length(crr)
        plot(crr(ii).*cos(a) + crxy(ii,1), crr(ii).*sin(a)+crxy(ii,2),'y')
    end
    plot(crxy0(:,1), crxy0(:,2), 'ro')
    plot(crx, cry, 'y+')
end
%  END DEBUG: Plot CR circles




