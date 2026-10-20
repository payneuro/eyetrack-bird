function closeEyeCameras(cams)
% closeEyeCameras(cams)
% Release the cameras opened by openEyeCameras.

for k = 1:numel(cams)
    if ~isempty(cams(k).vid) && isvalid(cams(k).vid)
        delete(cams(k).vid);
    end
end
