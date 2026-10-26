function p = defaultTrackerParams()
% p = defaultTrackerParams()
% Pupil / corneal reflection tracker parameters, one struct element per camera.
% See detectPupilCR for how each field is used.

p = [];
p.radiiPupil = 35;      % (pixels) 20
p.radiiCR = [1 5];          % (pixels) [4 7]
p.CRthresh = 12;        % (default 10) Threshold for subtracting background
p.CRfilter = 6;         % (default 3, minimum 3). Set larger to detect imperfect circles - but sometimes too large throws an error esp with small radiiCR
p.CR_box_width = 100;   % (pixels) Crop image for faster CR search
p.pupil_downsamp = 4;   % (pixels) factor to downsample for initial pupil search
p.pupil_alpha = 2;      % Sensitivity to radial symmetry. 1 - slack, 3 - strict, ... and you can go higher
p.minfeatures = .9;     % (fraction, [0 1]) min features required for starburst pupil detection
p.smoothSigma = 3;      % (pixels) smooth image (2)
p.ellipse_residual_thresh = 1.3; % Max mean residual to accept for final ellipse fit
p.max_radialSymTransform = -40;  % If pupil guesses are bad, move lower to skip more frames (speeds up tracking but might miss more data)
p.nCRs = 2;
p.edge_thresh0 = 128;       % Initial guess, increase if pupil fit is too small, decrease to run faster
p.max_bad_frames = 1;
p.min_edge_thresh = 6;
p.plot_on = 1;
p.debug_on = 0;
p.pupil_start = [NaN NaN];
p.cropX = []; % optional pre-crop image, e.g. [500 1400] (empty = full frame)
p.cropY = []; % e.g. [400 1000]
p.pupil_intensity = 37; % Adjust based on images if needed % 30 % 100/130
p.iris_intensity = 65; % Adjust based on images if needed %80
p.example_t = 0;        % (s) time of the preview frame shown before tracking (0 = first frame)

p(2) = p(1); % Same settings for the second camera
