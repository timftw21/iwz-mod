![license](https://img.shields.io/github/license/h1-mod/iw7-mod.svg)
[![open bugs](https://img.shields.io/github/issues/h1-mod/iw7-mod/bug?label=bugs)](https://github.com/h1-mod/iw7-mod/issues?q=is%3Aissue+is%3Aopen+label%3Abug)
[![discord](https://img.shields.io/discord/945420505157083208?color=%237289DA&label=members&logo=discord&logoColor=%23FFFFFF)](https://discord.gg/RzzXu5EVnh)
<!--
[![Build](https://github.com/h1-mod/h1-mod/workflows/Build/badge.svg)](https://github.com/h1-mod/h1-mod/actions)
[![Build status](https://ci.appveyor.com/api/projects/status/0sh80kdnsvm53rno?svg=true)](https://ci.appveyor.com/project/h1-mod/h1-mod)
-->

# IWZ-MOD

IWZ-MOD is a Zombies-focused fork of IW7-Mod for Call of Duty®: Infinite Warfare. It builds on IW7-Mod with Zombies gameplay fixes, tweaks, HUD and menu improvements, custom lobby music, and quality-of-life features.

IWZ-MOD 0.5 adds Arcade Attack survival mode, expands Zombies progression and HUD options, improves third-person aiming and map interactions, and fixes inventory, records, localization, power-up, and Pack-a-Punch presentation issues. To install it, download the [latest release](https://github.com/timftw21/iwz-mod/releases/latest) and extract `iw7-mod.exe` and the `iw7-mod` folder into the Infinite Warfare installation directory. A legal Steam copy of the game is required.

# IWZ-MOD To-Do

 - Fate and Fortune machine still needs to be implemented into survival maps
 - Certain fixes are only partially implemented (alien fuse interaction on Attack, gun laser behavior, etc.)
 - Allow custom music to be queued by the DJ in Zombies in Spaceland
 - Certain tweaks to how custom music behaves in the pre-game lobby
 - Certain vanilla hintstrings should be tweaked
 - Option to bypass map intro cinematics
 - The next survival map, Rave in the Redwood's "Island Panic!" (gotta think of an alliteration💀)
 - More map-specific fixes and tweaks
 - Fix crawler bug (they sometimes lose collision)

# IWZ-MOD Changes

General
 - Removed most IW7-MOD branding
 - Tweaks that improve performance on modern hardware
 - Added client options, such as player name, name color, skipping intro cinematics, pause on focus lost, mute on focus lost, and XP rate
 - Added zombies-specific options, such as camera perspective options, HUD options, and an in-game timer for all modes
 - A variety of fixes and tweaks to the Zombies' menus
 - Survival mode: IWZ-MOD's take on Black Ops 7 Zombies' survival maps; first survival map is "Arcade Attack!"
 - Ghosts 'N Skulls Arcade: select Ghosts 'N Skulls games without completing their tedious in-game steps
 - CAST button allows the player to choose their character
 - Power-ups now spawn more frequently (will probably require some more adjustments)
 - Levels 1-999 now take 10% less XP
 - Sprinting zombies are now slightly slower
 - Interactions with traversing zombies do not push the player like a fucking bouncy ball anymore
 - General improvements to zombie collision and interactions (it's not perfect, but it's better!)
 - Climbing ladders and other objects is now significantly faster
 - In-game pause menu now displays a weapon XP widget
 - The match summary now displays cards for weapon levels and unlocked calling cards
 - Calling cards now display within in-game challenge notifications to indicate that you've completed the highest tier for a challenge
 - Certain calling card challenge requirements have been eased (some of them were clearly meant to pad the game's lifecycle)
 - XP rewards for completed challenges are now more generous
 - Custom lobby music is now supported; drag supported files into iw7-mod\custom_music to bring them in-game
 - Red-screen visual is less intrusive

Zombies in Spaceland
 - Small tweaks and fixes to the HUD
 - The SETICOM now takes 15 hits instead of 10 hits
 - Alien fuses now persist after first installation
 - Zombies now ignore the player while playing arcade games

Rave in the Redwoods
 - Boat speed to PaP island is now much faster (you're welcome)
 - Removed perk penalty from failing EE steps
 - Other miscellaneous tweaks and fixes

Shaolin Shuffle
 - Ninja zombies no longer teleport; base ninja zombie speed has been increased by 15%
 - The Banshee at spawn no longer clips through the bench
 - Other miscellaneous tweaks and fixes

Attack of the Radioactive Thing
 - Certain objects are now easier to interact with
 - Other miscellaneous tweaks and fixes

The Beast from Beyond
 - Phantom floppy disk now has VFX to better indicate its location
 - The OSA assault rifle now has more starting ammo
 - Certain objects are now easier to interact with
 - Other miscellaneous tweaks and fixes

# IW7-Mod

IW7-Mod is a client for Call of Duty®: Infinite Warfare that adds dedicated servers, hands-on modding utilities, and custom mods that feature content like weapons, models, sounds, and more. ***You must legally own [Call of Duty®: Infinite Warfare](https://store.steampowered.com/app/292730/Call_of_Duty_Infinite_Warfare/)*** to run this mod. Unlicensed or cracked versions of the game are **NOT** supported and will not be given assistance.

<p align="center">
  <img src="assets/github/banner.png?raw=true" width="500" height="500" />
</p>

## Download

To download IW7-Mod, [read our Installing IW7-Mod guide](https://docs.auroramod.dev/iw7-install) to help you.

## Compile from source code

- Clone the Git repo via [Git](https://git-scm.com/install/windows) or [GitHub Desktop](https://desktop.github.com/download/). **DO NOT download it as ZIP** as it will not work.
- Run the `generate.bat` script to generate the project solution.
- Build the project via the generated solution file in `build\iw7-mod.sln`.

## Credits

- [s1x-client](https://git.alterware.dev/alterware/s1-mod) *(now **s1-mod**)* - codebase and research
- [h1-mod](https://github.com/auroramod/h1-mod) - extended work and research
- [h2-mod](https://github.com/alicelys/h2-mod) - research
- [momo5502](https://github.com/momo5502) - Arxan & Steam research, former lead developer of [XLabsProject](https://github.com/XLabsProject)

## Disclaimer

This software has been created purely for the purposes of academic research. It is not intended to be used to attack other systems. Project maintainers are not responsible or liable for misuse of the software. Use responsibly.
