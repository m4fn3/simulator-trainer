# simulator-trainer

Drop an iOS tweak .deb file onto a Simulator to install it  

<img src="./img/flex_install.gif" width="100%">

## Usage

1. Download/build an iOS tweak `.deb`.
2. Boot a Simulator with **simulator-trainer**.  
3. Drop the file onto the sim window and wait for a respring.

![Installing tweak status](./img/jb0.png) ![Tweak installed status](./img/jb1.png)


## What it does
* Turns Simulator.app into a dylib and dlopens it for in-process swizzling.  
* Mounts a writable `tmpfs` overlay on the simulator runtime.  
  *(one simruntime per iOS version, shared by every device model)*.  
* Injects a loader into `libobjc.A.dylib` to start tweaks.  
*  Installs tweaks inside the overlay; non-sim binaries are auto-converted during install.
