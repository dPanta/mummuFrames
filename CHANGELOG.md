# Changelog

This changelog keeps `Unreleased` plus the 10 most recent tagged versions.

## Unreleased
- No changes yet.

## 2.0.3 - 2026-03-16
- Shortened the Profiles page activate button text so it fits cleanly in the config UI.
- Localized the remaining profile and configuration strings across non-English locale files.
- Bumped addon metadata to `2.0.3`.

## 2.0.2 - 2026-03-15
- Changed profile storage to be character-local, so profile lists and active selections no longer bleed across the whole account.
- Added a one-time migration that copies legacy account-wide profiles into each existing character's local profile set while preserving that character's selected profile when possible.
- Updated the Profiles page copy to explain the new per-character behavior and position export/import as the way to move layouts between characters.
- Bumped addon metadata to `2.0.2`.

## 2.0.1 - 2026-03-15
- Fixed tracked priest buffs so `Atonement` and `Prayer of Mending` use the same explicit spellID-driven fallback path as `Renewing Mist`, including broader `Prayer of Mending` aura alias coverage.
- Hardened tracked-buff matching against Midnight ownership metadata gaps by trusting direct override-family spellID hits without touching the dedicated debuff cache.
- Fixed a Lua scoping bug in the group debuff overlay helper that could call `isGroupAuraFilteredIn` before it was defined.
- Removed the target-frame `CheckInteractDistance` fallback that could trigger `ADDON_ACTION_BLOCKED` during secure target changes.
- Bumped addon metadata to `2.0.1`.

## 2.0.0 - 2026-03-15
- Refactored party and raid debuff tracking around a dedicated Midnight-safe `UNIT_AURA` cache built from `C_UnitAuras` slot scans and delta updates, instead of relying on hidden Blizzard compact-frame aura state.
- Added configurable party and raid debuff icon rows, while keeping the regular unit-frame debuff strips dispel-agnostic.
- Restored dispellable group-frame overlays for party and raid frames, including fallback handling for Midnight aura payloads that omit complete dispel metadata.
- Hardened aura icon rendering against Retail secret-value taint by sanitizing icon textures, stack counts, and cooldown timing before they reach the UI.
- Reworked aura tracking for Atonement and Prayer of Mending.
- Cleaned up the new debuff pipeline comments and bumped addon metadata to `2.0.0`.

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
