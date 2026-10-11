# MW4 Bot Fix

A GSC script for **Modern Warfare 4 – Beta** that automatically adds **11 multiplayer bots** when you start an offline match.

This is the first public release of the project. **Version 1 is a beta:** bots may not always behave correctly, and some features may not work as expected.

## Features

- Automatically adds 11 bots to an offline multiplayer match.
- Installs through the game's `Custom` scripts folder.

## Requirements

- A Modern Warfare 4 – Beta installation with the `rex\Assets\Scripts` folder.
- The release ZIP containing the `Custom` folder.

These instructions are intended for the game installation described below. Compatibility with other builds has not been established.

## Installation

1. **Close the game.**
2. Download the release ZIP from this repository's **Releases** section and extract it.
3. If you already have custom scripts installed, back up any files that would be overwritten.
4. Copy the extracted **`Custom` folder** into your game's **`rex\Assets\Scripts`** folder.
5. Merge the folders and replace the existing file if prompted.
6. Start the game and launch an **offline multiplayer match**. **11 bots will be added automatically.**

### Example installation path

```text
C:\Games\Modern Warfare 4 - Beta\rex\Assets\Scripts\Custom\mp
```

Use your own game installation directory if it differs from this example. The release's multiplayer scripts should end up inside `Custom\mp`; avoid creating an extra `Custom\Custom` folder.

## Usage

Once installed, start an offline multiplayer match to use the script. Bot spawning is automatic; no manual spawning step is required.

**Do not manually add bots when creating a new match.** The script automatically adds all 11 bots for you.

**Team Deathmatch works best** and is the recommended game mode for this version.

The supplied installation instructions cover offline multiplayer only.

## Known Limitations

- This is a beta release.
- The bot count is currently fixed at **11** and cannot be adjusted.
- Bots may not always behave correctly.
- Some features may not work perfectly.
- Compatibility across different game builds, maps, modes, or other custom scripts is not guaranteed.

## Troubleshooting

### Bots do not appear

- Confirm that you started an **offline multiplayer match**.
- Check that you copied the release's `Custom` folder into `rex\Assets\Scripts` in the correct game installation.
- Check that the multiplayer scripts are inside `Custom\mp`, without an extra nested `Custom` folder.
- Close the game completely before reinstalling the script, then restart it.

### Problems after installation

- Check whether another custom script replaces or modifies the same files.
- Temporarily disable potentially conflicting scripts and try again.
- Restore your backed-up files to check whether the issue also occurs without this script.
- If the issue persists, report it with the details listed below.

## Bug Reports and Feedback

Report bugs or suggestions through this repository's **Issues** tab, if enabled. Include:

- The script version and game build.
- The map and game mode.
- Steps to reproduce the problem.
- What you expected to happen and what actually happened.
- Any other custom scripts you have installed.
- Screenshots, error messages, or logs, if available.

## Release Notes

### v1 — Initial Public Release

- First public version of MW4 Bot Fix.
- Automatic spawning of 11 bots in offline multiplayer matches.
- Beta release for testing and feedback.

## Author

Created by **Henrik**.
