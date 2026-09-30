function [E, mask_temp] = cleanEye(Eraw, scale)
% To loosen criteria, increase scale e.g. to 2

if ~exist('scale','var')
    scale = 1;
end

% PARAMS
max_resid = 1.2*scale;
nstd_radius = 2;
min_ecc = 0.7;
dist_thresx = 80; % (px)
dist_thresy = 10;
dist_thres_cr = 10; % (px)
dist_thresh_crpupil = 40;
maxgap = 0.02;  % (s) frame rate is typically 50 Hz, so 20 ms = fill in one gap
medfilt = 0.06; % (s) % 0.05

E = Eraw;
dt_eye = mean(diff(E.t));

% Check residual from ellipse fit
mask_resid = E.resid1>max_resid*scale | E.resid2>max_resid*scale;
fprintf('mask resid %.2f\n', mean(mask_resid))

% Check size of pupil
p_radius1 = max(E.pupil1(:, 3:4),[],2);
p_radius1 = (p_radius1 - nanmean(p_radius1))/nanstd(p_radius1);
p_radius2 = max(E.pupil2(:, 3:4),[],2);
p_radius2 = (p_radius2 - nanmean(p_radius2))/nanstd(p_radius2);
mask_radius = abs(p_radius1)>nstd_radius*scale | abs(p_radius2)>nstd_radius*scale;
fprintf('mask_radius %.2f\n', mean(mask_radius))

% Check eccentricity of pupil
p_ecc1 = min(E.pupil1(:, 3:4),[],2)./max(E.pupil1(:, 3:4),[],2);
p_ecc2 = min(E.pupil1(:, 3:4),[],2)./max(E.pupil1(:, 3:4),[],2);
mask_ecc = p_ecc1<min_ecc | p_ecc2<min_ecc;
fprintf('mask_ecc %.2f\n', mean(mask_ecc))

% Check distance in pix between pupil in two images
xdist = E.pupil1(:,1) - E.pupil2(:,1);
ydist = E.pupil1(:,2) - E.pupil2(:,2);
mask_pupil_dist = abs(xdist - median(xdist,'omitnan')) > dist_thresx*scale | ...
    abs(ydist - median(ydist,'omitnan')) > dist_thresy*scale;
fprintf('mask_pupil_dist %.2f\n', mean(mask_pupil_dist))

% Check distance between two CRs in each camera
xdist1 = abs(E.cr1(:,1,1) - E.cr1(:,1,2));
ydist1 = abs(E.cr1(:,2,1) - E.cr1(:,2,2));
xdist2 = abs(E.cr2(:,1,1) - E.cr2(:,1,2));
ydist2 = abs(E.cr2(:,2,1) - E.cr2(:,2,2));
mask_distcr = abs(xdist1 - median(xdist1,'omitnan')) > dist_thres_cr*scale | ...
    abs(ydist1 - median(ydist1,'omitnan')) > dist_thres_cr*scale | ...
    abs(xdist2 - median(xdist2,'omitnan')) > dist_thres_cr*scale | ...
    abs(ydist2 - median(ydist2,'omitnan')) > dist_thres_cr*scale;
fprintf('mask_distcr %.2f\n', mean(mask_distcr))

% Check distance from all CRs to pupil
pcdist1a = sqrt(sum((E.cr1(:,1:2,1) - E.pupil1(:,1:2)).^2, 2, 'omitnan'));
pcdist1b = sqrt(sum((E.cr1(:,1:2,2) - E.pupil1(:,1:2)).^2, 2, 'omitnan'));
pcdist2a = sqrt(sum((E.cr2(:,1:2,1) - E.pupil2(:,1:2)).^2, 2, 'omitnan'));
pcdist2b = sqrt(sum((E.cr2(:,1:2,2) - E.pupil2(:,1:2)).^2, 2, 'omitnan'));
mask_distcr_pupil = pcdist1a > dist_thresh_crpupil*scale |  pcdist1b > dist_thresh_crpupil*scale | ...
    pcdist2a > dist_thresh_crpupil*scale |  pcdist2b > dist_thresh_crpupil*scale;
fprintf('mask_distcr_pupil %.2f\n', mean(mask_distcr_pupil))

% Check presence of two CRs
% maskcr = any(any(isnan(E.cr1(:,1:2,:)),2),3) | any(any(isnan(E.cr2(:,1:2,:)),2),3);
% fprintf('maskcr %.2f\n', mean(maskcr))

% Mask everything
mask = mask_resid | mask_radius | mask_ecc | mask_pupil_dist | mask_distcr | mask_distcr_pupil ;
E.pupil1(mask,:) = NaN;
E.pupil2(mask,:) = NaN;
E.cr1(mask,:) = NaN;
E.cr2(mask,:) = NaN;
E.resid1(mask,:) = NaN;
E.resid2(mask,:) = NaN;


% Fill in small gaps 
maxgapi = round(maxgap/dt_eye)+1; % Bug fix 12/13/2023 -- a gap of 1 does nothing
E = processStruct(E, @(x) interp1gap(x, maxgapi));

% Preserve NaN masking at this point - if data is missing for any
% measurement, remove it 
mask_temp = isnan(E.pupil1(:,1)) | isnan(E.pupil2(:,1)) | any(isnan(E.cr1(:,1,:)),3) | any(isnan(E.cr2(:,1,:)),3);

% median filter
medfilti = round(medfilt/dt_eye);
E = processStruct(E, @(x) medfilt1(x, medfilti,'omitnan','truncate'));

E.pupil1(mask_temp,:) = NaN;
E.pupil2(mask_temp,:) = NaN;
E.cr1(mask_temp,:,:) = NaN;
E.cr2(mask_temp,:,:) = NaN;
E.resid1(mask_temp,:) = NaN;
E.resid2(mask_temp,:) = NaN;


