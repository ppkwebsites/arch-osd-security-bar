# System Security OSD for Quickshell

A sleek, sidebar-style **On-Screen Display (OSD)** built with Quickshell for Arch Linux. This tool provides a real-time security overview of your system, specifically designed for use with Wayland compositors like Hyprland.

---

### Key Features

* **Network Monitoring**: Displays real-time download/upload speeds and your current local IP address.
* **Firewall Status**: Checks if **UFW** (Uncomplicated Firewall) is installed and active.
* **Malware Protection**: Monitors **ClamAV** services, including the daemon, freshclam, and real-time monitoring (clamonacc).
* **Update Tracker**: Monitors Arch Linux system updates, showing the last update date and the number of pending packages.
* **Interactive Controls**: Includes "Copy" buttons for common terminal commands and quick links to security resources.

---

### Installation & Setup

1. **Dependencies**: Ensure you have the following installed on your Arch system:
   * `quickshell`
   * `networkmanager` (for `nmcli` checks)
   * `wl-clipboard` (for `wl-copy` to work)
   * `pacman-contrib` (for `checkupdates`)

2. **Placement**: Move the `SecurityBar` folder to your config directory:
   * `~/.config/quickshell/SecurityBar/`

3. **Permissions**: Make sure the toggle script is executable:
   ```bash
   chmod +x ~/.config/quickshell/SecurityBar/SecurityBar.sh

How to Use
Using the Toggle Script
The included SecurityBar.sh script acts as a toggle. When run, it checks if the OSD is already open; if it is, it kills the process, otherwise it launches it.

Integration with Hyprland
To use this OSD, map the script to a keybinding in your hyprland.conf.

Add the following line to your ~/.config/hypr/hyprland.conf:

Bash
# Toggle System Security OSD (Example using Super + S)
bind = $mainMod, S, exec, ~/.config/quickshell/SecurityBar/SecurityBar.sh
