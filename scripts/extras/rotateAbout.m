function  out = rotateAbout(a, b, theta)
% out = rotateAbout(a, b, theta)
% Rotate vector a about vector b by theta degrees.

% component of x parallel to v
xParV = @(x,v) dot(x, v) / dot(v, v) * v;

% component of x orthogonal to v. Result is perpendicular to v.
xPerpV = @(x, v) x - xParV(x, v);

w = cross(b, xPerpV(a,b));
w = w/norm(w);
out =  (xParV(a,b) + xPerpV(a,b) * cosd(theta) +...
    norm(xPerpV(a,b)) * w * sind(theta));
