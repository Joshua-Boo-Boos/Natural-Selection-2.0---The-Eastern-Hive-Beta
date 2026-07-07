-- CNBalance/Weapons/ExoWeaponHolderModels.lua
--
-- Overrides ExoWeaponHolder:GetViewModelName() and :GetAnimationGraphName()
-- so that the 10 new prototype exo combos get the correct first-person chassis
-- model and animation graph.
--
-- Loaded post lua/Weapons/Marine/ExoWeaponHolder.lua (via FileHooks.lua).
-- ExoWeaponHolder.lua is Script.Load-ed by Exo.lua (line 13), so this file
-- runs partway through Exo.lua's load — before CNBalance/Exo.lua has defined
-- the kPrototypeChassis* tables.  That is fine: this file only DEFINES
-- functions; the tables are globals looked up at call-time (runtime), by which
-- point CNBalance/Exo.lua has long since run and the tables exist.
--
-- Ordering guarantee (why comboChassis is always set before GetViewModelName runs):
--   1. Server Exo:OnInitialized calls self:InitExoModel()  ← sets self.comboChassis
--   2. OnInitialized then calls Player.OnInitialized(self) ← calls InitWeapons
--   3. InitWeapons calls weaponHolder:SetWeapons(...)
--   4. SetWeapons (vanilla) calls self:GetViewModelName()  ← reads exo.comboChassis
-- Steps 1→4 are sequential on the server; comboChassis is ALWAYS written
-- before GetViewModelName is invoked.  No networked field is needed because
-- SetViewModel networks the resolved model+graph path to clients automatically.
--
-- Fallback: if the parent Exo has no comboChassis (vanilla commander-drop exo
-- without this mod's InitExoModel path running), we call the original vanilla
-- GetViewModelName / GetAnimationGraphName which uses weaponSetupName lookup —
-- so all existing vanilla layouts keep working.

-- GetViewModelName and GetAnimationGraphName are Server-only in vanilla
-- (defined inside `if Server then` in ExoWeaponHolder.lua), so only
-- override them on the server where they exist.
if Server then

    -- ── GetViewModelName override ─────────────────────────────────────────────
    local baseGetViewModelName = ExoWeaponHolder.GetViewModelName
    function ExoWeaponHolder:GetViewModelName()
        local exo     = self:GetParent()
        local chassis = exo and exo.comboChassis
        if chassis and kPrototypeChassisViewModel and kPrototypeChassisViewModel[chassis] then
            return kPrototypeChassisViewModel[chassis]
        end
        return baseGetViewModelName(self)
    end

    -- ── GetAnimationGraphName override ────────────────────────────────────────
    local baseGetAnimationGraphName = ExoWeaponHolder.GetAnimationGraphName
    function ExoWeaponHolder:GetAnimationGraphName()
        local exo     = self:GetParent()
        local chassis = exo and exo.comboChassis
        if chassis and kPrototypeChassisViewGraph and kPrototypeChassisViewGraph[chassis] then
            return kPrototypeChassisViewGraph[chassis]
        end
        return baseGetAnimationGraphName(self)
    end

end

-- ── GetDeathIconIndex override (Self-Destruct killfeed icon) ────────────────
-- TriggerExoSelfDestruct (CNBalance/Exo.lua) uses this entity as its preferred
-- `doer` for RadiusDamage ("ExoWeaponHolder.kMapName is the exo's own
-- always-present built-in weapon... a far more direct and reliable source" -
-- Exo.lua's own comment). Without this override it fell through to
-- ScriptActor:GetDeathIconIndex()'s default (kDeathMessageIcon.None already,
-- coincidentally) with console text printing literally "None" - this instead
-- gives the correct "ExoSelfDestruct" console text (kDeathMessageIcon.ExoSelfDestruct
-- appended in CNBalance/Globals.lua) while still showing the None icon art
-- (redirected in CNBalance/GUI/GUIDeathMessagesExo.lua).
function ExoWeaponHolder:GetDeathIconIndex()
    return kDeathMessageIcon.ExoSelfDestruct
end
