-- CNBalance/Mixin/PrototypeUpgradesMixin.lua
-- Stores experimental Prototype upgrades as a single networked integer bit-mask.
-- (Limited port: only the kept exo upgrades have bits; no Jumppack/Boost bit.)
PrototypeUpgradesMixin = CreateMixin(PrototypeUpgradesMixin)
PrototypeUpgradesMixin.type = "PrototypeUpgrades"

-- Stable techId -> bit index map, in kPrototypeUpgradesForTrack order (jetpack, exo,
-- cannon). Jetpack/cannon lists are empty in this port, so only exo upgrades get bits.
local kBit = {}
do
    local i = 0
    for _, track in ipairs({ "jetpack", "exo", "cannon" }) do
        for _, techId in ipairs(kPrototypeUpgradesForTrack[track]) do
            kBit[techId] = i
            i = i + 1
        end
    end
end
PrototypeUpgradesMixin.kBit = kBit

-- Networked so the client sees the upgrades (HUD, fuel prediction, armour bar).
-- The Exo class is re-linked with this var in CNBalance/Exo.lua; Shared.LinkClassToMap
-- MERGES network vars (it never wipes the existing set), so this only ADDS one field.
PrototypeUpgradesMixin.networkVars =
{
    prototypeUpgradeBits = "integer",
}

function PrototypeUpgradesMixin:__initmixin()
    self.prototypeUpgradeBits = 0
end

function PrototypeUpgradesMixin:GetHasPrototypeUpgrade(techId)
    local bit = kBit[techId]
    if not bit then return false end
    local mask = 2 ^ bit
    return math.floor(self.prototypeUpgradeBits / mask) % 2 == 1
end

function PrototypeUpgradesMixin:SetPrototypeUpgrade(techId, value)
    local bit = kBit[techId]
    if not bit then return end
    local mask = 2 ^ bit
    local has = self:GetHasPrototypeUpgrade(techId)
    if value and not has then
        self.prototypeUpgradeBits = self.prototypeUpgradeBits + mask
    elseif not value and has then
        self.prototypeUpgradeBits = self.prototypeUpgradeBits - mask
    end
end

function PrototypeUpgradesMixin:GetPrototypeUpgradeList()
    local list = {}
    for techId in pairs(kBit) do
        if self:GetHasPrototypeUpgrade(techId) then
            table.insert(list, techId)
        end
    end
    return list
end
