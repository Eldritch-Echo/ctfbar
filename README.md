# CTFBar

> A lightweight XFCE panel utility for CTF and pentesting workflows.

CTFBar is a small utility designed to keep the most important information of a CTF or pentesting session visible directly on the XFCE panel.

It provides quick terminal commands to set the current target and contextual information, while displaying both values in the panel with click-to-copy functionality.

## Features

-  Display the current CTF target directly on the XFCE panel
-  Display contextual information
-  Click-to-copy target and information
-  Clear target or information independently
-  Clear both values with a single command
-  Automatic XFCE panel configuration
-  Automatically places CTFBar next to the CPU Graph when available
-  Creates backups of the XFCE panel configuration
-  Installation rollback on failure
-  Clean and selective uninstallation
-  ZSH integration

## Requirements

- `XFCE`
- `ZSH`
- `Python 3`
- `xfce4-genmon-plugin`
- `xclip`
- `libnotify-bin`

The installer automatically checks for and installs the required packages.

## Installation

Clone the repository:

```bash
git clone https://github.com/Eldritch-Echo/ctfbar.git
cd ctfbar
```

Make the scripts executable:
```
chmod +x install.sh uninstall.sh
```

Run the installer:
```
./install.sh
```

The installer will:

- Check the environment 
- Install missing dependencies 
- Create the CTFBar configuration directory 
- Add the required ZSH functions 
- Create the XFCE panel plugins 
- Position CTFBar next to the CPU Graph when available 
- Verify the resulting panel configuration 
- Create backups for recovery 

## Usage

Set target
```
settarget 10.10.10.11
```

Set information
```
setinfo Web server
```

You can use any text that is useful during an engagement or CTF:
```
setinfo Port 8080 - Jenkins
```

Clear target
```
cleartarget
```

Clear information
```
clearinfo
```

Clear both
```
clearbars
```

## Click to copy

Both values displayed in the XFCE panel can be clicked to copy their contents to the clipboard.

This is especially useful when repeatedly switching between:

- IP addresses
- Hostnames
- Ports
- URLs
- Credentials discovered during a lab
- Notes and enumeration findings

## Uninstallation

Run:
```
./uninstall.sh
```

The uninstaller:

- Removes only the plugins created by CTFBar
- Restores the XFCE panel configuration
- Removes the CTFBar block from .zshrc
- Creates backups before modifying configuration
- Optionally removes the CTFBar configuration directory

CTFBar does not remove or modify unrelated XFCE panel plugins.

## Safety

CTFBar is designed to avoid modifying existing XFCE panel configuration unnecessarily.

Before changing the panel, the installer stores the original plugin configuration and verifies the resulting plugin array after installation.

If installation fails, CTFBar attempts to roll back the changes automatically.

## Project structure

```
ctfbar/
├── install.sh
├── uninstall.sh
├── README.md
├── LICENSE
└── .gitignore
```

## Why?

During CTFs and pentesting labs, the target IP or a small piece of contextual information is often copied and reused constantly.

CTFBar was created to keep that information visible and immediately accessible without having to repeatedly search through terminal history, notes, or multiple terminal windows.

# Author

EldritchEcho

Built for CTFs, pentesting labs and security learning.

#### License

This project is licensed under the MIT License.
