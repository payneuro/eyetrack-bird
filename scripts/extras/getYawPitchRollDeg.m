function [yaw, pitch, roll] = getYawPitchRollDeg(R)
% x axis = first column
% y axis = second column
% z axis = third column
% Yaw: rotate around original z axis
% Pitch: rotation around new y axis
% Roll: rotate around new x axis?

yaw = squeeze(atan2d(R(2,1,:), R(1,1,:)));
pitch = squeeze(-asind(R(3,1,:)));
roll = squeeze(atan2d(R(3,2,:), R(3,3,:)));
