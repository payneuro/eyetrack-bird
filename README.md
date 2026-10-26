# eyetrack-bird

Dual-camera video oculography plus mocap head tracking for freely moving birds.

Two calibrated cameras and two IR lights are used to measure the 3D pupil center and the
center of corneal curvature on every frame (Barsingerhorn, Boonstra & Goossens 2018,
*Behav Res Meth*). Passive IR markers on the head (measured using a Qualisys motion
capture system) are used to measure head pose. Combining the two gives each eye's
position and optical axis in the head frame, without the animal having to fixate
calibration targets.

Contents: [Hardware](#hardware) · [Software](#software) · [Folder layout](#folder-layout) ·
[Getting started](#getting-started) · [1. Calibration](#1-calibration) ·
[2. QTM setup](#2-qtm-setup) · [3. Recording](#3-recording) · [4. Analysis](#4-analysis) ·
[Coordinate frames](#coordinate-frames)

---

## Hardware

| Part | Model | Notes |
|---|---|---|
| Cameras (2) | Blackfly S BFS-U3-27S5M | |
| Lenses (2) | Edmund Optics 25 mm f/1.4, #59871 | |
| IR LEDs (2) | LUXEON IR Domed 850 nm, LST1-01H01-IR01-01 ([Mouser](https://www.mouser.com/ProductDetail/416-LST101H01IR0101)) | 5 V, 2 A supply, 2 Ω ≥3 W resistor per LED |
| Mirror | Thorlabs ME2S-P01 (front-surface silver) | For locating the LEDs |
| Checkerboard | Uneven size (e.g. ≥4×5), 4 mm squares | `P.square_size` |
| Axes triangle | 3 passive IR markers on a right triangle | `p0` (right angle), `px` (long edge), `py` (short edge); tilted 45° so QTM and the eye cameras both see it |
| Head tracking | Qualisys + head marker rigid body | Must be the first rigid body in the QTM export |

## Software

MATLAB (tested on R2026a) with Computer Vision, Image Processing, Signal Processing, and
Image Acquisition toolboxes plus the GenICam Interface support package; the Spinnaker SDK
(camera driver; SpinView isn't needed); ffmpeg 7.1 (GPU recording); Qualisys Track
Manager (QTM). The GUI's Settings tab marks anything missing and says how to install it.

## Folder layout

The code finds a session's calibration by the six digits after the last underscore in
the session folder name, so name the calibration folder with the recording date.

```
calibration\231212\
  cam1\ cam2\        checkerboard pairs (1.bmp, 2.bmp, ...)
  lights\            cam<N>_light<M>.bmp, cam<N>_light<M>_checkerboard.bmp
  axes\              cam1.bmp, cam2.bmp, qtm.mat (markers p0, px, py)
  calib.mat axes.mat written by calibrateCameras

behavior\HC13_230525\
  cam1.mp4 cam2.mp4  eye videos (or .avi)
  qtm.mat            QTM 6DOF export
  frames_in_view.mat beak.mat eye.mat eye_triangulate.mat   written by the pipeline
  head_calibration.mat                                       results
```

---

## Getting started

1. Plug both cameras into USB 3 and the LEDs into the 5 V supply.
2. `git clone https://github.com/payneuro/eyetrack-bird.git` (or *Code > Download ZIP*).
3. In MATLAB:
   ```matlab
   cd <path to eyetrack-bird>\scripts
   eyetrackGUI
   ```
4. In **Settings**, install anything marked red, set the data roots, and click **Save as
   my defaults**.

## 1. Calibration

Don't move the eye cameras, lights, or QTM cameras after this.

1. Set QTM exposure to 50–80 µs (so the strobes don't reflect in the eye) and calibrate
   QTM.
2. Follow the **Calibration** tab: checkerboard pairs, lights (via the mirror), and the
   axes triangle. Each image is checked as it's saved.
3. For the axes, also record a short QTM segment, label `p0`, `px`, `py`, and export it
   as `axes\qtm.mat`.

   <img src="docs/img/axes_images.png" width="600">

4. When the checklist has no red rows, click **Run calibration**. Reprojection error
   should be well under 1 px, and the QTM and camera triangle sizes should match. Compare
   with the [example output](#example-calibration-output).

## 2. QTM setup

1. *Project Options > Input Devices > Camera System > Synchronization > Wireless/software
   Trigger > Function* = **Start capture**, so QTM waits for the space bar.

   <img src="docs/img/qtm_sync.png" width="650">

2. Same page, **Out 2**: Frequency divisor, positive TTL. QTM rate ÷ divisor = eye-camera
   rate (e.g. 300 ÷ 6 = 50 Hz). The divisor is `downsample_eye` in analysis.

   <img src="docs/img/qtm_out2.png" width="400">

## 3. Recording

1. In the **Record behavior** tab, create the session folder and connect the cameras.
   Keep exposure at least 2 ms below the frame interval.
2. *Compressed* (GPU H.264, ~45 GB/hour) can record straight to Z:.
3. In QTM, start a recording into the session folder named `qtm`. Click **Record** in the
   GUI, then press the space bar in QTM.
4. Stop QTM first, then the GUI. Export the head rigid body (6DOF) as `qtm.mat` in the
   session folder.

## 4. Analysis

In the **Analyze behavior** tab: **Label beak** (first session per bird), **Track eyes**,
**Analyze**. Use **Eyetrack preview** to tune parameters first. The **Birds** tab
combines sessions per bird and plots across birds.

**Analyze** also plots the camera-QTM check: each eye's position in the head against head
yaw, which should be flat. Sloped lines mean the eye cameras moved relative to QTM after
calibration; **Correct offset** fits and removes a horizontal shift plus yaw
(`fitCameraOffset`).

Without the GUI, see [`scripts/RUNME.m`](scripts/RUNME.m). Parameters are in
[`src/eyetrackParams.m`](src/eyetrackParams.m) and
[`src/defaultTrackerParams.m`](src/defaultTrackerParams.m). To redo a step, delete its
file (`calib.mat`/`axes.mat`, `beak.mat`, `eye.mat`). Optional figures are in
`scripts/extras/`.

### Example calibration output

Checkerboard:

<img src="docs/img/out_checkerboard.png" width="700">

Lights (right: top-down view, cameras cyan, lights red/magenta):

<img src="docs/img/out_lights.png" width="700">

Axes (right: triangle from QTM and from the eye cameras, before and after the 45°
correction):

<img src="docs/img/out_axes.png" width="700">

## Coordinate frames

- **Camera** (`C`): origin at camera 1, x along image columns, y down rows, z along the
  optical axis. mm.
- **Common** (`alignCommonReferenceFrame`): origin at `p0`, x toward `px`, rotated 45°
  about x so z is vertical. Camera and QTM data are both mapped into it.
- **Head** (`H.R_head`): x from the eye midpoint to the beak tip, y toward the left eye,
  z up.
- **Angles** (`Ht`): azimuth `theta = atan2d(y, x)`, polar angle `phi = acosd(z/r)`
  (elevation = 90° − phi).
