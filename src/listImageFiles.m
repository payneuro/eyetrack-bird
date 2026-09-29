function files = listImageFiles(folder)
% files = listImageFiles(folder)
% Full paths of the image files (bmp, png, tif, jpg) in folder, sorted by name.

d = dir(folder);
d = d(~[d.isdir] & endsWith({d.name}, {'.bmp', '.png', '.tif', '.tiff', '.jpg'}, 'IgnoreCase', true));
files = fullfile(folder, {d.name});
