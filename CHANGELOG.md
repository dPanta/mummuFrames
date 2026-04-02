# Changelog

This changelog keeps `Unreleased` plus the 10 most recent tagged versions.

## Unreleased
- No changes yet.

## 3.2.0 - 2026-04-02
- Rebuilt party and raid out-of-range handling around a new dedicated `rangeHandle` module that owns cached range state and frame alpha application.
- Added spell-aware friendly/dead range probing, phase/visibility/offline gating, short-lived `UNIT_IN_RANGE_UPDATE` hints, and a lightweight polling safety net for group frames.
- Removed the old scattered group-range helpers and AuraHandle-driven range dispatch so party and raid frames now consume one centralized range pipeline.
- Bumped addon metadata to `3.2.0`.

## 3.1.2 - 2026-04-02
- Added feral druid combo points to the secondary power bar so druids now get the same combo-point pip bar support as rogues.
- Bumped addon metadata to `3.1.2`.

## 3.1.1 - 2026-04-01
- Fixed Vengeance Demon Hunter soul-fragment icons by treating fragments as the current secret-value custom resource, restoring the correct 6-pip display and live refresh behavior.
- Bumped addon metadata to `3.1.1`.

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
