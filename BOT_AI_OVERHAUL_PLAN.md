# NS2.0-TEH-Beta Bot AI Overhaul — Implementation Plan

Date: 2026-06-16
Target: `NS2.0-TEH-Beta\output\lua\bots\` (+ a couple of lifeform files)

## 0. Findings (current state of Beta)

- Beta's bot files were **NOT** reverted to NS2.0-EN. All 17 shared files differ
  substantially (e.g. `MarineBrain_Data.lua` 4858 vs EN 3678 lines), only
  `MarineCommanderBrain_Utility.lua` matches.
- Vokex/Prowler/TEHBotManager standalone files are **absent** from Beta, BUT
  `PlayerBot_Server.lua` still has `elseif player:isa("Vokex")` (L355) and
  `elseif player:isa("Prowler")` (L361) calling brains that no longer exist →
  runtime error when such a bot spawns. (Dangling refs.)
- Beta has 4 files EN lacks: `AlienCommanderBrain.lua`, `AlienCommanderBrain_Senses.lua`,
  `BrainSenses.lua`, `MarineCommanderBrain.lua`.

### Key EN mechanisms this plan builds on
- `TeamBrain:Update()` (TeamBrain.lua L787) — per-team tick; builds `self.teamBots`.
  **The two 30-second server reviews hook in here.**
- Alien evolution: `CommonAlienActions.lua` (base game) →
  `CreateAlienEvolveAction(weights, type, lifeformTechId)`. The executor evolves a
  Skulk to **`bot.lifeformEvolution`** (a techId). `UpdateBotDesiredEvolution()` sets
  that field today via random/role logic. **Lever = set `bot.lifeformEvolution`.**
- Existing alien role-limiter (`kAlienTeamRoleLimits`, `teamRoles`, `GetIsRoleAllowed`,
  `ReportBotRole`, `GetRoleCount`) is a self-described "quick HACK" → we replace its
  behaviour with the even-distribution distributor.
- Marine purchases: `marine:ProcessBuyAction({ techId })` (MarineBrain_Data L1371/L1653).
  Marine objective actions include BuyWeapons / BuyExo / BuyJetpack / BuyMines /
  PlaceMines (enum `kMarineBrainObjectiveTypes`).
- Gorge already has bile-bomb logic (`PerformBileBomb`, `kTechId.BileBomb`) in EN
  `GorgeBrain_Data.lua` — Phase 3 is a refinement, not new code.

### Decisions locked with the user
- Revert = **full overwrite to NS2.0-EN + delete the 4 Beta-only files**.
- Alien lifeform order (poorest→richest) = **Gorge, Prowler, Lerk, Fade, Vokex, Onos** (all 6).
- Vokex = **modified working Fade brain**, also uses **Acid Rocket**, **no Vortex**.
- Gorge = **bile bomb + spit** when attacking; **leave healspray**.
- Marines: per-respawn purchase rolls (welder often, never Motion Tracker, each item
  once per life) + a 30s high-tech review for Exo / Jetpack / Jetpack+Gauss-Cannon
  with save-up + over-supply back-off + re-roll on death.
- Mines: PG, Armory, Adv. Armory, Infantry Portal, Command Station; max 4 each; count
  chosen by a set spacing distance.

---

## Phase 0 — Safety backup (do first)
Copy `NS2.0-TEH-Beta\output\lua\bots\` → `NS2.0-TEH-Beta\_bots_backup_pre_overhaul_<timestamp>\`
so the current Beta bot logic is recoverable even though we overwrite it. (Verify the
copy exists before proceeding to Phase 1.)

## Phase 1 — Revert to NS2.0-EN baseline
1. Overwrite each of the 17 shared files in Beta with the NS2.0-EN version.
2. Delete the 4 Beta-only files: `AlienCommanderBrain.lua`, `AlienCommanderBrain_Senses.lua`,
   `BrainSenses.lua`, `MarineCommanderBrain.lua`.
   - Risk check: EN's `PlayerBot_Server.lua` does **not** `Script.Load` these, and EN's
     other files don't require them (they load base-game `AlienCommanderBrain.lua` etc.
     by path). Confirm with a grep for each name across Beta after copying; if anything
     still references a deleted file, keep that file instead and note it.
3. After overwrite, Beta `PlayerBot_Server.lua` = EN's (no Vokex/Prowler branches) →
   dangling refs gone. Phase 2 re-adds clean branches.

## Phase 2 — Working Vokex & Prowler brains + dispatch
Vokex and Prowler are still assigned by the distributor, so they need brains.
1. **`VokexBrain.lua`** — `class 'VokexBrain' (FadeBrain)`; `Script.Load FadeBrain` +
   `VokexBrain_Data`; `GetExpectedPlayerClass()="Vokex"`; `GetActions()=kVokexBrainActions`.
2. **`VokexBrain_Data.lua`** — copy of `kFadeBrainActions` flow, but the attack executor
   selects weapons for Vokex: melee (swipe/equivalent) + **Acid Rocket** at range;
   **never Vortex**. Confirm Vokex weapon map names + energy costs from
   `output\lua\CNBalance\Lifeforms\Vokex.lua` during implementation.
3. **`ProwlerBrain.lua` / `ProwlerBrain_Data.lua`** — `class 'ProwlerBrain' (SkulkBrain)`
   variant using the Prowler's weapon(s); confirm map names from `output\lua\Prowler\Prowler.lua`.
4. **`PlayerBot_Server.lua`** — add `Script.Load` for both brains; add
   `elseif player:isa("Vokex") then self.brain = VokexBrain()` and the Prowler branch in
   `_LazilyInitBrain` (after Onos).
5. Confirm Vokex/Prowler tech IDs for the distributor (Phase 4): `kTechId.Vokex`,
   `kTechId.Prowler` (verify exact identifiers exist).

## Phase 3 — Gorge: bile bomb + spit
In EN `GorgeBrain_Data.lua` attack path: ensure when `kTechId.BileBomb` is researched the
bot **uses bile bomb against structures/area targets and spit otherwise** (alternate /
prefer bile vs structures, spit vs small targets), gated by `kBileBombEnergyCost`.
Leave `PerformHealSpray` untouched. Net effect: Gorge fights with bile **and** spit.

## Phase 4 — Alien 30-second even-distribution distributor
Add to `TeamBrain:Update()` a 30s (in-game) timer for the alien team only.

Order (cheapest→most expensive): `kTechId.Gorge, kTechId.Prowler, kTechId.Lerk,
kTechId.Fade, kTechId.Vokex, kTechId.Onos` → `L = 6`.

Each tick:
1. Gather alien bots from `self.teamBots`. For each, read player + `GetPersonalResources()`.
2. Classify:
   - **Locked** = already a non-Skulk lifeform (Gorge..Onos) OR currently gestating
     (`player:GetIsEvolving()`/gestating) → not reassignable this tick; counts toward totals.
   - **Eligible** = `isa("Skulk")` and not gestating → reassignable.
3. Count current lifeforms across ALL alien bots (locked evolved ones + any eligible bot's
   already-assigned `lifeformEvolution`). Build `have[lifeform]`.
4. `N = #aliveAlienBots` (or all alien bots). Compute target per lifeform =
   even split: `base = floor(N/L)`, remainder `r = N % L` distributed to the **cheapest r**
   lifeforms (Gorge first). → `target[lifeform]`.
5. Need per lifeform = `max(0, target - have)`.
6. Sort **eligible** bots by p-res ascending (poorest first).
7. Walk lifeforms cheapest→expensive; for each, assign the next poorest eligible bots
   (`set bot.lifeformEvolution = techId`) until that lifeform's `need` is met or bots run out.
   Mark each assigned bot consumed so it gets exactly one target.
8. Leftover eligible bots (if N not divisible) already handled by remainder in step 4.

**Forcing the assignment:** modify `UpdateBotDesiredEvolution()` (CommonAlienActions, copied
into Beta as a TEH override OR patched) so that when the server has set `bot.lifeformServerAssigned`
it does **not** randomise — it keeps `bot.lifeformEvolution` = the assigned techId. Simplest
robust approach: the distributor sets `bot.lifeformEvolution` directly AND a flag
`bot.lifeformAssignedByServer=true`; `UpdateBotDesiredEvolution` early-returns when that flag
is set and the bot is still a Skulk. The evolve action then evolves to it when safe/affordable
(its existing res/!combat/near-hive checks remain — satisfying "evolve when the bot's code
decides to, but always to the assigned lifeform").

**Edge cases**
- Mid-gestation when tick fires → bot is Locked, skipped (no error).
- Too poor → keeps the assignment; evolves later when affordable (no error).
- Already evolved → Locked; when it dies and respawns as Skulk it becomes Eligible again
  (flag reset on death/Skulk).
- No bots / all locked / all too poor → distributor simply assigns nothing. Fine.
- Bot removed mid-tick → guarded by `IsValid`/`GetPlayer()` nil checks.
- Reset flag `bot.lifeformAssignedByServer`/`bot.lifeformEvolution` when the bot becomes a
  Skulk again (death/devolve) so the next 30s tick re-plans cleanly.

## Phase 5 — Marine per-respawn purchasing
On (re)spawn, give each marine bot a fresh per-life purchase plan via probability rolls,
scaled by availability (Armory / Adv. Armory / Prototype Lab) and current p-res. Implemented
by extending the existing Marine buy objective actions / adding a per-life init keyed off a
"lastLifeId" so it re-rolls each spawn.
- Roll set (each independent, only if available & affordable, **bought once per life**):
  Shotgun, Welder (higher probability so structures get welded), Mines, GrenadeLauncher,
  Flamethrower, HeavyMachineGun, weapon upgrades available at Adv. Armory. **Never Motion Tracker.**
- Welder frequency tuned up so most bots carry one.
- Each successful item flagged on the bot so it isn't re-bought until next life.
- High-tech (Exo/JP/Cannon) handled by Phase 6, not here.

## Phase 6 — Marine 30-second high-tech review (Exo / Jetpack / Jetpack+Cannon)
Add to `TeamBrain:Update()` a 30s timer for the marine team, mirroring the alien one. Only
active when a **Prototype Lab is built** and the relevant tech is available
(`kTechId.Exosuit`/Jetpack/`DualMinigunTech`/Cannon — confirm exact IDs).
Per marine bot, one-by-one:
1. If the bot already has a per-life "save goal" (set), keep saving toward it.
2. Else roll a **save-for-combo** decision: choose among available combos —
   **Exo**, **Jetpack**, **Jetpack+Gauss-Cannon** (JP and Cannon can be bought together).
   - **Over-supply back-off:** if team already has ≥ limit of that entity (limits scaled to
     team size; default cap chosen during impl, e.g. proportional like the alien split), skip
     that combo this tick; the bot buys normal items (Phase 5) meanwhile and re-tries later
     when counts drop.
   - If the save-roll **succeeds**: set `bot.saveGoal = combo`; the bot stops spending and
     **saves p-res**; buys the combo as soon as affordable AND availability/limit allow.
   - If the save-roll **fails**: no high-tech goal this cycle; Phase 5 item rolls apply.
3. **Once per life:** a purchased combo is flagged; not re-bought this life. On **death**,
   clear `saveGoal`/flags → the save-roll happens again next life (if still available).
4. Affordability: if can't afford yet → keep saving (don't buy normal items that would
   drain the savings, except cheap survival items per tuning).

Edge cases: bot dies mid-save (reset), Prototype Lab destroyed (drop unaffordable goal),
tech lost, bot removed → all guarded.

## Phase 7 — Mines around key structures
Extend EN's mine placement (`kMinePriority` / PlaceMines objective in MarineBrain_Data) to
cover: **Phase Gate, Armory, Advanced Armory, Infantry Portal, Command Station**.
- **Max 4 mines per structure.**
- Number to place derived from a **set spacing distance**: place around the structure at
  ~`structureExtents + spacing`, count = min(4, ringSlots), de-dupldes against mines already
  near that structure (count existing mine entities within radius; only top up to 4).
- Only marines carrying mines (slot 4) perform placement; integrates with Phase 5 (mines are
  one of the purchasable items).

## Edge-case & safety summary
- All new per-team logic guarded with `Shared.GetTime()` timers and `IsValid`/nil checks.
- 30s reviews are independent per team and skip cleanly when no bots / no tech / no structures.
- Assignments stored on the bot table (`lifeformEvolution`, `lifeformAssignedByServer`,
  `saveGoal`, per-life purchase flags) and reset on death/Skulk so state never goes stale.
- No exceptions thrown during gestation/respawn races (classify + skip).

## Verification
- Lua syntax check each changed/new file with `luac -p` (if available) or load-parse;
  otherwise careful manual review + matching brace/`end` counts.
- Confirm `PlayerBot_Server.lua` loads and dispatches all 8 brain types incl. Vokex/Prowler.
- Grep Beta after revert for any reference to the 4 deleted files (must be none).

## Open items to confirm during implementation (against named files)
- Vokex weapon map names + energy costs — `output\lua\CNBalance\Lifeforms\Vokex.lua`.
- Prowler weapon map names + base class — `output\lua\Prowler\Prowler.lua`.
- Exact tech IDs: `kTechId.Vokex`, `kTechId.Prowler`, Exo/Jetpack/Gauss-Cannon, MinesTech.
- EN Marine purchase action structure (BuyWeapons/BuyExo/BuyJetpack/BuyMines/PlaceMines)
  — `NS2.0-EN\output\lua\bots\MarineBrain_Data.lua`.
- Whether to patch `CommonAlienActions.lua` via a Beta override file or copy it into
  `output\lua\bots\` (Beta loads `lua/bots/...`; confirm load order so the override wins).
