function R = rotationBetween(a, b)
% R = rotationBetween(a, b)
% Rotation matrix that turns direction a onto direction b (Rodrigues), so
% R*a(:) is parallel to b. Replaces vrrotvec2mat(vrrotvec(a, b)), which needs
% Simulink 3D Animation.
a = a(:)/norm(a); b = b(:)/norm(b);
v = cross(a, b); s = norm(v); c = dot(a, b);
if s < eps
    if c > 0
        R = eye(3);
    else % opposite: turn 180 deg about any axis perpendicular to a
        n = null(a'); n = n(:,1);
        R = 2*(n*n') - eye(3);
    end
    return
end
K = [0 -v(3) v(2); v(3) 0 -v(1); -v(2) v(1) 0];
R = eye(3) + K + K^2*(1 - c)/s^2;
end
