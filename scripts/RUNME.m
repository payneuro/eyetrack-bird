% Scripted version of the pipeline. For the GUI, run eyetrackGUI.
% Paths and constants are in src/eyetrackParams.m.
code_root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(code_root,'src'));
P = eyetrackParams();
data_root = P.data_root;
ploton = 1;

%% Process a single calibration of cameras
filepath_camera = fullfile(P.calib_root, '250307');
[C,A] = calibrateCameras(filepath_camera, P);
% NOTE: To re-run calibration analysis, delete axes.mat and calib.mat files (or pass force = 'all')


%% Run a single eye tr acking file
% NOTE: To re-run eye tracking, delete eye.mat file


% dir_root = 'HC08_221028b'; %IND102_220707a

% dir_root = 'IND102_220707a'; % *** example traces?
% downsample_eye = 6;
% 
% dir_root = 'HC07_221013';
% downsample_eye = 6;
% 
% dir_root = 'HC08_221028a'; % Good
% dir_root = 'HC08bad_221028b'; % Problem! Couldn't solve, exclude by renaming folder for now
% dir_root = 'HC08_221028c'; % Good
% downsample_eye = 6;

% dir_root = 'HC09_221028b'; % QTM file corrupted? Don't use
% dir_root = 'HC09_221028a';
% downsample_eye = 6;

% dir_root = 'HC11_230201a'; %*** example
% downsample_eye = 6;

% dir_root = 'HC11_230201b';
% downsample_eye = 6;
% 
% dir_root = 'HC12_230210a';
% downsample_eye = 5;
% 
% dir_root = 'HC13_230525';
% downsample_eye = 6;
% 
% dir_root = 'HC14_230902'; %*** continue running!
% downsample_eye = 6;
% 
% dir_root = 'HC15_230902';
% downsample_eye = 6;
%
% dir_root = 'HC17_230902';
% downsample_eye = 6;
% 
% 
% dir_root = 'HC17R_231102';
% dir_root = 'HC17R_231103b';
% downsample_eye = 6;
%
% dir_root = 'HC18R_231212';
% downsample_eye = 6;
% 
% 
% dir_root = 'HC19_240627';
% downsample_eye = 6;


% runEyetrackSingle(fullfile(data_root, dir_root),downsample_eye)


%% Run analysis for all birds (to re-run raw eye tracking, delete the results file e.g. eye.mat and eye_trangulate.mat)
% dir_roots = {'IND102_22*', 'HC05_22*', 'HC06_22*','HC07_22*','HC08_22*',...
%     'HC09_22*','HC10_22*','HC11_2*','HC12_2*','HC13_2*','HC14_2*','HC15_2*',...
%     'HC17_2*','HC17R_2*','HC18R_2*','HC19_2*'};

dir_roots = {'HC08_22*','HC10_22*','HC11_2*','HC12_2*','HC13_2*','HC15_2*',...
    'HC17_2*','HC18R_2*'} ; % 8 birds for paper
downsample_eyes = 6*ones(size(dir_roots));
downsample_eyes(startsWith(dir_roots,'HC12')) = 5;

% NOTE: 'ROS38_220308*','TRQ180_220310*','CHC37_220310*', only had two head markers, and acrylic barrier - up through 220630, possibly less accurate?
% NOTE: IND102 was measured before and after change on several days
% NOTE: RBY47_221013 is the same bird as HC06_221013 before surgery, could
% use instead if needed

Ht = table; stats = table;
for ii = 1:length(dir_roots)
    [~, Ht_bird, stats_bird] = runEyetrackAll(fullfile(data_root, dir_roots{ii}), downsample_eyes(ii), ploton, P);
    Ht = [Ht; Ht_bird]; stats = [stats; stats_bird]; %#ok<AGROW>
end

%% Plot results & give stats for all birds
plotEyetrack(Ht, stats);

