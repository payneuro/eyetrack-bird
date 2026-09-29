function filepath_camera = findCalibrationFolder(filepath_eye, calib_root)
% filepath_camera = findCalibrationFolder(filepath_eye, calib_root)
% Calibration folder for a session: the six digits after the last '_' in
% the session folder name, e.g. HC13_230525b -> <calib_root>\230525

[~, name] = fileparts(filepath_eye);
tok = regexp(name, '_(\d{6})[^_]*$', 'tokens', 'once');
if isempty(tok)
    error('Session folder %s does not end in _YYMMDD', name)
end
filepath_camera = fullfile(calib_root, tok{1});
