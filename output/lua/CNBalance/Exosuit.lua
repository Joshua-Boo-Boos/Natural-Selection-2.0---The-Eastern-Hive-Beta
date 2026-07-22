Script.Load("lua/PointGiverMixin.lua")

-- The Exosuit's own spawn/eject animation graph (the graph vanilla
-- Exosuit:SetLayout uses, a file-local we can't reference from this hook). It
-- is authored for the shared exosuit skeleton, so it binds to ALL chassis
-- models (mm/cm/rr/cr) - unlike the Exo's per-chassis COMBAT graph, which
-- expects the Exo's animation-input setup the static Exosuit entity lacks.
local kExosuitEjectGraph = PrecacheAsset("models/marine/exosuit/exosuit_spawn_animated.animation_graph")

local baseOnCreate = Exosuit.OnCreate
function Exosuit:OnCreate()
    baseOnCreate(self)
    InitMixin(self, PointGiverMixin)
end

function Exosuit:GetTechId()
    return kTechId.Exosuit
end

-- Carry the ejecting exo's prototype upgrades onto this dropped Exosuit.
-- Exo:PerformEject (CNBalance/Exo.lua) sets _G.gEjectingExoPrototypeBits just
-- before it calls exosuit:SetLayout(...), so this runs while that global is live.
-- Stored as a plain server-side Lua field (eject and re-enter are both server).
local baseExosuitSetLayout = Exosuit.SetLayout
function Exosuit:SetLayout(layout)
    baseExosuitSetLayout(self, layout)

    -- Vanilla Exosuit:SetLayout (NS2-Copy/ns2/lua/Exosuit.lua:169-172) only maps
    -- "MinigunMinigun"/"RailgunRailgun" to world models and defaults everything
    -- else to exosuit_mm (dual minigun) - so a dropped exosuit from any other
    -- prototype layout (Claw/Railgun, Flamethrower, GL, etc.) showed the WRONG
    -- dual-minigun model. Set the correct per-chassis world model here.
    -- IMPORTANT: pair it with the Exosuit's OWN eject/spawn graph, NOT the Exo's
    -- per-chassis COMBAT graph - the combat graph expects the Exo's
    -- animation-input setup that this static Exosuit entity does not have, so
    -- SetModel with it fails and the model stays at the base dual-minigun default
    -- (this was the bug: the world model never actually changed).
    local entry = kPrototypeExoLayouts and kPrototypeExoLayouts[layout]
    if entry and entry.chassis and kPrototypeChassisWorldModel[entry.chassis] then
        -- pcall so an unexpected model/graph binding failure degrades to the
        -- base (dual-minigun) model instead of hard-crashing the eject.
        pcall(function()
            self:SetModel(kPrototypeChassisWorldModel[entry.chassis], kExosuitEjectGraph)
        end)
    end

    if _G.gEjectingExoPrototypeBits ~= nil then
        self.storedPrototypeUpgradeBits = _G.gEjectingExoPrototypeBits
    end
    -- Resupply charges remaining (out of 10) — same eject-time global handoff,
    -- so the ammopack count stays constant across eject/re-enter.
    if _G.gEjectingExoResupplyCharges ~= nil then
        self.storedResupplyCharges = _G.gEjectingExoResupplyCharges
    end
end

if Server then

    function Exosuit:OnUseDeferred()

        local player = self.useRecipient
        self.useRecipient = nil

        if player and not player:GetIsDestroyed() and self:GetIsValidRecipient(player) then

            local weapons = player:GetWeapons()
            for i = 1, #weapons do
                weapons[i]:SetParent(nil)
            end

            local exoPlayer

            if self.layout == "MinigunMinigun" then
                exoPlayer = player:GiveDualExo()
            elseif self.layout == "RailgunRailgun" then
                exoPlayer = player:GiveDualRailgunExo()
            elseif self.layout == "ClawRailgun" then
                exoPlayer = player:GiveClawRailgunExo()
            else
                -- Prototype layout: pass layout directly so InitWeapons creates the right arms.
                exoPlayer = player:Replace(Exo.kMapName, player:GetTeamNumber(), false, nil,
                                           { layout = self.layout })
            end

            if exoPlayer then

                for i = 1, #weapons do
                    exoPlayer:StoreWeapon(weapons[i])
                end

                exoPlayer:SetMaxArmor(self:GetMaxArmor())
                exoPlayer:SetArmor(self:GetArmor())
                exoPlayer:SetFlashlightOn(self:GetFlashlightOn())
                exoPlayer:TransferParasite(self)
                exoPlayer:TransferExoVariant(self)

                -- Restore prototype upgrades stored when the exo was ejected
                -- (Lifeform Scanner, Resupply, Boost, Armour Plating, etc.) so the
                -- HUD panels and upgrade behaviour return with the re-entered exo.
                -- Set the bits directly (do NOT recompute armour here — the exosuit
                -- already carries the correct stored armour, which we copied above).
                if self.storedPrototypeUpgradeBits ~= nil then
                    exoPlayer.prototypeUpgradeBits = self.storedPrototypeUpgradeBits
                end
                if self.storedResupplyCharges ~= nil then
                    exoPlayer.resupplyChargesRemaining = self.storedResupplyCharges
                end

                -- Set the auto-weld cooldown of the player exo to match the cooldown of the dropped
                -- exo.
                local now = Shared.GetTime()
                local timeLastDamage = self:GetTimeOfLastDamage() or 0
                local waitEnd = timeLastDamage + kCombatTimeOut
                local cooldownEnd = math.max(waitEnd, self.timeNextWeld)
                local cooldownRemaining = math.max(0, cooldownEnd - now)
                exoPlayer.timeNextWeld = now + cooldownRemaining

                local newAngles = player:GetViewAngles()
                newAngles.pitch = 0
                newAngles.roll = 0
                newAngles.yaw = GetYawFromVector(self:GetCoords().zAxis)
                exoPlayer:SetOffsetAngles(newAngles)
                -- the coords of this entity are the same as the players coords when he left the exo, so reuse these coords to prevent getting stuck
                exoPlayer:SetCoords(self:GetCoords())

                player:TriggerEffects("pickup", { effectshostcoords = self:GetCoords() })

                DestroyEntity(self)

            end

        end

    end


    function Exosuit:GetAutoWeldArmorPerSecond(nanoArmorResearched)
        return nanoArmorResearched and kExoNanoArmorPerSecond or kExoArmorPerSecond
    end

end

function Exosuit:GetExoVariantOverride(variant)
    -- Mirror Exo:GetExoVariantOverride (CNBalance/Exo.lua): claw chassis have
    -- no Chroma-variant cosmetic material, so force the normal skin to avoid
    -- a GetPrecachedCosmeticMaterial assertion when this dropped Exosuit runs
    -- its skin update. Detect claw via the layout's chassis (cm/cr = claw).
    local entry = kPrototypeExoLayouts and kPrototypeExoLayouts[self.layout]
    local hasClaw = entry and (entry.chassis == "cm" or entry.chassis == "cr")

    if GetHasTech(self,kTechId.MilitaryProtocol) then
        return hasClaw and kExoVariants.normal or kExoVariants.chroma
    end

    -- BUG FIX: same gap as Exo.lua - a manually-selected Chroma skin
    -- (independent of Military Protocol) previously bypassed the claw guard
    -- entirely, falling through to "return variant" unchecked.
    if hasClaw and variant == kExoVariants.chroma then
        return kExoVariants.normal
    end

    return variant
end
