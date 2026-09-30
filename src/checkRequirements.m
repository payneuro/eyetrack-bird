function T = checkRequirements()
% T = checkRequirements()
% Table of MATLAB toolboxes and outside software the pipeline uses, whether
% each is installed on this computer, what it's for, and how to install it.
% T.url is a download page where there is one ('' otherwise).

get_addon = 'Home > Environment > Add-Ons > Get Add-Ons: "%s"';
rows = {
    % name, needed for, installed, how to install
    'Computer Vision Toolbox', 'Required: calibration, triangulation', ...
        exist('triangulate', 'file') > 0, sprintf(get_addon, 'Computer Vision Toolbox')
    'Image Processing Toolbox', 'Required: calibration, tracking', ...
        exist('imgaussfilt', 'file') > 0, sprintf(get_addon, 'Image Processing Toolbox')
    'Signal Processing Toolbox', 'Required: tracking, cleaning', ...
        exist('filtfilt', 'file') > 0, sprintf(get_addon, 'Signal Processing Toolbox')
    'Spinnaker SDK (SpinView)', 'Required: camera settings and recording', ...
        spinnakerInstalled(), 'Download the full Spinnaker SDK for Windows x64 from Teledyne FLIR (includes SpinView, USB3 drivers, and the GenTL producer)'
    'Qualisys Track Manager (QTM)', 'Required: head tracking, trigger, axes calibration', ...
        qtmInstalled(), 'Install from Qualisys (license needed)'
    'Image Acquisition Toolbox', 'Planned: capture from MATLAB', ...
        exist('videoinput', 'file') > 0, sprintf(get_addon, 'Image Acquisition Toolbox')
    'GenICam Interface support package', 'Planned: capture from MATLAB', ...
        gentlInstalled(), [sprintf(get_addon, 'GenICam Interface') ' (Image Acquisition Toolbox support package)']
    'ffmpeg', 'Planned: GPU video encoding', ...
        ffmpegInstalled(), 'Download a Windows build with NVENC (gyan.dev "full"), add its bin folder to PATH'
    'Parallel Computing Toolbox', 'Optional: GPU processing', ...
        exist('gpuDevice', 'file') > 0, sprintf(get_addon, 'Parallel Computing Toolbox')
    };
T = cell2table(rows, 'VariableNames', {'item', 'needed_for', 'ok', 'how_to_install'});
T.ok = logical(T.ok);
T.url = repmat({''}, height(T), 1);
T.url{strcmp(T.item, 'ffmpeg')} = 'https://www.gyan.dev/ffmpeg/builds/';
T = [T(~T.ok,:); T(T.ok,:)]; % missing first
end

function tf = spinnakerInstalled()
tf = isfolder('C:\Program Files\FLIR Systems\Spinnaker') || isfolder('C:\Program Files\Teledyne\Spinnaker');
end

function tf = qtmInstalled()
tf = ~isempty(dir('C:\Program Files*\Qualisys\Qualisys Track Manager*'));
end

function tf = gentlInstalled()
tf = false;
if exist('imaqhwinfo', 'file') == 0; return; end
try
    w = warning('off', 'all');
    info = imaqhwinfo;
    warning(w);
    tf = any(strcmpi(info.InstalledAdaptors, 'gentl'));
catch
end
end

function tf = ffmpegInstalled()
[status, ~] = system('where ffmpeg');
tf = status == 0;
end
