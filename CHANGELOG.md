# Changelog

This changelog keeps `Unreleased` plus the 10 most recent tagged versions.

## Unreleased
- No changes yet.

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

## 3.2.1 - 2026-04-04
- Reworked party and raid dispellable-debuff highlighting with brighter overlays, colored frame accents, and new corner icons for Magic, Curse, Poison, and Disease debuffs.
- Fixed party and raid `Ready` and `Pull` leader actions by dispatching slash commands through registered slash handlers instead of relying on the chat edit box flow.
- Bumped addon metadata to `3.2.1`.

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
