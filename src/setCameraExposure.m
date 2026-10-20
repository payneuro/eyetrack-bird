function exposure_used = setCameraExposure(cam, exposure_us)
% exposure_used = setCameraExposure(cam, exposure_us)
% Set one camera's exposure (us). The camera rounds to its own step (e.g.
% 6000 -> 5997 us); exposure_used is the value it applied.

w = warning('off', 'all'); % silence the "adjusted by the camera" notice
cam.src.ExposureTime = exposure_us;
warning(w);
exposure_used = cam.src.ExposureTime;
