# Party Spell-Target Highlight

This feature adds a dedicated warning border to `mummuFrames` party frames when a curated hostile NPC spell from Midnight Season 1 appears to be targeting that player.

## Implementation notes

- Runtime detection is Midnight-safe and avoids secret-target helpers such as `UnitIsSpellTarget`.
- Cast detection is driven by hostile `UNIT_SPELLCAST_*` events that the addon already routes through its shared event frame.
- Target resolution is driven by hostile caster unit scanning:
  - `UnitTokenFromGUID` first
  - fallback scan of `boss1-5`, `nameplate1-40`, `target`, `focus`, `mouseover`, `softenemy`
  - repeated `sourceUnit.."target"` checks during a short retry window
- Party-frame updates only toggle a prebuilt overlay and never mutate secure header ownership in combat.
- The tracker deliberately avoids introducing its own fresh `COMBAT_LOG_EVENT_UNFILTERED` or nameplate event registrations, because Midnight's protected event paths are stricter than earlier expansions.

## Midnight-only source references

The v1 curated list was seeded from current Midnight LittleWigs modules, using only mechanics whose modules expose concrete cast spell IDs instead of private-aura-only IDs.

- `Midnight/MagistersTerrace/ArcanotronCustos.lua`
- `Midnight/MagistersTerrace/Degentrius.lua`
- `Midnight/MagistersTerrace/Gemellus.lua`
- `Midnight/MagistersTerrace/SeranelSunlash.lua`
- `Midnight/MaisaraCaverns/MurojinAndNekraxx.lua`
- `Midnight/MaisaraCaverns/Raktul.lua`
- `Midnight/MaisaraCaverns/Vordaza.lua`
- `Midnight/NexusPointXenas/Lothraxion.lua`
- `Midnight/NexusPointXenas/Nysarra.lua`
- `Midnight/WindrunnerSpire/CommanderKroluk.lua`
- `Midnight/WindrunnerSpire/DerelictDuo.lua`
- `Midnight/WindrunnerSpire/Emberdawn.lua`
- `Midnight/WindrunnerSpire/RestlessHeart.lua`

## Seeded spell table

The first pass lives in [Modules/spellTargetTracker.lua](/mnt/gamecell/Blizzard_linux/World%20of%20Warcraft/_retail_/Interface/AddOns/mummuFrames/Modules/spellTargetTracker.lua) and currently includes:

- Magisters Terrace: `Ethereal Shackles`, `Unstable Void Essence`, `Cosmic Sting`, `Neural Link`, `Runic Mark`
- Maisara Caverns: `Flanking Spear`, `Infected Pinions`, `Freezing Trap`, `Barrage`, `Carrion Swoop`, `Spiritbreaker`, `Crush Souls`, `Drain Soul`, `Unmake`
- Nexus Point Xenas: `Searing Rend`, `Brilliant Dispersion`, `Umbral Lash`, `Eclipsing Step`, `Lightscar Flare`
- Windrunner Spire: `Reckless Leap`, `Intimidating Shout`, `Curse of Darkness`, `Searing Beak`, `Tempest Slash`, `Gust Shot`, `Bullseye Windblast`

## Deliberate gaps

Some Midnight Season 1 dungeon modules currently expose only private-aura IDs for their targeted mechanics in LittleWigs. Those fights are intentionally not guessed into the cast-scan table yet.

- Den of Nalorakk
- Murder Row
- The Blinding Vale
- Voidscar Arena

Those can be added later once live Midnight testing confirms the real cast spell IDs and best trigger unit events.
