# Changelog

This changelog keeps `Unreleased` plus the 6 most recent tagged versions.

## Unreleased

## 3.8.1 - 2026-04-26
- Fixed a `UNIT_AURA` delta crash when Midnight returned secret aura payload values for tracked-aura names or spell IDs, by routing tracked indicator set lookups through a guarded membership check.
- Bumped addon metadata to `3.8.1`.

## 3.8.0 - 2026-04-26
- Added an optional Mechanic integration that registers a `MechanicLib-1.0` bridge so the addon's per-module performance counters surface as profiler sub-metrics, with auto-enable when the `scriptProfile` CVar is on and a manual reset entry point.
- Added lightweight runtime profiling counters to the unit-frame, incoming-cast-board, range, aura, and data modules, gated behind `SetPerfCountersEnabled` so they only run when Mechanic or script profiling is active.
- Optimized personal unit-frame `UNIT_AURA` handling by tracking rendered aura instance IDs per frame and skipping refreshes when the delta payload only carries auras the frame neither renders nor tracks (including secondary/tertiary aura matches).
- Optimized party/raid aura dispatch by skipping `RefreshGroupFrameAuras` when a `UNIT_AURA` delta does not change the debuff cache or any tracked-aura indicator state.
- Narrowed `UNIT_ABSORB_AMOUNT_CHANGED` to an absorb-only refresh (plus tertiary on the player) instead of the full vitals path, and dropped the unnecessary tertiary refresh from non-player vitals events.
- Cached character settings and active profile context resolution in `dataHandle` so repeated config lookups reuse the same context table instead of rebuilding it on every call.
- Added `!Mechanic` to the TOC `OptionalDeps` so the Mechanic load-order hint applies when the host addon is installed.
- Bumped addon metadata to `3.8.0`.

## 3.7.0 - 2026-04-25
- Reworked the Heal/Aura tracking configuration into a preset-driven editor with all-healer defaults, per-class healer preset buttons, and a party-frame workspace preview.
- Added draggable aura indicators in the configuration preview so square and icon positions can be adjusted directly while the size and offset controls stay visible beside the preview.
- Expanded the bundled tracked-aura defaults for Restoration druid, Preservation evoker, Mistweaver monk, Holy paladin, Priest, and Restoration shaman support/HoT tracking.
- Added same-corner square sibling rendering so Druid `Rejuvenation (Germination)` can anchor next to `Rejuvenation` instead of consuming a detached icon slot.
- Added size-gated 1px borders to tracked aura icons, square indicators, and their preview counterparts when the indicator size is 10px or larger.
- Reworked party-frame debuff rendering for Retail/Midnight by avoiding nameplate-only clutter, hiding long non-dispellable debuffs by default, and separating dispellable overlay+type-icon display from non-dispellable type-icon-only display.
- Hardened aura/debuff access against Midnight secret-value wrappers, including safe handling for dispel flags, spell IDs, icons, durations, expiration times, and aura instance IDs.
- Bumped addon metadata to `3.7.0` and updated the TOC interface tag to `120005`.

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
