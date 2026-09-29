# eyetrack-bird
eye tracking code for dual camera video oculography + rigid body head tracking in freely moving birds

Cameras: Blackfly S BFS-U3-27S5M (2.8 MP monochrome 2/3" sensor. Note: higher resolution would be helpful but this is enough) 
Lenses: Edmund Optics 25mm/F1.4 59871
IR LEDs: LST1-01H01-IR01-01 LUXEON IR Domed 850n
 (Note: upgrade to Mouser 720-SFH4717ASAA1518 Infraret Oslon osram LEDs on custom Starboard v2 PCB for shorter exposure times?)
Mirror: mirrored on outer surface, Thorlabs ME2S-P01 


# Protocol: calibration
My calibrations  are saved here: Z:\Hannah\eyetrack\calibration
	1. Set up flat surface and camera module. Plug LEDs into 5 V, 2 A power supply
	2. Set QTM exposure time to 50-80 us (to avoid reflections in eye)
	3. Calibrate QTM
	4. Open SpinView software. Check which camera is left (22048634 - cam1) and right (21554508 - cam2) and arrange accordingly
	5. Settings - repeat for both cameras!!:
		○ Set Features > Stream Parameters > Buffer Handling Control > Stream Buffer Handling Mode to Oldest First to avoid dropped frames. NOTE: this setting doesn't seem to get saved between sessions

		○ Set up trigger on Rising edge of TTL pulse: (under Features > Blackfly S BFS-U3-27S5M > Acquisition Control). Optional: set Delay to at least the duration of the QTM exposure (50 us)

		○ Set Settings> Exposure Mode: Timed (ideally make this shorter than the QTM frame interval (e.g. 50 hz -> 18000 us) to avoid  interference from overhead lights)

		○ (Optional) Gain Conversion HCG (High Conversion Gain):

		○ Save as User Set (maybe the same as clicking this button for each camera while stopped under Devices?): 

		○ [To reduce frame buffering: go to Task Manager>Details pane>Right click on spinview.exe and set Priority High]

		
	6. Create a new folder \Hannah\dualcamera\calibration\220310 and copy the subfolders from the template into it
	7. Place checkerboard in view. Take 5 images of a checkerboard in different orientations, simultaneously with both cameras, save as: e.g. Z:\Hannah\dualcamera\calibration\220310\cam1\1.bmp etc.
	8. Place mirror in view. Take images of one IR light (1 = left, 2 = right) at a time, seen simultaneously in both cameras. Save in calibration\220310\lights (total 8 images). For each combination of camera/light source, take two photos:
		a. First with the exposure high (e.g. 6000 ms) to see checkerboard:
cam1_light1_checkerboard.bmp
		b. Then with exposure set to the minimum (19 ms) to see just a point of light:
		cam1_light1.bmp
	9. Place triangle of passive IR markers in view.  Adjust gain so markers are saturated (e.g. 80000). If difficult, can position LED lamp on stepstool behind cameras so that reflectors are directly illuminated.
		- Record a short segment in QTM: calibration\220310\axes\qtm.qtm.
Label markers as p0, px, py and File > Export 3D coordinates to matlab as qtm.mat
		- Record with the cameras (\axes\cam1.bmp and cam2.bmp). Double check that you have recorded both in qtm and with cameras!


## In Matlab:
Process calibration to check it is ok:
addpath(fullfile('C:\Users\Hannah\Dropbox\alab\Code\eyetrack-bird\src'))
filepath_camera = 'Z:\Hannah\eyetrack\calibration\231212';
[C,A] = calibrateCameras(filepath_camera);
(In RUNME.m)



## Example output:
checkerboard	
	



light	
	

axes	
	




## Recording set up
	1. Set QTM to require space bar pressed to start recording (Project Options (gear icon)>Input Devices>Camera System>Synchronization>Wireless/software Trigger>Function=>Start capture)

	2. Scroll down and set QTM Out2 to trigger frames (Project Options>Input Devices>Camera System>Synchronization>Out 2) (e.g. record at 300 fps, but trigger 1/6 of the frames to result in 50Hz video tracking. Set TTL signal polarity Positive. (Currently: Duty cycle doesn't matter. TODO: Set Duty Cycle so that the Pulse Duration equals the Exposure & Flash time?)
	Set exposure time to at least 2 ms less than the ideal frame rate interval (e.g. 14000 us for 60 Hz, 17000 for 50 Hz)

	3. Set up cameras in SpinView to trigger on event input as above ("Set up trigger on QTM TTL pulse")
	
## Recording
	1. ***Don't move anything after axes calibration!***
	2. Place bird in arena with food in front of perch, and markers on head
	3. Click Record in QTM and set correct folder and filename ("Z:\Hannah\eyetrack\behavior\HC13_230525", "qtm.mat"). Don't Start yet
	4. In SpinView, Click Record button for each camera. 
		- Set filename (IND102_220618\cam1 etc - if saving as raw image save to local SSD)
		- Save Options: Capture 0 Frames (0=inf).
		- Click Video tab, set correct Framerate (50 Hz)
		- Mjpeg, Quality 80 (or H264, quality 10,000,000,  (default is 1,000,000))
	5. Hit Record in QTM. Don't press space bar yet
	6. Check exposure settings: Max 1/fps 1000/50 = 20 ms. e.g. 18000, gain 10
	7. Hit record for both cameras in Spinnaker
	8. Then press space bar in QTM to synchronize

Note: Saving in SpinView may fail after a few minutes due to memory usage. 
If it seems to freeze, don't force quit! Ctrl+Shift+Esc and bring the error windows to the front and hit ok. Make sure to stop QTM recording first. 
	
In Matlab:
cd C:\Users\Hannah\Dropbox\alab\Code\eyetrack-bird\scripts


	
# Troubleshooting: check 




Note:
Type	Frames before failure	Resource usage
Mpeg, Quality 80	7500 frames	CPU ~50%, disk low
Mpeg, Quality 90	7100 frames	CPU ~50%, disk low
H264, Bitrate 8,000,000	3400 frames	CPU ~100%, disk low
Uncompressed (.tiff)	1900 frames	
		


# Protocol: analysis
	1. Run D:\hannah\Dropbox\alab\Code\project2\eye\runEyetrackCalib.m
	2. Run __ to analyze eyes
	3. Adjust parameters as needed after selecting a good first frame
	4. Select the beak in each image pair, Collect at least 5-10 images in different configurations

Ground truth experiment
	- Using M660 stage
	- Software here: https://www.pi-usa.us/en/products/precision-motion-controllers-and-drivers-for-positioning-systems/c-8672u2-piline-motion-controller-412418438#downloads
	- See paper for other methods
	- To run bird:
		- Prepare anesthetics, saline in syringe, surgical tools, eye spear, dental rubber bands and applicator, set up motor software +  rigid body markers on motor + calibrate QTM/set up to record
		- Anesthetize with iso + K+X (normal dose, 0.1 ml each)
		- Put in 3D printed ear bars in surgery room
		- Bring here, position in place. Set up motor sequence.
		- If still alive, overdose with another dose
		- Once death is confirmed, cut away skin around one eye using forceps and serrated scissors. Avoid getting feathers in eye or needing to wipe. If necessary, wipe very gently with pre-moistened eye spear
		- Record in 1 deg increments, +- 25 deg. Start qualisys and start video cameras as above, then start motor sequence. Run it 5-6 times in both directions. 
		- Repeat on other eye.



<img width="1388" height="7302" alt="image" src="https://github.com/user-attachments/assets/7171d3b2-1069-4b03-bfba-880b21d7bec5" />
