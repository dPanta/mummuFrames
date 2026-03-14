# Changelog

This changelog keeps `Unreleased` plus the 10 most recent tagged versions.

## Unreleased
- No changes yet.

## 1.8.4 - 2026-03-14
- Restored stable GUID-based party spell-target tracking and `UnitTokenFromGUID` reacquisition.
- Hardened party spell-target source/target checks against Retail secret booleans and clarified the feature's curated Midnight scope.
- Bumped addon metadata to `1.8.4`.

## 1.8.3 - 2026-03-13
- Fixed target, party, and raid out-of-range dimming.
- Hardened range checks against Retail secret booleans and added a lightweight live refresh fallback.
- Bumped addon metadata to `1.8.3`.

## 1.8.2 - 2026-03-13
- Bumped addon metadata to `1.8.2`.

## 1.8.1 - 2026-03-13
- Hardened the Midnight party spell-target tracker against protected-event and secret-value issues.
- Fixed configuration refresh errors and tightened the Frames UI so advanced controls only appear where they matter.
- Kept party target and spell-target warning borders readable while frames are dimmed for range or offline state.
- Removed the dead generated font catalog path and kept bundled fonts local to the shared style module.

## 1.8.0 - 2026-03-13
- Added a Midnight-specific party spell-target tracker that highlights party member frames when curated hostile dungeon casts appear to be targeting them.
- Wired the new tracker into party-frame visuals with a dedicated warning overlay, a lightweight highlight-only refresh path, and a config toggle.
- Documented the Midnight Season 1 seed list and limited spell coverage to mechanics backed by current Midnight cast IDs.
- Reworked the configuration window around top-level `Frames`, `Tracked Auras`, `Global`, and `Profiles` pages instead of flat per-unit tabs.
- Added a grouped Frames hub with left-side unit navigation, consistent per-unit sections, a basic/advanced toggle, reset-to-defaults for individual frame types, and scope-aware refresh intents.
- Polished the Frames page so advanced options only show on relevant panes, simpler units expose direct position controls, and the header toggle text stays inside the configuration window.
- Synced all locale files with the newer configuration keys by seeding missing entries from `enUS`, preserving existing translations and using English fallbacks where translations are still pending.
- Bumped addon metadata to `1.8.0`.

## 1.7.0 - 2026-03-13
- Added generic empowered-spell castbar support with charging-stage markers and event handling for player, target, and focus castbars.
- Rewired live raid frames to use fixed `raid1`-`raid40` secure buttons with deterministic sorting/layout, instead of relying on secure-header child discovery.
- Reworked party and raid out-of-range handling to update from `UNIT_IN_RANGE_UPDATE` instead of waiting for unrelated vitals events.
- Added dedicated lightweight alpha refresh paths for party and raid frames so range changes do not force full unit redraws.
- Centralized group range and protected-boolean handling, and removed the `CheckInteractDistance` fallback to avoid mismatched range dimming.
- Fixed group range updates to register `UNIT_IN_RANGE_UPDATE` as a filtered unit event, which restores live out-of-range dimming on party and raid frames.
- Added a large centered defensive icon for party and raid frames, driven from Blizzard's compact-frame defensive classification and refreshed through the shared aura pipeline.
- Removed the dead legacy party/raid healer-editor config code and stale aura default data that no live UI path used.
- Bumped addon metadata to `1.7.0`.

## 1.6.6 - 2026-03-11
- Fixed secure group-frame unit drift that could make party clicks target the wrong member and cause duplicate or missing group displays.
- Added a Blizzard group leader icon to party and raid unit frames, anchored at the center-left edge to match the existing overlay styling.
- Added party healthbar debuff overlay coloring by debuff type, including typed debuffs the current player cannot dispel.
- Bumped addon metadata to `1.6.6`.

## 1.6.5 - 2026-03-10
- Fixed Enhancement shaman Maelstrom Weapon stacks sticking at `10` after `Tempest` consumed the full aura.
- Filled in the missing `1.6.x` changelog entries and bumped addon metadata to `1.6.5`.

## 1.6.3 - 2026-03-09
- Bumped addon metadata to `1.6.3`.

## 1.6.2 - 2026-03-09
- Follow-up git release cleanup.

## 1.6.1 - 2026-03-09
- Git cleanup for release packaging and bundled assets.

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
