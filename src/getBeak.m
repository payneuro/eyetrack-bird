function [beak, flag_newdata] = getBeak(filepath_eye, camfilename, resume_beak, run_beak, DI)
% Click the beak tip in both cameras every DI frames (default 45).
% Left click = accept, right click = skip ahead, Enter = finish.

if ~exist('DI','var') || isempty(DI)
    DI = 45; % Number of frames to skip each time
end
flag_newdata = false;

if exist(fullfile(filepath_eye,'beak.mat'),'file')% Add more beak points
    beak = load(fullfile(filepath_eye,'beak.mat'));
    if resume_beak
        p1 = beak.p1;
        p2 = beak.p2;
        ii = beak.ii;
    else
        return
    end
    
end

if ~run_beak
    beak = [];
    return
end

flag_newdata = true;

%% Load the high res video
cam1 = dir(fullfile(filepath_eye, sprintf(camfilename, 1) ));
cam2 = dir(fullfile(filepath_eye, sprintf(camfilename, 2) ));
vid1 = VideoReader(fullfile(cam1.folder, cam1.name));
vid2 = VideoReader(fullfile(cam2.folder, cam2.name));
N_eye = min(vid1.NumFrames, vid2.NumFrames);


%% Display an image. Press arrows to jump x seconds ahead. Click to record beak locations in each image. Hit escape to finish
figure;
% maximize;
ah1 = subplot(1,2,1);
apos =  [0.0125    0.025    0.45    0.95];
set(ah1,'Pos',apos);
ah2 = subplot(1,2,2);
set(ah2,'Pos',apos+[0.5 0 0 0]); axis image; drawnow
colormap gray

%% Resume or start fresh?
if ~exist('p1','var')
    ii = 1; % index into video
    p1 = NaN(N_eye,2);
    p2 = NaN(N_eye,2);
end


while ii<N_eye
    % Load image
    I1 = single(rgb2gray(read(vid1,ii)));
    I2 = single(rgb2gray(read(vid2,ii)));
    
    imagesc(ah1, I1); axis(ah1, 'image'); title(sprintf('Frame %i',ii))
    imagesc(ah2, I2); axis(ah2, 'image');
    axes(ah1) %#ok
    disp('Select beak tip in camera 1. Right click to skip ahead, hit Enter to exit')
    try
        [x1,y1,button1] = ginput(1); % 1 = left click. 2= middle click. 3 = right click
    catch
        break
    end
    if isempty(button1) % EXIT
        break
    elseif button1 == 1 % ACCEPT POINT, ask for I2 point
        
        line(ah1, x1,y1,'Marker','+','Color',[1 0 0],'MarkerSize',30)
        
        disp('Select beak tip in camera 2.')
        [x2,y2,button2] = ginput(1); % 1 = left click. 2= middle click. 3 = right click
        
        if isempty(button2)
            break
        elseif button2==1
            line(ah2, x2,y2,'Marker','+','Color',[1 0 0],'MarkerSize',30)
            p1(ii,:) = [x1 y1]; %
            p2(ii,:) = [x2 y2]; %
        end
    end
    
    save(fullfile(filepath_eye,'beak.mat'),'p1','p2','ii')
    
    % Skip ahead a bit
    ii = ii+DI;
    
    
end

%% Save results!
save(fullfile(filepath_eye,'beak.mat'),'p1','p2','ii')

beak = [];
beak.p1 = p1;
beak.p2 = p2;

