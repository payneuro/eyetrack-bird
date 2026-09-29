function P = eyetrackParams()
% P = eyetrackParams()
% Paths and constants shared by the calibration and analysis pipeline.
% Edit here (or in the GUI) instead of in individual scripts.

% Paths
P.data_root  = 'Z:\Hannah\eyetrack\behavior';    % Session folders, e.g. HC13_230525
P.calib_root = 'Z:\Hannah\eyetrack\calibration'; % Calibration folders named YYMMDD
P.camfilename = 'cam%i*.avi';                    % Eye video template, %i = camera number

% Calibration
P.square_size = 4;          % (mm) checkerboard square size
P.mirror_thickness = -0.1;  % (mm) front-coated Thorlabs mirror; old back-coated acrylic was -2.86
P.axes_thresh = 250;        % Intensity threshold for saturated axes markers (after smoothing)

% Recording
P.downsample_eye = 6;       % QTM frames per eye camera frame (QTM Out2 divisor)

% Beak labeling
P.beak_skip_frames = 45;    % Frames to jump between beak clicks
