# Changelog

## 1.6.1 - 2026-03-09
- Git Cleanup

## 1.6.0 - 2026-03-09
- Brightened the dark-mode health bar backing while keeping the darker primary power backing unchanged.
- Raised the secondary power size limit to `60` and made detached secondary power rows auto-expand their width so larger icons can render correctly.
- Added specialization-specific DK rune icons for the secondary power bar using the addon icon set for Blood, Frost, and Unholy.
- Restricted monk and shaman secondary resources to the specs that actually use them, leaving Chi to Windwalker and Maelstrom Weapon to Enhancement.
- Refreshed several secondary resource icon assets with higher-resolution `50x50` art for cleaner scaling.

## 1.5.0 - 2026-03-09
- Added a party layout setting with proper horizontal secure-header growth for live party frames.
- Hardened party role sorting so headers re-sort on role assignment changes and preview/test ordering mirrors the live tank, healer, dps flow.
- Added optional party role icons using Blizzard role art, including solo/spec fallback behavior and test-mode support.
- Tuned party role icon placement and layering so the icon anchors at the health bar corner without shifting name text or falling behind selection borders.
- Added a black 1-pixel border to detached player bar-style resource elements, covering primary power and tertiary power bars while excluding icon-based secondary resources.
- Extended party defaults, locale strings, and configuration controls for the new layout and role-icon options.

## 1.4.0 - 2026-03-08
- Added a new Global `Dark Mode` toggle stored in profile style settings.
- Recolored health and main power bars to a granite fill with a red-tinted gray empty-bar backing when Dark Mode is enabled.
- Moved class color emphasis from unit bar fills to player name text in Dark Mode while preserving offline and AFK overrides.
- Centralized Dark Mode palette and status-bar backing logic so player, party, and raid frames update consistently through the existing deferred refresh flow.

## 1.3.1 - 2026-03-08
- Cleaned up all locale files and synced them to the current set of live config keys.
- Removed stale locale entries and fallback leftovers from the translation files.
- Bumped addon metadata to `1.3.1`.

## 1.3.0 - 2026-03-08
- Added a dedicated raid frames module with raid layout, spacing, sorting, and test-size support.
- Fixed party buff handling and expanded aura tracking for party and raid members.
- Extended the configuration UI for raid and aura options, and added the addon icon asset.

## 1.2.3 - 2026-03-04
- Fixed party out-of-range detection so units are not dimmed when the game cannot reliably check their range.
- Updated party range logic to handle both `UnitInRange` API return styles safely.

## 1.2.2 - 2026-03-03
- Added a breath bar for the player by reusing the primary power bar while underwater.
- Improved range safety checks in party frames to better handle uncertain API results.

## 1.2.1 - 2026-03-01
- Fixed follower dungeon party handling across home and instance group categories.
- Improved secure visibility refresh behavior for dynamic unit frames after combat.
- Tightened party roster detection and self-display logic for edge-case group states.
