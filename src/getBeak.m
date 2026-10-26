function beak = getBeak(filepath_eye, camfilename, resume_beak, run_beak, DI)
% beak = getBeak(filepath_eye, camfilename, resume_beak, run_beak, DI)
% Click the beak tip in both cameras every DI frames (default P.preview_step_frames).
% Left click = accept, right click = skip ahead, Enter = finish.
% Returns beak.p1/p2 (N x 2 pixels, NaN = not clicked). Loads beak.mat if it
% exists; resume_beak adds clicks to it. With run_beak false and no beak.mat,
% returns [].

if ~exist('DI','var') || isempty(DI)
    DI = eyetrackParams().preview_step_frames; % frames to skip each time
end

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


%% Load the high res video
[vid1, vid2] = openEyeVideos(filepath_eye, camfilename);
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
    [I1, I2] = readEyeFrames(vid1, vid2, ii); % full frames, no crop
    
    imagesc(ah1, I1); axis(ah1, 'image'); title(ah1, sprintf('Camera 1, frame %i: click beak tip (right click = skip, Enter = done)',ii))
    imagesc(ah2, I2); axis(ah2, 'image'); title(ah2, 'Camera 2: then click beak tip here')
    drawnow
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

