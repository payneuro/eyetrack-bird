function [I1, I2] = readEyeFrames(vid1, vid2, ii, p)
% [I1, I2] = readEyeFrames(vid1, vid2, ii, p)
% Read frame ii from both eye videos as single grayscale, cropped to
% p(cam).cropX/cropY if set.

I1 = toGray(read(vid1, ii));
I2 = toGray(read(vid2, ii));
if exist('p','var')
    I1 = cropImage(I1, p(1));
    I2 = cropImage(I2, p(2));
end
end

function I = toGray(I)
if size(I,3) == 3
    I = rgb2gray(I);
end
I = single(I);
end

function I = cropImage(I, p)
if isfield(p,'cropX') && ~isempty(p.cropX)
    I = I(p.cropY(1):p.cropY(2), p.cropX(1):p.cropX(2));
end
end
