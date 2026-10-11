# ARCUS (ARC Upgrade System): porting guide

Built in NS2.0-TEH-Beta on 2026-10-10. Revised the same day after the first playtest. Not yet tested again in game.

This file sits outside `output/`, so it is never published with the mod.

## What it does

An ARC Factory can be converted, once, into one of three specialised factories. Each one builds its own kind of ARC and researches four upgrades in a fixed order.

| | Hammerworks | Vanguard | Inferno |
|---|---|---|---|
| Role | PvE: anti-structure | PvP: anti-personnel tank | PvPvE: flamethrower tank |
| Conversion research | Hammerworks Conversion | Vanguard Conversion | Inferno Conversion |
| Factory name | Hammerworks Siege Foundry | Vanguard Armour Works | Inferno Forge |
| ARC name (tooltip spells it out) | H.A.M.M.E.R. (Hive-Assault Mobile Mortar & Explosive Rig) | V.A.T. (Vanguard Assault Tank) | H.E.L.L. (Heavy Embedded Liquid-fire Launcher) |
| ARC skin | Tundra | Chroma | Forge |
| Factory skin | Tundra | Chroma | Forge |
| Moves while deployed | No | Yes | Yes |
| Fires | Only while deployed (normal ARC) | Only while deployed | Only while deployed |

On-screen names are just the acronyms (H.A.M.M.E.R., V.A.T., H.E.L.L.); the full names are in the tooltips.

Behaviour that applies to all three:

- **A plain ARC Factory** keeps its name, and **Buy ARC** builds a normal ARC.
- **Normal ARCs always use the standard skin,** whatever ARC cosmetic the Commander has chosen. Otherwise a Chroma cosmetic would make every normal ARC look exactly like a V.A.T. (`ARCSpec_Skins.lua` maps `kTechId.ARC` to the standard skin.)
- **Any mix is allowed.** Several factories can be converted, to the same or different specialisations.
- **The ARC limit is shared.** Every ARC of every type counts towards the existing `kMaxARCs` (5).
- **Each ARC keeps its own skin and name**, set by its own type.
- **Double-click / Ctrl-click selects only the clicked ARC type** among the usual on-screen candidates: normal ARC, H.A.M.M.E.R., V.A.T. or H.E.L.L. Shift keeps its usual toggle behaviour; marquee selection can still select mixed types. Added to Beta and Event on 2026-10-11.
- **Losing every factory of a specialisation:**
  - its specialised ARCs can't be built, and no further upgrade can be researched,
  - **specialised ARCs already built keep every level researched** (Level 0 up to the last one, with later levels replacing earlier effects as usual). `ARCSpec.GetUpgradeTier` reads each upgrade node's researched flag, not `GetHasTech`, which would also need the factory standing,
  - converting another factory to that specialisation continues from the last researched level; unresearched upgrades stay unresearched.

## Commander 2x4 grid (root level, no submenus)

```
Unspecialised ARC Factory           Specialised factory
[Hammer ][Vanguard][Inferno ][  ]   [Upgrade1][Upgrade2][Upgrade3][Upgrade4]
[Buy ARC][        ][        ][  ]   [Buy <specialised ARC>][  ][  ][  ]
```

- **Starting a conversion** hides the other two conversion buttons.
- **The four upgrades** are chained 1 → 2 → 3 → 4, so only the next one in order can be researched. A researched upgrade's button disappears, and the others keep their places.
- **Buy** is always bottom-left.
- **Tank orders:**
  - The H.E.L.L. has an **Attack** button: an Attack order makes it burn that target first, whatever the priority.
  - The V.A.T. has no Attack button.
  - Right-click moves either tank (a H.E.L.L. right-clicked onto an enemy attacks it).

## Costs and research times

| Item | Team resources | Time |
|---|---|---|
| Conversion (any of the three) | 15 | 20 s |
| Specialised ARC | 18 (normal ARC remains 15) | 10 s (twice the normal ARC's 5 s) |
| Upgrade 1 | 10 | 30 s |
| Upgrade 2 | 15 | 40 s |
| Upgrade 3 | 20 | 50 s |
| Upgrade 4 | 25 | 60 s |

The constants are in `ARCSpec_TechIds.lua`: `kSpecResearchCost`, `kSpecResearchTime`, `kUpgradeCosts`, `kUpgradeTimes`, `kARCCost` and `kARCBuildTimeScalar`.

Costs updated in Beta and Event on 2026-10-11: specialised ARCs cost a fixed 18 team resources; upgrade levels 1-4 cost 10, 15, 20 and 25. Conversion costs and all build/research times are unchanged.

## H.A.M.M.E.R.: Hammerworks (PvE)

The normal ARC siege cannon: 550 damage, 7 m blast. It can't move while deployed.

- **Targets:** every alien structure, including eggs, cysts, Hydras and spore mines. Never alien players or Babblers.
- **Shade ink:** the normal ARC rules apply (no firing into a cloud, auto-ink parry).

| # | Name | Effect |
|---|---|---|
| 1 | Hivebreaker Warheads | +25% damage to Hives |
| 2 | Fragmentation Casings | Blast radius 7 m → 10 m |
| 3 | Deflector Plating | Takes 25% less damage |
| 4 | Thermobaric Payload | +20% damage to everything in the blast, and sets it on fire |

## V.A.T.: Vanguard (PvP)

Never fires at structures.

| # | Name | Effect |
|---|---|---|
| Base | Machine gun (no research) | The same machine gun at half the fire rate and short range: 10 normal damage, 1 shot every 4 s, 6 m range (a little more than the H.E.L.L.'s 4 m Pilot Flame). Same targets, turret and effects |
| 1 | Coaxial Machine Gun | Full rate and range: 10 normal damage per shot, 1 shot every 2 s, 30 m range. Rifle-style tracer, muzzle flash and pistol-shot sound. Targets alien lifeforms first, then Babblers |
| 2 | Light Cannon Shells | Main cannon, alien lifeforms only. Charges 1 s (the ARC's own charge sound and effect at the muzzle), then fires (the ARC's own fire effect) 25 light damage. 5 s cooldown after firing, 22.5 m range |
| 3 | Standard Cannon Shells | Cannon deals 30 normal damage |
| 4 | Railgun Sabots | Cannon deals 65 heavy damage, with the railgun tracer |

- **Upgrade 4 was reduced from 100 heavy.** Heavy damage strips armour twice as fast, which is why 100 heavy looked like about 180 damage on armoured aliens. The machine gun's 10 per shot also adds on top. It went 100 → 35 → 67.5 (the mean) → **65**, at the user's request.
- **Cannon changes from the first version:** damage halved and range cut by 25%.

- **Spore clouds block it:** a spore cloud between the muzzle and the target (anywhere within the cloud's radius of that line) stops the machine gun from firing and the cannon from starting a charge. A charge that completes into spores is lost (no cooldown; it recharges once the line is clear). A flamethrower, Marine or H.E.L.L., has to burn the spores away.

## H.E.L.L.: Inferno (PvPvE)

Every hit is Flame damage. Each pulse also burns other aliens within 1.5 m of the target.

- **Target order when a burst is ready:**
  1. bile bombs in flight (Gorge `Bomb` and Whip `WhipBomb`),
  2. the Commander's Attack-order target,
  3. alien lifeforms,
  4. spore clouds,
  5. Babblers,
  6. any other alien structure.
- **During the cooldown** it fires at nothing, and never picks bile bombs or spores.
- **A bile bomb or spore target** takes one pulse: the stream reaches it at once and destroys it, then the normal cooldown starts.
- **Every flame pulse** also burns any spores or bile bombs its stream passes through. This is the vanilla flamethrower's own rule (`BurnSporesAndUmbra`), with the same `burn_spore` / `burn_bomb` effects.

| # | Name | Effect |
|---|---|---|
| Base | Pilot Flame (no research) | 0.25 s flicker, 4 m range, every 3 s. **No direct damage**; it sets targets on fire (two ignite stacks per pulse) |
| 1 | Igniter Burst | 0.25 s burst, 6 m range, 20 damage, every 2 s |
| 2 | Pressurised Flame Jet | 0.75 s burst (3 pulses of 15), 10 m range, every 2.5 s |
| 3 | Napalm Gel | 3 pulses of 18, and sets targets on fire |
| 4 | Thermite Lance | 14 m range, 3 pulses of 22, and sets targets on fire |

- **The flame stream** is drawn from the muzzle straight to the target on every pulse, so it always reaches instantly.
- **The range circle** on a placed H.E.L.L. or V.A.T. shows the reach of the weapon it currently has.
- **Why Pilot Flame failed before:** the Beta's fire system only ignites once the burn stack reaches the burn rate (5 per `SetOnFire` call against 8 per second for a player). One call never lit anything; two do.

## Research tray icons (Commander and spectator HUD)

- **What's shown:** one icon per specialisation the team has had, in the research tray (`GUIProduction`) next to the normal researched techs. It shows the acronym and level, e.g. "H.E.L.L." over "Level 3".
- **Colours:** team colour (blue) while a factory of that specialisation stands, and **red** once every one is destroyed.
- **Hover text:** the factory's name and level, then one "- effect" line per effect of the levels researched so far. An effect a later level replaces (a stronger cannon, a longer flame) is shown only in its latest form. A red icon adds an "Offline" line.
  - The lines are in `ARCSpec.kLevelEffects` (`ARCSpec_TechData.lua`) as `{ slot, text }` pairs per level; a later line in the same slot replaces the earlier one. Keep them in step with the numbers in `ARCSpec_ARC.lua`.
  - Built by `ARCSpec.GetLevelTooltip(key, level)`, and shown by a `GUIProduction:Update` wrapper in `ARCSpec_Production.lua`, which runs after the tray's own Update.
- **Why a message:** the tray normally reads `TeamInfo`'s tech bitmask, which is already full. So the state travels in a second network message, `ARCSpecTeamState`:
  - sent by the server when it changes, and every 10 s for late joiners,
  - holds, per specialisation, a state (0 none, 1 active, 2 lost) and a level from 0 to 4.
- **Textures:** `ui/arcus/<hammer|vanguard|inferno>_level<0-4>.dds`, 100x100. They're light, so the game's tint shows clearly, like the Combat Engineers icon.

## Line of sight

| ARC | Its own line of sight needed? | Can it fire at targets only the team can see? |
|---|---|---|
| H.A.M.M.E.R. | **No.** The normal ARC rule: it fires over walls | **Yes.** The target must be sighted by the team (Marines, Observatory, scans) or detected |
| V.A.T. | **Yes.** A clear trace from its own eye to the target, and no spore cloud on that line | **No.** Team sight doesn't help |
| H.E.L.L. | **Yes.** A clear trace from its own eye to the target (bile bombs and spores too) | **No.** Team sight doesn't help |

For all three, cloaked aliens must be detected, and nothing inside a Shade ink cloud can be targeted.

## Shade ink (tanks)

- They can't target anything inside an ink cloud.
- Each time a tank locks onto a new target, a ready Shade near that target gets the auto-ink parry (`AlienDetectionParry`).
- If the Shade inks, the lock is dropped.

## Turret and shot effects

- **Turret:** snaps straight to its target, taking the short way round, using the ARC's existing networked barrel angles. Vanilla eased the yaw linearly between ±180°, which made it swing the long way behind the ARC.
- **Shot effects:** drawn by each client from the ARC's muzzle attach point (`fxnode_arcmuzzle`) to the target, through one network message, `ARCSpecShot`.
- **Why a message:**
  - Hit-message tracers only reach players near the attacker, and an ARC's attacker is the Commander in the Command Station.
  - The server doesn't animate the ARC's bones, so server-made cinematics can't find the muzzle.

## Network budget

- **No new networked class and no new network variable.**
- **Factory and ARC type:** stored in each entity's existing networked tech ID.
- **Upgrades:** live only in the team tech tree. They are not added to `TeamInfo.kRelevantTechIdsMarine`, whose 32-bit mask is already full.
- **Two network message types,** not network variables:
  - `ARCSpecShot` (`entityid`, `vector`, and an integer from 0 to 3),
  - `ARCSpecTeamState` (a team number, plus a state and a level for each of the three specialisations).
- **New tech IDs:** 21, appended with `debug.appendtoenum` after all existing IDs.

## Files

### New

| File | Hooked (post) on | Purpose |
|---|---|---|
| `output/lua/CNBalance/ARCSpec/ARCSpec_TechIds.lua` | `lua/TechTreeConstants.lua` | 21 tech IDs, the `ARCSpec` table, costs and times |
| `output/lua/CNBalance/ARCSpec/ARCSpec_TechData.lua` | `lua/TechData.lua` | Names, tooltips, costs, times and range circles. Specialised Factory and ARC entries are copied from the live ARC Factory and ARC entries, without the map name |
| `output/lua/CNBalance/ARCSpec/ARCSpec_TechTree.lua` | `lua/TechTree.lua` | Makes the conversions instanced (per Factory) |
| `output/lua/CNBalance/ARCSpec/ARCSpec_Buttons.lua` | `lua/TechTreeButtons.lua` | Button icons for every new ID |
| `output/lua/CNBalance/ARCSpec/ARCSpec_MarineTeam.lua` | `lua/MarineTeam.lua` | Tech-tree nodes |
| `output/lua/CNBalance/ARCSpec/ARCSpec_RoboticsFactory.lua` | `lua/RoboticsFactory.lua` | 2x4 grid, allowed checks, ARC limit, conversion progress/cancel/complete, building specialised ARCs, no free MACs at specialised Factories |
| `output/lua/CNBalance/ARCSpec/ARCSpec_FactorySkins.lua` | `lua/RoboticsFactory.lua` | Factory skin by tech ID (client) |
| `output/lua/CNBalance/ARCSpec/ARCSpec_Production.lua` | `lua/GUIProduction.lua` | ARCUS icons in the Commander / spectator research tray (client) |
| `output/lua/CNBalance/ARCSpec/ARCSpec_Selection.lua` | `lua/Commander_MouseActions.lua` | Filters double-click / Ctrl-click ARC selection by the clicked ARC's tech ID (client) |
| `output/ui/arcus/*.dds` (15 files) | | Research tray icons: acronym plus "Level 0" to "Level 4" for each specialisation |
| `output/lua/CNBalance/ARCSpec/ARCSpec_Skins.lua` | `lua/ARCVariantMixin.lua` | ARC skin by tech ID (client) |
| `output/lua/CNBalance/ARCSpec/ARCSpec_ARC.lua` | `lua/ARC.lua` | All ARC behaviour: targeting, weapons, cannon charge, turret, orders, ink, H.A.M.M.E.R. shell, Deflector Plating, range circle |
| `output/lua/CNBalance/ARCSpec/ARCSpec_Shots.lua` | `lua/NetworkMessages.lua` | The `ARCSpecShot` message, and the client-side tracers, flame stream, muzzle flash and sounds |
| `output/models/marine/arc_spec/arc_hammer_tundra.dds` and `.material` | | ARC texture recoloured in the Tundra Exo scheme |
| `output/models/marine/arc_spec/arc_hell_forge.dds` and `.material` | | ARC texture recoloured in the Forge Exo scheme |
| `output/models/marine/arc_spec/rf_hammer_tundra.dds` and `.material` | | Robotics Factory texture, Tundra scheme |
| `output/models/marine/arc_spec/rf_vanguard_chroma.dds` and `.material` | | Robotics Factory texture, Chroma scheme |
| `output/models/marine/arc_spec/rf_inferno_forge.dds` and `.material` | | Robotics Factory texture, Forge scheme |

About the textures:

- **Source:** each `.dds` is generated from the vanilla textures in NS2-Copy (`models/marine/arc/arc.dds` and `models/marine/robotics_factory/robotics_factory.dds`). DXT5, 2048x2048.
- **Method:** the olive-green paint panels are found with a combined green and olive mask (the Factory's paint is olive, with red about equal to green), then recoloured to match each official skin:
  - **Tundra** (from the Tundra rifle and Command Station): near-white panels with ragged cyan-blue paint scratches, and red hazard stripes turned blue,
  - **Chroma** (from the Chroma Command Station): near-black brushed panels, with yellow/orange and blue lights turned red,
  - **Forge** (from the Forge Exo): dim red-brown panels with orange-red lights.
- **Why not the Exo textures directly:** they're laid out for the Exo model, so they can't be applied to the ARC.
- **The V.A.T.'s Chroma ARC skin** is the game's own `models/marine/arc/arc_chroma.material`.

### Edited

- `output/lua/CNBalance/FileHooks.lua`: 12 `SetupFileHook` lines added at the very end. They must stay after the mod's own hooks on the same files.

### Removed (were part of the first version)

- `output/lua/CNBalance/ARCSpec/ARCSpec_ClientEffects.lua` (railgun tracer through the hit message). Replaced by `ARCSpec_Shots.lua`.
- `output/models/marine/arc_spec/arc_inferno.dds` and `.material` (the first red skin). Replaced by the Forge skin.

Nothing outside the ARCSpec files was removed.

## Ports done

| Branch | Date | Notes |
|---|---|---|
| NS2.0-TEH-Event | 2026-10-11 | Straight copy, no code changes. Event's mod `FireMixin`, `RoboticsFactory.lua` and `MarineTeam.lua` are identical to Beta's; `GetTechIdIsInstanced`, `AlienDetectionParry` and every tech ID ARCUS uses exist there. Event has no `CNBalance/GUI/GUIProduction.lua` hook; ARCUS doesn't need it. Event's `CNBalance/Structures/Marine/ARC.lua` lacks Beta's ARC auto-deploy and "deployed ARC never sleeps" fixes; ARCUS doesn't depend on them (its tanks never sleep by their own `GetCanSleep` wrapper), but with no Commander a H.A.M.M.E.R. there won't deploy itself, same as a normal Event ARC. Backup taken by the user before the port: `NS2.0-TEH-Event - PRE ARC SPECIALISATIONS - 11TH OCTOBER 2026`. |

When ARCUS changes in Beta, copy the changed ARCSpec files to every branch in this table as well.

## Porting to another NS2.0-TEH branch

1. **Copy the files:** the whole `output/lua/CNBalance/ARCSpec/` folder, `output/models/marine/arc_spec/` and `output/ui/arcus/`.
2. **Register the hooks:** append the 12 `SetupFileHook` lines (see the end of the Beta's `FileHooks.lua`) after that branch's own hooks.
3. **Check what the target branch must already have:**
   - `GetTechIdIsInstanced` (mod hook on `lua/TechTree.lua`),
   - `AlienDetectionParry` (in `CNBalance/NS2Utility.lua`). The tanks skip the parry if it's missing.
   - the mod's `FireMixin` stack system. If the branch has vanilla `FireMixin`, one `SetOnFire` call ignites, so `igniteStacks = 1` is enough.
   - a `RoboticsFactory:GetTechButtons` override. Any version works, because ARCSpec takes over only for ARC Factories.
4. **If the branch's `MarineTeam:InitTechTree` differs:** ARCSpec only appends nodes after it runs, so no change is needed. It requires that `ARCRoboticsFactory`, `RoboticsFactory` and `kTechId.ARC` exist.
5. **Test:**
   - convert a Factory, and check its skin and that the other buttons hide,
   - research the upgrades in order,
   - build each ARC and check its name and skin,
   - V.A.T.: drive it deployed, check the machine-gun tracer and sound, the cannon charging and firing from the barrel, and that it never hits structures,
   - H.E.L.L.: check the flame stream reaches the target, Pilot Flame ignites, and an Attack order is obeyed,
   - H.A.M.M.E.R.: check it shells eggs and cysts but never players or Babblers,
   - check Shade ink stops the tanks,
   - check the ARC limit across mixed types,
   - place two of each ARC type together: double-click each type and check only its pair is selected; check Ctrl-click, Shift toggling, and mixed-type marquee selection too,
   - destroy the only Factory of a type: its built ARCs must keep their researched levels; convert another and check research continues from the last level.
