# MW4 Bot Fix

A GSC script for **Modern Warfare 4 – Beta** that makes **multiplayer bots** work in offline matches. Set the number of bots and their difficulty in the in-game lobby, and control the bots and your own player during the match with the in-game **BOTFIX settings menu**.

## Features

- **Lobby bots:** configure the number and difficulty of bots in the in-game lobby.
- **More than 6 bots:** bots no longer stand still for the whole match when many bots are in the match.
- **Replacement bots:** after a map restart or a new match, the mod adds bots that match your lobby (count, teams, difficulty).
- **BOTFIX settings menu** in *Settings > Debug Options*, usable during the match:

**BOTFIX: PLAYER**
| Setting | Options |
|---|---|
| Advanced UAV | On / Off: every enemy on your minimap for the whole match |
| My Health | Default, 150, 200, 300, 500, Invulnerable |
| Unlimited Ammo | Off / On |
| Movement Speed | Normal, 110 %, 125 %, 150 % |
| My Skin | Your own operator skin |
| Reset All Settings | Sets every BOTFIX setting back to its default |

**BOTFIX: BOTS**
| Setting | Options |
|---|---|
| Friendly / Enemy Bot Difficulty | Lobby Setting, Recruit, Regular, Hardened, Veteran |
| Friendly / Enemy Bot Health | Default, 50, 150, 200, 300 |
| Freeze Bots | Bots stop moving, aiming and shooting |
| Bot Unlimited Ammo | Bots never run out of ammo |
| Bot Weapon Class + "… for Bots" | Allow or block a weapon class for bots |
| Bot Fixed Weapon | Every bot gets the same primary weapon |
| Replacement Bots | Auto (like the lobby), Off, or a fixed count |
| Headshots Only | Training mode: bots only take damage from your headshots |
| Bot Respawn Delay | Default, Instant, 1, 2, 3, 5, 10, 15 s |
| Bot Names | Default or your own name list |

**BOTFIX: BOT SKINS**
| Setting | Options |
|---|---|
| Bot Skins | Game Default, Custom (keep for the match), Custom (new every respawn) |
| Allies / Axis Bot Skin | One skin for a whole team, or random from the pool |
| Pool Skin + "… in Pool" | Allow or block single skins for random picks |
| Single Bot + "Skin of Bot N" | Give one bot its own skin |

In Free-for-All every bot counts as an enemy.

## Requirements

- A Modern Warfare 4 – Beta installation with the `rex\Assets\Scripts` and `rex\Assets\Lua` folders.
- The release ZIP from this repository's **Releases** section. It contains the `Custom` and `Lua` folders.

These instructions are intended for the game installation described below. Compatibility with other builds has not been established.

## Installation

1. **Close the game.**
2. Download the release ZIP from this repository's **Releases** section and extract it.
3. If you already have custom scripts installed, back up any files that would be overwritten.
4. Copy the extracted **`Custom` folder** into your game's **`rex\Assets\Scripts`** folder. Merge the folders and replace the existing files if prompted.
5. Copy both files from the extracted **`Lua` folder** into your game's **`rex\Assets\Lua`** folder. If you already made your own bot name list (`mw4_botfix_names_post.lua`), keep yours.
6. Start the game and launch an **offline multiplayer match**. **Configure the number and difficulty of bots in the lobby before starting the match.** You will see `MW4 Botfix v1.2 loaded`.

### Example installation paths

```text
C:\Games\Modern Warfare 4 - Beta\rex\Assets\Scripts\Custom\mp
C:\Games\Modern Warfare 4 - Beta\rex\Assets\Lua
```

Use your own game installation directory if it differs from this example. The multiplayer scripts should end up inside `Custom\mp`; avoid creating an extra `Custom\Custom` folder. The Lua files go directly into `rex\Assets\Lua`.

## Usage

Set the number of bots and their difficulty in the in-game lobby, then start an offline multiplayer match.

During the match, open **Settings > Debug Options** and scroll down to **BOTFIX**. The settings only work during a match. They stay active for the following matches until you restart the game.

**Team Deathmatch works best** and is the recommended game mode.

The supplied installation instructions cover offline multiplayer only.

## Custom Bot Names

1. Open `rex\Assets\Lua\mw4_botfix_names_post.lua` in a text editor and write your names into the list.
   Use letters, digits, spaces and `_`. Names can have up to 20 characters, and the list can hold up to 32 names.
2. Restart the game, start a match and set **Bot Names** to **Custom**.

Only bots the mod adds itself get these names. Those are the replacement bots after a map restart or a new match. Bots from the lobby keep their names.

## Known Limitations

- All BOTFIX settings go back to their defaults when you restart the game.
- *Instant* respawn still waits for the short death animation, about 1.75 s. The respawn delay has no effect in modes with limited lives or wave respawns.
- In team modes, a skin from the other team may not show on a bot.
- Bots may not always behave correctly.
- Compatibility across different game builds, maps, modes, or other custom scripts is not guaranteed.

## Troubleshooting

### Bots do not appear

- Confirm that you started an **offline multiplayer match**.
- Make sure you configured the number of bots in the in-game lobby.
- Check that you copied the release's `Custom` folder into `rex\Assets\Scripts` in the correct game installation.
- Check that the multiplayer scripts are inside `Custom\mp`, without an extra nested `Custom` folder.
- Close the game completely before reinstalling the script, then restart it.

### The BOTFIX menu does not appear

- Check that `mw4_botfix_menu_post.lua` is directly inside `rex\Assets\Lua`. The file name must end with `_post.lua`.
- Restart the game completely after copying the files.

### Settings have no effect

- The settings only work during a match. In the main menu they show the note *"Works only during a match."*
- Check that all three `.gscc` files from the release are inside `rex\Assets\Scripts\Custom\mp`.

### Problems after installation

- Check whether another custom script replaces or modifies the same files.
- Temporarily disable potentially conflicting scripts and try again.
- Restore your backed-up files to check whether the issue also occurs without this script.
- If the issue persists, report it with the details listed below.

## Source Code

This repository contains the source code of the current version:

| File | Purpose |
|---|---|
| `mw4_addbot.gsc` | Bot behaviour: movement, combat, lobby bots |
| `mw4_botfix_menu.gsc` | Server side of the BOTFIX settings menu |
| `mw4_bot_fallback.gsc` | Replacement bots, the more-than-6-bots fix, custom bot names |
| `mw4_botfix_menu_post.lua` | The BOTFIX settings menu |

The compiled scripts (`.gscc`) are in the release ZIP.

## Bug Reports and Feedback

Report bugs or suggestions through this repository's **Issues** tab, if enabled. Include:

- The script version and game build.
- The map and game mode.
- Steps to reproduce the problem.
- What you expected to happen and what actually happened.
- Any other custom scripts you have installed.
- Screenshots, error messages, or logs, if available.

## Author

Created by **SparKs**.
