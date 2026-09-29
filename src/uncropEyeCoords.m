function E = uncropEyeCoords(E, p)
% E = uncropEyeCoords(E, p)
% Convert pupil and CR centers from cropped-image pixels (p(cam).cropX/cropY
% in trackEye) back to full-frame pixels, which the stereo calibration uses.
% No change if no crop was set.

for cam = 1:2
    if ~isfield(p,'cropX') || isempty(p(cam).cropX)
        continue
    end
    offset = [p(cam).cropX(1) p(cam).cropY(1)] - 1;
    pupil = sprintf('pupil%i', cam);
    cr = sprintf('cr%i', cam);
    E.(pupil)(:,1:2) = E.(pupil)(:,1:2) + offset;
    E.(cr)(:,1:2,:) = E.(cr)(:,1:2,:) + offset;
end
