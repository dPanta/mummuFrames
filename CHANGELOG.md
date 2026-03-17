# Changelog

This changelog keeps `Unreleased` plus the 10 most recent tagged versions.

## Unreleased
- No changes yet.

## 2.1.1 - 2026-03-17
- Fixed target and targettarget out-of-range fading for opposite-faction player targets in city or sanctuary cases where item probes do not resolve, by restoring a narrow out-of-combat interact fallback for that player-only edge case.
- Rebuilt profile import/export around a single compressed `MMFP3` format, fixed the broken export path, and made active-profile imports refresh live frames and tracked aura state immediately.
- Hardened party and raid out-of-range fading so noisy `UNIT_IN_RANGE_UPDATE` payloads or ambiguous group-range API returns no longer leave the whole group dimmed.
- Bumped addon metadata to `2.1.1`.

## 2.1.0 - 2026-03-17
- Fixed raid frame health and absorb handling under Midnight secret values.
- Restored out-of-range fading for party, raid, target, targettarget, focus, and focustarget.
- Bumped addon metadata to `2.1.0`.

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
