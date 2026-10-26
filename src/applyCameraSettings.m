function txt = applyCameraSettings(cams, settings)
% txt = applyCameraSettings(cams, settings)
% Set camera features (GenICam names, e.g. Gain, TriggerDelay) on both
% cameras from settings, a struct of feature name -> value
% (P.camera_settings), so nothing has to be set in SpinView.
% Features a camera doesn't have are skipped and listed in txt.
% txt - one line: the values read back from cam1, and anything skipped

names = fieldnames(settings);
skipped = {};
for k = 1:numel(cams)
    info = propinfo(cams(k).src);
    for n = 1:numel(names)
        if ~isfield(info, names{n})
            skipped{end+1} = names{n}; %#ok<AGROW>
            continue
        end
        w = warning('off', 'all'); % "adjusted by the camera" notices
        try
            cams(k).src.(names{n}) = settings.(names{n});
        catch err
            skipped{end+1} = sprintf('%s (%s)', names{n}, err.message); %#ok<AGROW>
        end
        warning(w);
    end
end
got = names(isfield(propinfo(cams(1).src), names));
vals = cellfun(@(n) sprintf('%s=%s', n, string(cams(1).src.(n))), got, 'UniformOutput', false);
txt = ['Camera settings: ' strjoin(vals, ', ')];
if ~isempty(skipped)
    txt = [txt '. Not available, skipped: ' strjoin(unique(skipped, 'stable'), ', ')];
end
end
