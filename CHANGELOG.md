# Changelog

This changelog keeps `Unreleased` plus the 6 most recent tagged versions.

## Unreleased

## 3.6.0 - 2026-04-23
- Reworked the Protection warrior Ignore Pain tertiary bar around a simpler visual absorb flow so the combat bar follows live absorb updates without relying on protected combat percent math.
- Removed the unreliable Ignore Pain combat text path and cleaned out the extra cast-grace, polling, and statusbar-readback fallbacks that had accumulated while debugging it.
- Hid the temporary `IP` label so the Ignore Pain bar now renders as a visual-only absorb indicator.
- Fixed the AuraHandle shared-unit comparison taint by routing `UnitIsUnit()` secret booleans through the existing safe truthy guard.
- Bumped addon metadata to `3.6.0`.

## 3.5.1 - 2026-04-16
- Fixed the dark overlay that darkened incoming-cast-board bars by removing the redundant status-bar background texture and the text/target panel layers that bled through the semi-transparent fill.
- Fixed targeted spells configuration slider alignment so chained sliders no longer drift progressively to the right.
- Added test-mode support for the incoming cast board, showing three sample bars with dummy spell names, target names, and class colors when test mode is active.
- Fixed test-mode cast bars not disappearing when test mode is toggled off.
- Fixed configuration checkboxes and controls across all lazily-built tabs not reflecting saved values after a reload by syncing widget state whenever a tab is selected.
- Bumped addon metadata to `3.5.1`.

## 3.5.0 - 2026-04-16
- Fixed party and raid dispel overlay fallbacks to use the player's actual known dispel spells and talents instead of a coarse class-only table.
- Stopped the bottom-right group dispel icon from guessing `Magic` when Midnight omits an aura's exact dispel type, so the overlay stays visible without lying about the type icon.
- Rebuilt targeted enemy-cast tracking around a new Danders-style party cast list that watches hostile nameplate casts generically instead of relying on a curated spell whitelist.
- Removed the old per-frame spell-target border highlight flow and replaced it with a party-attached incoming cast board that avoids exact party-member target resolution and comparison-heavy secret-value handling.
- Cleaned out the legacy tracker module, old spell-target config/docs, and the remaining border-highlight wiring so the new list owns the full targeted-cast path end to end.
- Bumped addon metadata to `3.5.0`.

## 3.4.1 - 2026-04-11
- Fixed Blizzard pet-frame suppression so the global hide option now also covers the default `PetFrame`.
- Reapplied Blizzard pet-frame hiding on pet/spec updates and hardened the hide hook against later alpha resets, which fixes Beast Mastery cases where the default pet frame could reappear with two pets active.
- Bumped addon metadata to `3.4.1`.

## 3.4.0 - 2026-04-09
- Added custom boss frames for `boss1` through `boss5`, including shared live/test refresh handling and support for hiding the Blizzard boss frames.
- Added a dedicated `Boss` page to the Frames configuration under a new `Encounter` group, with shared controls for boss-frame size, spacing, position, text, auras, and Blizzard-frame replacement.
- Added primary resource-bar support to the boss frame set and stacked the boss frames from one shared layout so edit-mode repositioning moves the whole group cleanly.
- Bumped addon metadata to `3.4.0`.

## 3.3.2 - 2026-04-09
- Fixed outlined text refreshes on unit-frame name/health text and castbar text so `target`, `targettarget`, `focus`, and `focustarget` now keep their configured outline styling.
- Fixed appearance-only refreshes so shared font changes reapply immediately on unit frames instead of waiting for a later full layout refresh.
- Bumped addon metadata to `3.3.2`.

## 3.3.1 - 2026-04-09
- Added clockwise swipe countdowns to tracked self-cast HoT and aura indicators on party and raid frames, including both icon and corner-square displays.
- Hardened tracked-aura cooldown rendering against Midnight secret-value wrappers by keeping timer math on the existing safe aura-number path and avoiding new taint-prone aura queries.
- Bumped addon metadata to `3.3.1`.

## 3.3.0 - 2026-04-06
- Added a player secondary-resource display mode switch so supported resources can render as the existing icons or as a segmented bar.
- Added segmented secondary-bar sizing controls, attached in-frame placement for segmented mode, and detached movable/snappable secondary bars in Blizzard Edit Mode.
- Added segmented-bar support for the supported secondary resource set, including death knight runes, monk chi, rogue and feral combo points, and Enhancement shaman Maelstrom Weapon stacks.
- Fixed the player-frame configuration page crash triggered by the new secondary power style selector.
- Refined secondary resource visuals so icon mode no longer picks up an extra border and segmented mode uses a thin outline with aligned right-edge sizing and even segment spacing.
- Bumped addon metadata to `3.3.0`.
