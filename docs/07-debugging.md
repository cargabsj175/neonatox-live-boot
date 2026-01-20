# Debugging and Lessons Learned

## Most Important Lessons

  * Do not assume devices exist
  * sysfs tells the truth
  * /dev problems surface later in systemd
  * dbus errors are often /dev or /run issues



## Why This Took Iteration

Live boot systems fail silently. Most issues only appear several stages later. 

The only reliable way to build one is iterative testing. 

## Final Result

Neonatox Live Boot successfully demonstrates: 

  * A minimal initramfs
  * Reliable media detection
  * Correct systemd handoff
  * A clean, writable live environment



Most importantly, it is understandable. 
