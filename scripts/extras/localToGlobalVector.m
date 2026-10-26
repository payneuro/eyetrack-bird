function v_out = localToGlobalVector(Rglobal, vlocal)
% Convert from local coordinates (e.g. calibrated angle of eye relative to 
% rigid body) to global coordinates, using rigidbody position measured over
% time
% 
% Rglobal is 3x3xnt
% vlocal is 3x1 or 1x3
    
nt = size(Rglobal,3);
v_out = zeros(3,nt);
for ii = 1:3
    Rcurr = squeeze(Rglobal(:,ii,:));
    v_out = v_out + Rcurr*vlocal(ii);
end

