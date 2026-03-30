# Changelog

This changelog keeps `Unreleased` plus the 10 most recent tagged versions.

## Unreleased
- No changes yet.

## 3.1.0 - 2026-03-31
- Made tracked-aura configuration character-specific instead of storing it with profile snapshots, and stopped profile import/export from carrying tracked aura entries.
- Added per-entry tracked-aura X/Y offset controls and applied those offsets to both icon-strip and square indicators.
- Fixed the tracked-aura editor RGB sliders so they align vertically instead of drifting farther right down the form.
- Added matching raid `Ready` and `Pull` action buttons above raid frames for leaders and assistants, including edit-mode preview and selection-bounds support.
- Bumped addon metadata to `3.1.0`.

## 3.0.0 - 2026-03-27
- Bumped addon metadata to `3.0.0`.

## 2.6.1 - 2026-03-26
- Fixed the post-`2.6.0` range regression so explicit group range events drive party/raid fading again without forcing observed unit frames permanently out of range.
- Bumped addon metadata to `2.6.1`.

## 2.6.0 - 2026-03-26
- Fixed group range evaluation so party and raid frames treat checkable `UnitInRange` misses as truly out of range instead of silently failing open.
- Bumped addon metadata to `2.6.0`.

## 2.5.1 - 2026-03-26
- Fixed party and raid out-of-range fading after the event-driven range rewrite by handling `UNIT_IN_RANGE_UPDATE` refreshes even when Midnight does not provide a stable unit token payload.
- Hardened unit-frame font fallback so outlined text stays consistent even when the preferred font path cannot be assigned directly.
- Bumped addon metadata to `2.5.1`.

## 2.5.0 - 2026-03-25
- Added centered Blizzard ready-check indicators to unit, party, and raid frames.
- Added leader-only `Ready` and `Pull` action buttons above the party frame, with `Pull` starting `/pull 9` and falling back to the Blizzard countdown API when needed.
- Restyled the party leader action buttons with a custom modern look and included their preview/selection area in the party frame's edit-mode element.
- Fixed the raid ready-check refresh path so it no longer trips a nil-function error during `READY_CHECK`.
- Fixed custom leader action button label setup so the buttons initialize their font before setting text.
- Bumped addon metadata to `2.5.0`.

## 2.4.1 - 2026-03-24
- Fixed raid-frame absorb shields so full-health targets still show a visible shield cue, and hardened the first overlay refresh against unresolved raid health-bar widths.
- Bumped addon metadata to `2.4.1`.

## 2.4.0 - 2026-03-23
- Reworked tracked group auras around structured per-entry configuration so healer buffs can render either as configurable icon-strip slots or as colored corner squares on party and raid frames.
- Added class-based tracked-aura entry defaults, legacy migration from the old spell-name whitelist, and profile maintenance/import sanitization for the new aura entry format.
- Rebuilt the Tracked Auras configuration page into an entry editor with per-spell display style, slot, own-cast filtering, size, and square color controls.
- Prebuilt party and raid tracked-aura indicator pools so combat updates stay on the existing `UNIT_AURA` refresh path without creating secure-child visuals mid-fight.
- Hid live party frames automatically while the player is in a raid group so raid frames are the only active group presentation in raid content.
- Added and updated the related English configuration strings for tracked-aura entry management.
- Bumped addon metadata to `2.4.0`.

## 2.3.0 - 2026-03-19
- Reworked the configuration window so the Frames tab keeps every unit's settings on one page, groups target-related units together, and aligns section headers and subsections cleanly instead of letting the layout drift farther right as you scroll.
- Added party and raid debuff declutter filters with options to hide permanent debuffs, hide long-duration debuffs, and configure the duration threshold, including default-profile and profile-maintenance support for the new settings.
- Removed the live party and raid range polling tickers in favor of Midnight's event-driven group range updates so group frames no longer rely on protected fallback polling during combat.
- Added and updated the related English configuration strings for the new config sections and debuff filter controls.
- Bumped addon metadata to `2.3.0`.

## 2.2.5 - 2026-03-18
- Fixed shared group-event health dispatch so party and raid frames refresh live healthbars correctly again during combat.
- Bumped addon metadata to `2.2.5`.
