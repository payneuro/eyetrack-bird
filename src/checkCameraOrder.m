function ok = checkCameraOrder(C)
% ok = checkCameraOrder(C)
% Warn if light 1 isn't left of light 2, or camera 1 isn't left of camera 2
% (x in camera-1 coordinates).

ok = true;
if C.p_light1(1) > C.p_light2(1)
    warning(['Light 1 should be the LED on the left in the cameras'' view, but it is on the right. ' ...
        'The tracker pairs corneal reflections left to right with light 1 and light 2, so check the lights images are not swapped.'])
    ok = false;
end
if C.p_cam1(1) > C.p_cam2(1)
    warning('Check that cameras 1 and 2 are not mislabelled in calibration folder')
    ok = false;
end
