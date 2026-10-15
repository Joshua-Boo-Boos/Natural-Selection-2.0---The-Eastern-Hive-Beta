# BMAC character: porting guide

Built in NS2.0-TEH-Beta on 14 October 2026. **Not yet fully tested in game:** the first playtest found the memory blow-up and the 100 → 50 AP correction, both fixed below.

The design and its reasoning are in `NS2.0-TEH/BMAC_Character.md` (Draft 6, sections 13-14). This file only covers how to copy the feature to another mod.

This file sits outside `output/`, so it is never published with the mod.

**Port only when Joshua says so.** The design was decided as "Beta only" until the Beta version is proven in game.

Branch short names: **M** = NS2.0-TEH-Main, **B** = NS2.0-TEH-Beta (source), **E** = NS2.0-TEH-Event, **S** = Siege2.0-TEH, **D** = Defense2.0-TEH.

## What it does

A Marine wearing one of the **vanilla BigMac or military MAC skins** (including their Chroma versions) is a **BMAC**: armour only, like an Exo.

**Survivability**
- **No health pool.** The 100 HP becomes **+50 AP** (100 HP at 2 damage per AP), so a BMAC has exactly the same total EHP as a biological Marine with the same upgrades.
- **Totals:** 80 AP with no upgrades (30 + 50); 145 AP with Armor 3 and Nano Armour (35 + 60 + 50).
- **Death:** at 0 AP, through the game's own Exo mechanism (`healthIgnored`).

**Damage (Exo rules)**
- **All damage comes off AP.**
- **Bile Bomb:** uses the Exo Corrode rate and **can kill** a BMAC (on a biological Marine it only strips armour).
- **Spores, biological damage and Lerk bite poison:** no effect. The Lerk bite itself still hits AP.
- **Crush (Spur):** bonus damage, as against an Exo.

**Status effects**
- **Fire:** can't be ignited; direct flame damage still hits.
- **Stun:** immune, Onos Stomp included; Stomp damage still lands.
- **Devour:** can't be swallowed; the bite (50) still takes 25 AP.
- **Vortex:** damages but never pulls (mass unchanged).

**Repair and healing**
- **Repairs AP:** MAC, Welder, Armory, Advanced Armory and Nano Armour.
- **No effect:** health regeneration and Life Sustain.
- **Supply Depot:** gives ammo only. It only ever heals health, and a BMAC's hidden health is always full.

**Medpacks: 25 AP instead of 50 HP**
- **Payout:** a medpack gives a BMAC **25 AP** (`kBMACMedpackArmor`), at once. A biological Marine gets 50 HP (Beta: 40 at once + 10 regeneration), and 25 AP is the same amount at 2 damage per AP. Regeneration only heals health, which a BMAC doesn't use.
- **Eligibility:** a BMAC can take one whenever its AP isn't full (instead of health not full), with the same per-player pickup delay.
- **Everything else as for a biological Marine:** picking packs up, the Commander's target-assist, the "need medpack" request and self-medication (25 AP for the same p-res), bot Marines and the bot Commander.
- **Commander tooltip:** "Restores 50 player health (25 armor for a BMAC)".

**Per-round Marine choice** (added 2026-10-15)
- **When the window appears:** when a player enters the ready room before a round has started. It doesn't appear again until that round has ended. Every player gets it, in case the shuffle makes them a Marine. The Commander gets it too, since they can leave the Chair mid-round.
- **Window 1, "Choose Your Marine":**
  - three options side by side: Biological, BMAC and Random (a large "?");
  - Biological and BMAC use the game's own Thunderdome art (`ui/thunderdome_rewards_icons/marines_eliteassault.dds` and `bmac_chroma.dds`), so no new assets are needed;
  - picking Biological or BMAC sends that choice at once, then opens window 2;
  - picking Random closes the window.
- **Window 2, "Choose Your Biological Skin" / "Choose Your BMAC Skin":**
  - a grid of the skins of that body the player owns, then Back and Confirm;
  - a "Random" tile appears only when there is more than one skin to choose from (checked separately for each body). With a single skin, that skin is pre-selected;
  - the panel is sized to the tiles actually shown (up to 4 columns, never narrower than the title and buttons need);
  - names use first-letter capitals per word (e.g. "Butler B.M.A.C.");
  - custom (TEHSF) skins are listed under Biological.
- **Free for everyone:**
  - "Normal": the default human skin, which has no item at all;
  - "Chroma B.M.A.C.": a Thunderdome / Competitive Play reward (item 14002, "TD Chroma Items" in `menu2/items/itemDefs.lua`), not a DLC skin.

  So everyone can choose either body with no DLC.
- **Ownership only:**
  - the base "B.M.A.C." is **not** free: it's in the paid B.M.A.C. Supporters Pack (`kDlcBmacPackId`, `kDlcOnlyPurchasableItems`);
  - every other DLC or Competitive Play skin is likewise shown only if the player owns it.
- **If nothing is chosen in time:** the windows close at the Countdown.
  - No body chosen: Biological or BMAC is picked at random, then a random owned skin.
  - Body chosen but no skin: a random owned skin of that body.
  - Late joiners (who never saw the window) and bots are random too.
- **Male or female:** Biological keeps the player's own male/female setting from their options.
- **Choices are fixed for the round:** they're made before the round, used at the Countdown, and ignored if sent during a round. They're cleared when the round ends (won, drawn or reset mid-round), but not by the countdown's own `ResetGame`.
- **Options menu:** the options-menu skin no longer decides the round.
- **Military Protocol mid-round:** every Marine is re-skinned at once to the Chroma version of their body (Chroma Biological, Chroma B.M.A.C. or Chroma Military B.M.A.C.), bots included. This includes anyone waiting to respawn. Before this change, Marines only turned Chroma on their next respawn.

**Skin lock**
- **When:** the round's chosen skin (see above) is locked from the Countdown until a win, draw or reset.
- **What it stops:** nobody can switch between BMAC and human durability mid-round.
- **Bodies it applies to:** Marines **and** the `MarineSpectator` a dead Marine becomes while waiting to respawn. The Infantry Portal's spawning hologram copies that spectator's model, so without this the newly picked skin flashed up during the respawn.
- **Custom skins** (e.g. TEHSF desert/urban) are locked too, but always stay biological.
- **Military Protocol:** its Chroma swap is applied on top of the locked skin, so a BMAC becomes the Chroma BMAC.
- **Ownership:** a skin the player doesn't own is never allowed.

**Changing body**
- **Jetpack:** keeps the exact AP, with no refill.
- **Exo exit** (normal and Emergency Ejection): restores the exact AP the BMAC had when it got in. 15 AP is only used if that value is missing.
- **HeavyMarine:** uses its own stats (no BMAC rules).

**Physics:** unchanged. A BMAC is still the `Marine` / `JetpackMarine` class, with Marine collision size, mass and movement, so it doesn't clip through walls.

**HUD**
- **Bottom-left status panel:** the HP/AP cluster is replaced by the Exo's armour readout (same panel art and font, drawn square at the Exo's proportions, `kPanelSide = 160`). The number is in the Marine HUD's AP blue (`GUIMarineStatus.kArmorBarColor`), red below 30%.
- **Crosshair HP/AP bars:** show AP only, as a full bar at full AP.

## How it decides (read before changing anything)

- **One decision, then a stored flag.** The skin is checked against the vanilla list **once**, when a skin is applied: spawn, skin change, Jetpack, Exo exit. The result is stored as the existing, already-networked armour-only flag (`healthIgnored`).
- **Everything else reads only that flag:** damage, HUD, bots, medpacks, Stomp, Devour, Vortex and the +50 AP.
- **Never put a skin lookup, table or closure in those hot paths.** An earlier version did, and ran the game out of Lua memory (`LowAddressAllocator: Failed to allocate`) within a minute of fighting.
- **Vanilla list:** 24 hard-coded vanilla skin **names**. Any other name (TEHSF's desert/urban) is custom, so it's never a BMAC.
- **TEHSF product ids:** if TEHSF is loaded, its product ids are also treated as custom. It is read with `rawget`, so it's optional: no error if TEHSF is missing.

## Network budget

- **No new networked class and no new network variable.** It uses LiveMixin's existing `healthIgnored`, `armor` and `maxArmor`, plus the Marine's existing `variant`.
- **Two network messages, client to server only.** Messages don't count against the network-variable or class limits.
  - `BMACRoundChoice` (`bodyType` 0-2, `variant` 0-1023): the per-round choice.
  - `BMACOwnedSkins` (`owned`: a "0"/"1" string, 128 characters, by variant id): the Marine skins this player owns.

**Skin ownership: never a DLC skin a player doesn't own.**
- **Why a report is needed:** the server cannot check ownership. Vanilla `GetOwnsItem` returns `true` on the server for every item (`ItemUtils.lua`), and every Marine skin is an item. So `GetHasVariant(..., client)` passes for any skin on the server, and only the player's own game can ask Steam.
- **The report:** each client sends `BMACOwnedSkins` once after connecting, and again whenever the choice window opens.
- **What the server ever uses:** the free skins (Normal and Chroma B.M.A.C., neither of them DLC), plus skins in that player's own report.
- **Before a report has arrived:** only the free skins, never an unproven one. The report arrives within moments of connecting, and the player's own skin is then applied.
- **Chosen skins** are refused unless they're owned or free.
- **Options-menu skins outside a round** that are neither free nor proven owned are replaced by the free skin of the same body. The check runs in the same update that would apply the skin (options change, spawn, respawn, Jetpack, Exo exit, spectator), so an unowned DLC skin is never shown, not even briefly.
- **Military Protocol's Chroma skins** (Chroma Elite Assault, Chroma B.M.A.C., Chroma Military B.M.A.C.) are Thunderdome / Competitive Play items, not DLC.
- **Bots** have no Steam account and may use any skin.
- **Limit:** a deliberately modified game client could lie in its report. That's the same trust vanilla NS2 already places in the client's options for every skin; no server can check Steam item ownership.
- **No new tech IDs.** The choice window is a plain Lua `GUIScript` class, not a networked class.

## Files

All paths are relative to `output/lua/`.

### New (copy as-is)

| File | Hooked (post unless stated) on | Purpose |
|---|---|---|
| `CNBalance/BMAC/BMAC_Shared.lua` | `lua/MarineVariantMixin.lua` | Vanilla-name list, optional TEHSF check, per-skin cache, `GetIsBMACMarine` (flag read), `BMAC_GetShouldBeBMAC` (the one decision), round lock, `BMAC_RefreshDurability`, `BMAC_RestoreAfterExoExit`, wraps of the mixin's `CopyPlayerDataFrom` / `OnClientUpdated` |
| `CNBalance/BMAC/BMAC_Marine.lua` | `lua/Marine.lua` | +50 AP, armour-use 1, AP-based `GetHealthFraction` (**server only**, for bots; on the client it must stay 0 like an Exo, or a red health section appears in the unit-status bar), no Spores/biological, no ignition, no stun, no regen, no Lerk poison (`SetPoisoned`) |
| `CNBalance/BMAC/BMAC_JetpackMarine.lua` | `lua/JetpackMarine.lua` | Same +50 AP and no regen for JetpackMarine's own overrides |
| `CNBalance/BMAC/BMAC_Exo.lua` | `lua/Exo.lua` | Both Exo exits: saves entry AP and owner before `Replace`, restores after |
| `CNBalance/BMAC/BMAC_MedPack.lua` | `lua/MedPack.lua` | For a BMAC: valid recipient while AP isn't full; `OnTouch` gives 25 AP (`BMAC_GiveMedpackArmor`, also used by self-medication). Uses `MedPack.kPickupDelay`, because self-medication passes the Marine as the pack |
| `CNBalance/BMAC/BMAC_Gamerules.lua` | `lua/NS2Gamerules.lua` | Lock starts at Countdown/Started, clears on any other state and on `ResetGame` |
| `CNBalance/BMAC/BMAC_GUIMarineStatus.lua` | `lua/Hud/Marine/GUIMarineStatus.lua` | Exo-style AP panel in the bottom-left status area; restores the normal panel within HUD settings |
| `CNBalance/BMAC/BMAC_NetworkMessages.lua` | `lua/NetworkMessages.lua` | Registers `BMACRoundChoice` and `BMACOwnedSkins` and hooks them on the server (handlers `BMAC_OnRoundChoiceMessage` / `BMAC_OnOwnedSkinsMessage` in `BMAC_Shared.lua`); defines `kBMACChoiceRandom` / `Biological` / `BMAC` and `kBMACOwnedSkinsMax` |
| `CNBalance/BMAC/BMAC_RoundChoice_Client.lua` | `lua/Player_Client.lua` | Client: opens the choice window in the ready room before a round, closes it at the Countdown, re-arms it after the round ends |
| `CNBalance/BMAC/GUIBMACRoundChoice.lua` | (loaded by the file above via `CreateGUIScript`) | Client: the two choice windows |
| `CNBalance/BMAC/BMAC_MarineTeam.lua` | `lua/MarineTeam.lua` | Military Protocol completing re-skins every Marine body at once (`BMAC_ReapplyRoundLock`) |
| `CNBalance/BMAC/BMAC_UnitStatus.lua` | `lua/Player_Client.lua` | Client: the unit-status bar/text over a BMAC (as seen when parasited, or by teammates) shows AP only, like an Exo - no red health section and no "health/armour" text |
| `CNBalance/GUI/GUIAdvancedHUDBars.lua` | `lua/GUIAdvancedHUDBars.lua` (**replace**) | Copy of vanilla with a nil-player guard and an armour-only branch (Exo or BMAC); full-width AP bar for a BMAC. Re-compare with vanilla whenever NS2 updates that file |

### Registered in `CNBalance/FileHooks.lua`

Append at the **very end**, after the branch's own hooks on the same files:

```lua
-- BMAC character (design: NS2.0-TEH/BMAC_Character.md). A Marine in a vanilla BMAC skin is armour-only
-- (+50 AP, Exo-style damage rules) and the selected skin is locked for the round. Registered LAST so
-- each file wraps the final version of what it hooks (CNBalance's MarineVariantMixin, Marine,
-- JetpackMarine, Exo, MedPack and NS2Gamerules hooks above). DamageTypes, Armory, Shockwave, Devour and
-- Vortex are edited in place.
ModLoader.SetupFileHook("lua/MarineVariantMixin.lua", "lua/CNBalance/BMAC/BMAC_Shared.lua", "post")
ModLoader.SetupFileHook("lua/Marine.lua", "lua/CNBalance/BMAC/BMAC_Marine.lua", "post")
ModLoader.SetupFileHook("lua/JetpackMarine.lua", "lua/CNBalance/BMAC/BMAC_JetpackMarine.lua", "post")
ModLoader.SetupFileHook("lua/Exo.lua", "lua/CNBalance/BMAC/BMAC_Exo.lua", "post")
ModLoader.SetupFileHook("lua/MedPack.lua", "lua/CNBalance/BMAC/BMAC_MedPack.lua", "post")
ModLoader.SetupFileHook("lua/NS2Gamerules.lua", "lua/CNBalance/BMAC/BMAC_Gamerules.lua", "post")
-- Maintained copy of vanilla GUIAdvancedHUDBars.lua (its layout values are file locals).
ModLoader.SetupFileHook("lua/GUIAdvancedHUDBars.lua", "lua/CNBalance/GUI/GUIAdvancedHUDBars.lua", "replace")
ModLoader.SetupFileHook("lua/Hud/Marine/GUIMarineStatus.lua", "lua/CNBalance/BMAC/BMAC_GUIMarineStatus.lua", "post")
-- Unit-status bar/text over a BMAC: AP only, like an Exo (after CNBalance's Player_Client hook).
ModLoader.SetupFileHook("lua/Player_Client.lua", "lua/CNBalance/BMAC/BMAC_UnitStatus.lua", "post")
-- (2026-10-15) Per-round Marine choice: Biological / BMAC / Random, then a skin. The message (+ its server hook), the
-- window trigger (client) and the Military Protocol re-skin (after the mod's MarineTeam hooks).
ModLoader.SetupFileHook("lua/NetworkMessages.lua", "lua/CNBalance/BMAC/BMAC_NetworkMessages.lua", "post")
ModLoader.SetupFileHook("lua/Player_Client.lua", "lua/CNBalance/BMAC/BMAC_RoundChoice_Client.lua", "post")
ModLoader.SetupFileHook("lua/MarineTeam.lua", "lua/CNBalance/BMAC/BMAC_MarineTeam.lua", "post")
```

Each target branch must already hook `lua/MarineTeam.lua` with its own `MarineTeam:OnResearchComplete` (checked: M, B, E, S and D all have `CNBalance/MarineTeam.lua`); the BMAC hook must come after it.

### Edited in place (re-apply by hand; never copy the whole file across)

These files differ per branch in other ways, so make **only** these small changes. Every guard checks `GetIsBMACMarine` exists, so an edit is harmless even before the BMAC files load.

1. **`CNBalance/DamageTypes.lua`** (four changes plus one helper)
   - Add after `function GetReceivesBiologicalDamage(entity) ... end`:
     ```lua
     -- BMAC character (CNBalance/BMAC): an armour-only BMAC Marine takes Exo-style Crush, armour use and
     -- Corrode, and Bile Bomb can kill it. GetIsBMACMarine is defined in BMAC_Shared.lua.
     local function GetIsBMACTarget(target)
         return GetIsBMACMarine ~= nil and GetIsBMACMarine(target)
     end
     ```
   - **Crush:** `if target:isa("Exo") or target:isa("Exosuit") or` → insert `GetIsBMACTarget(target) or` before `target.GetReceivesStructuralDamage`.
   - **`ApplyHighArmorUseFractionForExos`:** `if target:isa("Exo") then` → `if target:isa("Exo") or GetIsBMACTarget(target) then`.
   - **`IgnoreHealthForPlayersUnlessExo`:** add `and not GetIsBMACTarget(target)` to its `if`.
   - **`ReduceGreatlyForPlayers`:** add `or GetIsBMACTarget(target)` to the Exo/Exosuit branch.
2. **`CNBalance/Structures/Marine/Armory.lua`** in `Armory:ResupplyPlayer`:
   ```lua
   local armorOnly = player.GetIgnoreHealth and player:GetIgnoreHealth()
   if player:GetHealthFraction() < 1 and not armorOnly then
   ```
   (was `if player:GetHealthFraction() < 1 then`). Advanced Armory inherits it.
3. **`CNBalance/Weapons/Alien/Shockwave.lua`:** `if enemy:isa("Player") and not enemy:isa("Exo") then` → add `and not (GetIsBMACMarine and GetIsBMACMarine(enemy))`.
4. **`Combat/Devour.lua`** in `Devour:Attack`, at the swallow check:
   ```lua
   local isBMAC = GetIsBMACMarine and GetIsBMACMarine(target)
   if (target:isa("Marine") or target:isa("JetpackMarine")) and not isBMAC then
   ```
5. **`CNBalance/Weapons/Alien/Vortex.lua`** in `SuckinPlayers`: `if mass < 200 then` → `if mass < 200 and not (GetIsBMACMarine and GetIsBMACMarine(entity)) then`.
6. **`CNBalance/Mixin/RequestHandleMixin.lua`** in `MedSelf` (self-medication), replace the two heal lines after `self:AddResources(-kAutoMedPRes)`:
   ```lua
   -- BMAC character: 25 AP instead of 50 HP (CNBalance/BMAC/BMAC_MedPack.lua).
   if GetIsBMACMarine and GetIsBMACMarine(self) and BMAC_GiveMedpackArmor then
       BMAC_GiveMedpackArmor(self)
   else
       self:AddHealth(MedPack.kHealth, false, true)
       self:AddRegeneration(MedPack.kRegen)
   end
   ```
7. **`CNBalance/Locale.lua`**, at the end (Commander tooltip):
   ```lua
   -- BMAC character (CNBalance/BMAC/BMAC_MedPack.lua): a BMAC gets armour instead of health.
   kLocales["MED_PACK_TOOLTIP"] = "Restores 50 player health (25 armor for a BMAC)"
   ```
   If the branch's medpack isn't 50 HP, adjust both numbers (BMAC AP = HP / 2).

**No BMAC edits in the Commander snap, voice routing or bot files.** An earlier version blocked medpacks there; that was removed when medpacks became 25 AP. Bots work through the server-side AP-based `GetHealthFraction` (in `BMAC_Marine.lua`). If a branch still carries those old `GetIsBMACMarine` medpack lines, remove them.

**Already correct, no change needed** (verified in every branch below): `Combat/WeaponCache_Server.lua` (the Supply Depot only heals health), `CNBalance/Mixin/AutoWeldMixin.lua` (regen goes through `GetAutoHealPerSecond`, already wrapped), and `CNBalance/Mixin/FireMixin.lua` (already calls `OnOverrideCanSetFire`).

## Per-branch check (checked 14 October 2026)

Each branch was checked for every file and code line the BMAC content depends on.

| Needed by BMAC | M | E | S | D |
|---|---|---|---|---|
| Mod `MarineVariantMixin` with MP override, `Marine:GetArmorAmount` / `GetVariantOverride` / `GetAutoHealPerSecond`, JetpackMarine overrides | ✔ | ✔ | ✔ | ✔ |
| `Exo:AttemptToKill` + `PerformEject` wrap, `MedPack:OnTouch`, `NS2Gamerules:SetGameState` | ✔ | ✔ | ✔ | ✔ |
| DamageTypes, Armory, Shockwave, Devour, Vortex anchors | ✔ | ✔ | ✔ | ✔ |
| `RequestHandleMixin:MedSelf` heal lines, mod `Locale.lua` (`kLocales`) | ✔ | ✔ | ✔ | ✔ |
| `HeavyMarine` / `DevouredPlayer` (Marine subclasses, excluded) | ✔ | ✔ | ✔ | ✔ |
| Supply Depot is health-only, armour values (`BalanceHealth.lua`) | ✔ | ✔ | ✔ | ✔ |
| Existing hook on `GUIAdvancedHUDBars` / `GUIMarineStatus` (would clash) | none | none | none | none |

**M, E, S and D:** straight port. Copy the files, register the hooks and make the seven in-place edits.
- **No bot-file edits are needed any more**, so it no longer matters that Siege has no mod `bots/MarineBrain_Data.lua` or that Defense has no mod bot-Commander files.
- **Defense** keeps having no updated bot-Commander logic. That's deliberate (Joshua, 14 October 2026): it lives only in M, B, E and S, because Defense's Alien side works differently. Don't copy those files in.
- **Paths:** Siege is `Siege2.0-TEH\Siege2.0-TEH\output`; Defense is `Defense2.0-TEH\Defense2.0-TEH\output` (the GitHub-tracked copy).

**Re-check before porting:** these results are a snapshot. The quickest check is to grep the target for each "was" string in the edit list above. If one is missing, that file has changed since: read it, and apply the same idea by hand.

## Porting steps

1. **Back up the target** (copy the folder, like `NS2.0-TEH-Event - PRE ARC SPECIALISATIONS - 11TH OCTOBER 2026`).
2. **Copy the new files:** the whole `output/lua/CNBalance/BMAC/` folder and `output/lua/CNBalance/GUI/GUIAdvancedHUDBars.lua`.
3. **Register the hooks:** append the FileHooks block at the very end of `CNBalance/FileHooks.lua`.
4. **Make the in-place edits** with the Edit tool. Never use sed, Python or blanket replaces on Lua.
5. **Syntax check** every touched file (LuaJIT / lupa `loadstring`).
6. **Test in game:**
   - **Spawning and EHP:** spawn as a BMAC. Check 80 AP with no upgrades and 145 AP with Armor 3 + Nano Armour, the Exo-style panel bottom left, and no HP number.
   - **Memory (repeat of the original failure):** start biological, switch to a BMAC skin during the Commander-selection phase, then fight with rifle and melee for a few minutes. There must be no `LowAddressAllocator` errors and no time-out.
   - **Damage:**
     - Skulk bites take AP;
     - Bile Bomb can kill;
     - Spores do nothing;
     - a Lerk bite takes AP but never poisons (no AP ticking down afterwards);
     - Stomp doesn't stun and still deals damage;
     - Devour bites but never swallows;
     - Vortex damages but never pulls;
     - no burning after a flame hit.
   - **Repair:** MAC, Welder, Armory and Advanced Armory repair AP. The Supply Depot gives ammo only.
   - **Medpacks:**
     - a damaged BMAC picks up a medpack and gains exactly 25 AP;
     - at full AP it walks over medpacks without taking them;
     - the Commander's drop snaps onto it;
     - its "need medpack" request reaches the Commander (or self-medicates for p-res, giving 25 AP);
     - a damaged bot BMAC goes for nearby medpacks;
     - the Commander's medpack tooltip reads "Restores 50 player health (25 armor for a BMAC)".
   - **Unit-status bar:** parasite a BMAC as an Alien (and look at one as a teammate). The bar over its head must show only the AP (yellow) section and a single AP number, never a red health section or "health/armour".
   - **Changing body:** a Jetpack keeps AP; Exo ejection and Emergency Ejection restore the entry AP.
   - **Round choice:**
     - entering the ready room before a round opens "Choose Your Marine" once;
     - choosing Biological or BMAC opens the skin grid of that body, showing only owned skins plus Normal / Chroma B.M.A.C., and Random only when there is more than one;
     - with a single skin there is no Random tile, that skin is pre-selected, and the panel is narrower;
     - Confirm locks that skin at the Countdown;
     - closing with Escape, or not finishing, gives a random body and/or skin;
     - the window doesn't reappear until the round has ended, then does in the ready room;
     - bots get random bodies and skins;
     - researching Military Protocol mid-round turns every Marine Chroma at once, Biological to Chroma Biological and BMAC to Chroma B.M.A.C.
   - **Skin lock:** a skin change after Countdown is refused until the round ends; the next round uses the newest choice. Also pick a different skin, die, and watch the Infantry Portal hologram while respawning: it must show the **locked** skin, never the new pick.
   - **Physics:** walk into walls and corners standing, crouched and jumping; use a phase gate, a Gorge tunnel and a ladder. No clipping.
   - **Logs:** clean server and client logs.

## Change log (Beta)

Every BMAC change in Beta is listed here, so a port always carries the latest version.

| Date | Change | Files |
|---|---|---|
| 2026-10-14 | First build (see the sections above) | all |
| 2026-10-14 | Fix: Lua out-of-memory. Skin decided once and stored as the armour-only flag; hot paths only read it; per-skin cache; TEHSF read via `rawget` (optional) | `BMAC_Shared.lua` |
| 2026-10-14 | Bonus 100 → **50 AP** (equal EHP to a biological Marine) | `BMAC_Shared.lua` (`kBMACBonusArmor`) |
| 2026-10-14 | Medpacks fully ignored: Commander snap, requests, bots; AP-based `GetHealthFraction` | `BMAC_Marine.lua`, edits 6-9 |
| 2026-10-14 | Exo-style AP panel in the bottom-left status area; then drawn square, number in Marine AP blue | `BMAC_GUIMarineStatus.lua` |
| 2026-10-14 | Lerk bite poison doesn't affect a BMAC (`Marine:SetPoisoned` wrap; poison cleared on becoming a BMAC). Without it, poison drained AP to death | `BMAC_Marine.lua`, `BMAC_Shared.lua` |
| 2026-10-14 | Fix: the newly picked skin showed on the Infantry Portal respawn hologram. The lock now also applies to the respawning `MarineSpectator` (round start, skin change, body copy); durability stays Marine-only | `BMAC_Shared.lua` |
| 2026-10-14 | Fix: the unit-status bar over a BMAC (e.g. when parasited) showed a red health section and "health/armour" text. AP-based `GetHealthFraction` is now server-only (bots), and a client hook gives a BMAC the Exo form (AP only) | `BMAC_Marine.lua`, new `BMAC_UnitStatus.lua`, FileHooks |
| 2026-10-14 | Medpacks now give a BMAC **25 AP** instead of 50 HP, and otherwise work as for a biological Marine (pickup, Commander target-assist, requests, self-medication, bots). Replaces "medpacks ignored": the Commander-snap, voice-route, manual-alert and bot-file medpack blocks were removed. New in-place edits: `MedSelf` payout and the `MED_PACK_TOOLTIP` text | `BMAC_MedPack.lua`, `RequestHandleMixin.lua`, `Locale.lua`; reverted `MarineCommander.lua`, `NetworkMessages_Server.lua`, three bot files |
| 2026-10-15 | **Per-round Marine choice:**<br>- "Choose Your Marine" window (Biological / BMAC / Random) and an owned-skin grid with Random, Back and Confirm.<br>- Normal and B.M.A.C. are free for everyone (changed to Normal and Chroma B.M.A.C. in the next row); anything unfinished is random.<br>- The round lock now comes from this choice instead of the options-menu skin.<br>- Choices are cleared when a round ends.<br>- Military Protocol re-skins every Marine to Chroma at once.<br>- New network message `BMACRoundChoice` (client to server). | `BMAC_Shared.lua`, `BMAC_Gamerules.lua`; new `BMAC_NetworkMessages.lua`, `BMAC_RoundChoice_Client.lua`, `GUIBMACRoundChoice.lua`, `BMAC_MarineTeam.lua`; FileHooks |
| 2026-10-15 | The free BMAC skin is now **Chroma B.M.A.C.** (a Competitive Play reward), not the base B.M.A.C., which is paid DLC and now needs ownership. The fallback BMAC skin is Chroma B.M.A.C. The skin grid's Random tile appears only with more than one skin, and the panel is sized to the tiles shown. | `BMAC_Shared.lua`, `GUIBMACRoundChoice.lua` |
| 2026-10-15 | **Ownership fix:** the server's ownership check always says "owned" (vanilla `GetOwnsItem` is `true` server-side), so its random pick could hand out unowned DLC skins.<br>- Clients now report their owned Marine skins (`BMACOwnedSkins`).<br>- The server only uses free skins and reported ones.<br>- Unowned options-menu skins are replaced by the free skin of the same body.<br>- Then made stricter: until the report arrives only free skins are worn, and the check runs in the same update as every skin application, so an unowned DLC skin is never worn at all. | `BMAC_Shared.lua`, `BMAC_NetworkMessages.lua`, `BMAC_RoundChoice_Client.lua` |

## Ports done

| Branch | Date | Notes |
|---|---|---|
| (none yet) | | |

When the BMAC content changes in Beta, copy the changed `CNBalance/BMAC/` files to every branch in this table, and re-apply any changed in-place edits by hand.
