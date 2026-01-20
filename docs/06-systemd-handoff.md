# systemd Handoff

## systemd as PID 1

systemd requires a properly prepared environment. Failing to do so results in degraded boots or silent failures. 

## Common Failure Symptoms

  * systemctl reports degraded
  * dbus fails to start
  * TTY shows no login



## Required Conditions

  * /dev/null must exist and be writable
  * /dev/console must exist
  * /run must be writable
  * machine-id must exist
  * devpts must be mounted



## Why systemd Was Not Verbose

In a live environment, systemd does not behave exactly like an installed system. 

This is normal and expected. Verbosity depends on: 

  * Kernel command line
  * Logging targets
  * Presence of persistent storage



The key indicator of success is: 
    
    
    systemctl is-system-running
    running
    
