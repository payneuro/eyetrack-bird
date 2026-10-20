function T = checkRequirements()
% T = checkRequirements()
% Table of MATLAB toolboxes and outside software the pipeline uses, whether
% each is installed on this computer, what it's for, and how to install it.
% T.url is a download page where there is one ('' otherwise).

get_addon = 'Home > Environment > Add-Ons > Get Add-Ons: "%s"';
[ffmpeg, gpu_ok, version] = findFfmpeg(eyetrackParams().ffmpeg);
    function s = ffmpegNote()
        s = 'Required: compressed recording (NVIDIA GPU)';
        if isempty(ffmpeg)
            s = [s '. Not found'];
        elseif ~gpu_ok
            s = sprintf('%s. Found %s (%s) but it can''t use the GPU: driver too old for it?', s, version, ffmpeg);
        else
            s = sprintf('%s. Using %s (%s)', s, version, ffmpeg);
        end
    end
rows = {
    % name, needed for, installed, how to install
    'Computer Vision Toolbox', 'Required: calibration, triangulation', ...
        exist('triangulate', 'file') > 0, sprintf(get_addon, 'Computer Vision Toolbox')
    'Image Processing Toolbox', 'Required: calibration, tracking', ...
        exist('imgaussfilt', 'file') > 0, sprintf(get_addon, 'Image Processing Toolbox')
    'Signal Processing Toolbox', 'Required: tracking, cleaning', ...
        exist('filtfilt', 'file') > 0, sprintf(get_addon, 'Signal Processing Toolbox')
    'Spinnaker SDK (SpinView)', 'Required: recording; camera driver for MATLAB capture', ...
        spinnakerInstalled(), 'Download the full Spinnaker SDK for Windows x64 from Teledyne FLIR (includes SpinView, USB3 drivers, and the GenTL producer)'
    'Qualisys Track Manager (QTM)', 'Required: head tracking, trigger, axes calibration', ...
        qtmInstalled(), 'Install from Qualisys'
    'Image Acquisition Toolbox', 'Required: calibration capture, recording', ...
        exist('videoinput', 'file') > 0, sprintf(get_addon, 'Image Acquisition Toolbox')
    'GenICam Interface support package', 'Required: calibration capture, recording', ...
        gentlInstalled(), [sprintf(get_addon, 'GenICam Interface') ' (Image Acquisition Toolbox support package)']
    'ffmpeg', ffmpegNote(), gpu_ok, ['Either update the NVIDIA driver so the installed ffmpeg can use the GPU, or ' ...
        'download ffmpeg-7.1.1-essentials_build.zip from the page below and unzip it to C:\Program Files\ffmpeg-7.1.1 ' ...
        '(so bin\ffmpeg.exe is inside), or set P.ffmpeg in eyetrackParams.m to where ffmpeg.exe is. ' ...
        'ffmpeg 7.1 works with older drivers (tested with 573); ffmpeg 8+ needs a newer one']
    };
T = cell2table(rows, 'VariableNames', {'item', 'needed_for', 'ok', 'how_to_install'});
T.ok = logical(T.ok);
T.url = repmat({''}, height(T), 1);
T.url{strcmp(T.item, 'Spinnaker SDK (SpinView)')} = 'https://www.teledynevisionsolutions.com/products/spinnaker-sdk/';
T.url{strcmp(T.item, 'ffmpeg')} = 'https://github.com/GyanD/codexffmpeg/releases/tag/7.1.1';
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
