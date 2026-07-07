-- CNBalance/Mixin/PrototypeUpgradesMixin.lua
-- Stores experimental Prototype upgrades as a single networked integer bit-mask.
PrototypeUpgradesMixin = CreateMixin(PrototypeUpgradesMixin)
PrototypeUpgradesMixin.type = "PrototypeUpgrades"

-- Stable techId -> bit index map. Order is FIXED (jetpack, exo, cannon, in
-- kPrototypeUpgradesForTrack order) so the network bit for an upgrade never moves.
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
