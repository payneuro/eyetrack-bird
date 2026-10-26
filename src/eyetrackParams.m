function P = eyetrackParams()
% P = eyetrackParams()
% Paths and constants shared by the calibration and analysis pipeline.
% Edit here (or in the GUI) instead of in individual scripts.

% Paths
P.data_root  = 'Z:\Hannah\eyetrack\behavior';    % Session folders, e.g. HC13_230525
P.calib_root = 'Z:\Hannah\eyetrack\calibration'; % Calibration folders named YYMMDD
P.camfilename = 'cam%i*.*';                      % Eye video template, %i = camera number (.avi raw or .mp4 compressed)

% Cameras (Blackfly S serial numbers)
P.cam_serials = {'22048634', '21554508'}; % {cam1 = left, cam2 = right}
% Set on both cameras when the GUI connects (GenICam feature names, as in SpinView),
% so SpinView isn't needed. Exposure and the trigger are set by the GUI itself.
P.camera_settings = struct( ...
    'ExposureAuto', 'Off', ...
    'GainAuto', 'Off', ...
    'Gain', 3, ...                 % (dB)
    'GainConversion', 'HCG', ...   % high conversion gain (Analog Control)
    'TriggerDelay', 100);          % (us) >= the QTM exposure (50-80 us), so QTM strobes don't show in the eye

% Calibration
P.square_size = 4;                     % (mm) checkerboard square size
P.mirror_thickness = -0.1;             % (mm) checkerboard sticker on the front-coated Thorlabs mirror
P.exposure_led_spot_ms = 0.019;        % (ms) LED spot images: only the reflection shows
P.exposure_mirror_checkerboard_ms = 6; % (ms) mirror checkerboard images
P.axes_thresh = 250;                   % intensity threshold for saturated axes markers (after smoothing)
P.axes_leg_tol = 1;                    % (mm) camera and QTM axes-triangle legs must agree this closely (past calibrations: < 0.3 mm)

% Recording
P.downsample_eye = 6;       % QTM frames per eye camera frame (QTM Out2 divisor)
P.trigger_line = {'Line3', 'Line3'}; % {cam1, cam2} input wired to QTM Out 2 (one frame per rising edge)
P.eye_fps = 50;            % Eye camera frame rate set by the QTM trigger (written into the video files)
P.record_exposure_ms = 16.003; % (ms) eye camera exposure while recording
P.ffmpeg = 'C:\Program Files\ffmpeg-7.1.1\bin\ffmpeg.exe'; % for compressed (GPU H.264) recording
P.keyframe_s = 2;           % (s) keyframe spacing in compressed recordings: jumping to a frame decodes from the last keyframe (5 s ffmpeg default: ~0.33 s per jump; 2 s: ~0.20 s, ~3% larger files)

% Skipping frames without the bird (findBirdFrames)
P.skip_empty_frames = true;   % default for tracking and the preview; the GUI has a checkbox
P.bird_shrink = 16;           % frames are shrunk this many times per side (each pixel = mean of a 16x16 block) before comparing
P.bird_pixel_thresh = 25;    % gray levels a pixel must differ from the empty-arena background
P.bird_frac_thresh = 0.01;    % fraction of changed pixels (in either camera) that means the bird is in view (~111 of the ~11000 shrunken pixels)
P.bird_pad_s = 0;             % (s) also track this long before and after each in-view stretch

% Tracker preview (Analyze behavior tab)
P.preview_step_frames = 30;   % frames moved by the << and >> buttons, and between beak clicks

