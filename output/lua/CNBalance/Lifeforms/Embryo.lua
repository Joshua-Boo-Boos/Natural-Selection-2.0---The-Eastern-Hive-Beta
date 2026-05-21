Script.Load("lua/CNBalance/Mixin/RequestHandleMixin.lua")
local networkVars =
{
    evolvePercentage = "float",
    gestationTypeTechId = "enum kTechId",
    gestationHadCamouflage = "boolean",
}

AddMixinNetworkVars(BaseMoveMixin, networkVars)
AddMixinNetworkVars(GroundMoveMixin, networkVars)
AddMixinNetworkVars(CameraHolderMixin, networkVars)
AddMixinNetworkVars(EggVariantMixin, networkVars)
AddMixinNetworkVars(RequestHandleMixin,networkVars)

local baseOnCreate = Embryo.OnCreate
function Embryo:OnCreate()
    baseOnCreate(self)
    InitMixin(self,RequestHandleMixin)
    self.gestationHadCamouflage = false
end

-- Vanilla Embryo:SetGestationData calls ClearUpgrades() at the end, wiping the
-- upgrade1..6 fields that CopyPlayerDataFrom just copied from the previous
-- alien. That makes GetHasUpgrade(Camouflage) return false during gestation,
-- which would break the rule that "had camo before evolving → stay
-- camouflaged through gestation".
--
-- Capture the prior camouflage state into a networked flag BEFORE the base
-- call so GetIsCamouflaged can read it for the duration of the gestation.
local baseSetGestationData = Embryo.SetGestationData
function Embryo:SetGestationData(techIds, previousTechId, healthScalar, armorScalar)

    self.gestationHadCamouflage = self.GetHasUpgrade and self:GetHasUpgrade(kTechId.Camouflage) or false

    baseSetGestationData(self, techIds, previousTechId, healthScalar, armorScalar)

end

function Embryo:GetIsCamouflaged()
    return self.gestationHadCamouflage == true
end

Shared.LinkClassToMap("Embryo", Embryo.kMapName, networkVars)
