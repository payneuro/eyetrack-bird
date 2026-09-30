function x = wrap180(x)
% x = wrap180(x)
% Wrap angles in degrees to [-180, 180]. Same result as the Mapping
% Toolbox's wrapTo180: values already in range are unchanged, and positive
% odd multiples of 180 map to 180.

out_of_range = (x < -180) | (x > 180);
y = x(out_of_range) + 180;
positive = y > 0;
y = mod(y, 360);
y(y == 0 & positive) = 360;
x(out_of_range) = y - 180;
