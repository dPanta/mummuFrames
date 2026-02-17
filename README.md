# mummuFrames
Unitframes addon for World of Warcraft. Minimal, core functionalities, basic customization. Aimed at visual clarity and speed (hopefully).

# What it does:
- Player, Target, Targets Target, Focus, Focus Target unit frames (no party or raid frames yet)
- Very basic buff tracking. If turned off (i prefer running no buffs on unit frames), it wont do any buff logic (only some debuff aura logic)
- Cast bar (detachable) of Player, Target and Focus unit frame.
- Basic configuration options (sharedMedia or inbuild textures/fonts).
- Edit Mode compatible (with snaping)
- Power and Secondary power bars/icons (bars for primary power like mana, icons for most secondary powers...chi, runes...etc.).
- libSharedMedia integration should work as well
- Stagger bar for brewmaster monks (coloring per light/med/heavy)
- Ironfur stacking/overlaping bars with glows and stack text

# How to use:
- A blue M icon will appear in minimap
- You can also use a chatcommand:  /mmf

# Idea
The whole idea behind these is simplicity and hopefully performance. No overly complex configuration, no complex logic.

# Still thinking about you
Still wondering about adding party/raid frames, because on these it is really important to have proper buff/debuff logic in-place with extensive buff/debuff configuration for healers to be able to play the game properly. Which would add a lot of overhead to the main frames and I do want to keep those as minimal as possible (because I think I dont need any more information out of these).