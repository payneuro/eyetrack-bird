function [p_pupil, p_cornea, dist_pc] = correctLengthP_CR(p_pupil, p_cornea)
% Correction to ensure consistent length of pupil-corneal reflection vectors

dist_pc = sqrt(sum((p_pupil - p_cornea).^2,2));
direction = p_pupil(:,3) > p_cornea(:,3); % direction should be 0, pupil closer to camera than CR, if calibration was ru correctly
fprintf('Fraction of frames with pupil farther than CR: %.3f\n', nanmean(direction(~isnan(p_pupil(:,1)))));
K = median(dist_pc,'omitnan'); % (mm)

% Camera coordinates:
% First column: x axis of image in camera 1 (cols)
% Second column: y axis of image in camera 2 (rows, down in actual space)
% Third column: pointing along optical axis away from cameras
xc = p_cornea(:,1);
yc = p_cornea(:,2);
zc = p_cornea(:,3);

xp = p_pupil(:,1);
yp = p_pupil(:,2);

% term_inside_sqrt = dist_pc.^2 - (xc-xp).^2 - (yc-yp).^2; % debug
term_inside_sqrt = K^2 - (xc-xp).^2 - (yc-yp).^2;
term_inside_sqrt(term_inside_sqrt<0) = NaN;
zp = nan(size(xp));
zp(direction) = zc(direction) + sqrt(term_inside_sqrt(direction));
zp(~direction) = zc(~direction) - sqrt(term_inside_sqrt(~direction));
zp = real(zp);
p_pupil(:,3) = zp;

imag_mask = term_inside_sqrt<0;
mask = imag_mask & direction;
p_pupil(mask,:) = NaN;
p_cornea(mask,:) = NaN;


