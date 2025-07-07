# simulator-trainer

Simulator tweak injection and helpers

## Usage

Drag an iOS app or tweak .deb file into a Simulator to install it

1. Download/build an iOS app or iOS tweak (`.deb`).
2. Boot a Simulator with **simulator-trainer**.  
3. Drop the file onto the sim window and wait for a respring.

![Installing tweak status](./img/jb0.png) ![Tweak installed status](./img/jb1.png)


## What it does
* Turns Simulator.app into a dylib and dlopens it for in-process swizzling.  
* Mounts a writable `tmpfs` overlay on the simulator runtime.  
  *(one simruntime per iOS version, shared by every device model)*.  
* Injects a loader into `libobjc.A.dylib` to start tweaks.  
*  Installs tweaks inside the overlay; non-sim binaries are auto-converted during install.

---

#### install ios tweaks

![libobjsee](./img/flex_install.gif)

---

#### install ios apps

![libobjsee](./img/app_install.gif)

---

#### trace objc_msgSend

![libobjsee](./img/tracing.gif)

---

#### cycript

![cycript](./img/cycript.gif)