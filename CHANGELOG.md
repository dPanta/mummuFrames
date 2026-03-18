# Changelog

This changelog keeps `Unreleased` plus the 10 most recent tagged versions.

## Unreleased
- No changes yet.

## 2.2.5 - 2026-03-18
- Fixed shared group-event health dispatch so party and raid frames refresh live healthbars correctly again during combat.
- Bumped addon metadata to `2.2.5`.

## 2.2.4 - 2026-03-18
- Slowed the spell-target tracker ticker and the party/raid range fallback tickers to reduce constant combat polling.
- Reworked tracked group-aura matching to use Midnight-safe one-pass aura scans instead of repeated direct spell-name and spell-ID queries.
- Removed the party/raid item-range fallback that could trigger `ADDON_ACTION_BLOCKED` during live group range refreshes.
- Bumped addon metadata to `2.2.4`.

## 2.2.3 - 2026-03-18
- Switched the party-frame summon indicator to Blizzard's default pending-summon icon and stopped resizing it.
- Bumped addon metadata to `2.2.3`.

## 2.2.1 - 2026-03-18
- Filtered shared group-unit event dispatch so party and raid frames do less unnecessary live refresh work.
- Fixed raid-frame absorb overlays so shields render from the current health edge and clamp to missing health.
- Bumped addon metadata to `2.2.1`.

## 2.2.0 - 2026-03-18
- Moved bundled default-profile migration work out of hot runtime getters to reduce combat stutter.
- Fixed combat `ADDON_ACTION_BLOCKED` taint from target and range probes by replacing the unsafe item-range call path.
- Bumped addon metadata to `2.2.0`.

## 2.1.2 - 2026-03-18
- Reworked the addon's factory default state around a bundled `MMFP3` profile seed so new `Default` profiles, fallback profile creation, and per-frame resets all inherit the same imported layout.
- Centralized `MMFP3` decode and sanitization so bundled default seeding and normal profile imports share the same validation path.
- Bumped addon metadata to `2.1.2`.

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
