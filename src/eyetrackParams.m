function P = eyetrackParams()
% P = eyetrackParams()
% Paths and constants shared by the calibration and analysis pipeline.
% Edit here (or in the GUI) instead of in individual scripts.

% Paths
P.data_root  = 'Z:\Hannah\eyetrack\behavior';    % Session folders, e.g. HC13_230525
P.calib_root = 'Z:\Hannah\eyetrack\calibration'; % Calibration folders named YYMMDD
P.camfilename = 'cam%i*.avi';                    % Eye video template, %i = camera number

% Cameras (Blackfly S serial numbers)
P.cam_serials = {'22048634', '21554508'}; % {cam1 = left, cam2 = right}

% Calibration
P.square_size = 4;                     % (mm) checkerboard square size
P.mirror_thickness = -0.1;             % (mm) checkerboard sticker on the front-coated Thorlabs mirror
P.exposure_led_spot_ms = 0.019;        % (ms) LED spot images: only the reflection shows
P.exposure_mirror_checkerboard_ms = 6; % (ms) mirror checkerboard images
P.axes_thresh = 250;                   % intensity threshold for saturated axes markers (after smoothing)

% Recording
P.downsample_eye = 6;       % QTM frames per eye camera frame (QTM Out2 divisor)

% Beak labeling
P.beak_skip_frames = 45;    % Frames to jump between beak clicks
