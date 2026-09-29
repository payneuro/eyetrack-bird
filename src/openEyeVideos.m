function [vid1, vid2, N_eye] = openEyeVideos(filepath_eye, camfilename)
% [vid1, vid2, N_eye] = openEyeVideos(filepath_eye, camfilename)
% Open the cam1/cam2 eye videos in a session folder. N_eye is the frame
% count of the shorter video.

vid = cell(1,2);
for cam = 1:2
    d = dir(fullfile(filepath_eye, sprintf(camfilename, cam)));
    if isempty(d)
        error('No video matching %s in %s', sprintf(camfilename, cam), filepath_eye)
    elseif numel(d) > 1
        warning('%i videos match %s, using %s', numel(d), sprintf(camfilename, cam), d(1).name)
    end
    vid{cam} = VideoReader(fullfile(d(1).folder, d(1).name));
end
vid1 = vid{1};
vid2 = vid{2};
N_eye = min(round(vid1.Duration*vid1.FrameRate), round(vid2.Duration*vid2.FrameRate));
