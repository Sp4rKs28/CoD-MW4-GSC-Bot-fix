# MW4 Bot Fix

A GSC script for **Modern Warfare 4 – Beta** that allows you to configure the **number and difficulty of multiplayer bots** directly in the in-game lobby before starting an offline match.

This is the first public release of the project. **Version 1 is a beta:** bots may not always behave correctly, and some features may not work as expected.

## Features

- Allows you to configure the number and difficulty of bots in the in-game lobby.
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
6. Start the game and launch an **offline multiplayer match**. **Configure the number and difficulty of bots in the lobby before starting the match.**

### Example installation path

```text
C:\Games\Modern Warfare 4 - Beta\rex\Assets\Scripts\Custom\mp
```

Use your own game installation directory if it differs from this example. The release's multiplayer scripts should end up inside `Custom\mp`; avoid creating an extra `Custom\Custom` folder.

## Usage

Once installed, configure the number and difficulty of bots in the in-game lobby before starting an offline multiplayer match.

**Set the desired number of bots and their difficulty when creating a new match.**

**Team Deathmatch works best** and is the recommended game mode for this version.

The supplied installation instructions cover offline multiplayer only.

## Known Limitations

- This is a beta release.
- Bots may not always behave correctly.
- Some features may not work perfectly.
- Compatibility across different game builds, maps, modes, or other custom scripts is not guaranteed.

## Troubleshooting

### Bots do not appear

- Confirm that you started an **offline multiplayer match**.
- Make sure you configured the number of bots in the in-game lobby.
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


## Author

Created by **Henrik**.
