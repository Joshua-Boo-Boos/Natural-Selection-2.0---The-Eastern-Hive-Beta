--[[
    CLIENT-ONLY: keep the hive-sight outline attached when an entity's render model is replaced.

    THE BUG
    -------
    HiveVisionMixin binds the outline to a specific RENDER MODEL INSTANCE:

        HiveVision_AddModel( model, kHiveVisionOutlineColor.Yellow )

    ...and then only ever revisits that binding when VISIBILITY CHANGES:

        if visible ~= self.hiveSightVisible and self.timeHiveVisionChanged + 1 < now then

    When the model instance is swapped while visibility stays the same -- a structure whose render
    state churns as it is built, damaged, corroded by bile, or animates its linked state -- the
    outline dies with the old model while `visible` and `hiveSightVisible` are BOTH still true. The
    guard never fires, nothing re-binds, and a still-parasited structure silently stops being
    outlined for the rest of the parasite's 44 seconds.

    WHY IT ONLY AFFECTED STRUCTURES
    -------------------------------
    A player's render model is stable and their OnUpdate runs every frame, so even a lost binding is
    re-evaluated and restored before it could be noticed. Structures churn their render state and do
    not update as predictably, so a lost binding simply stays lost.

    THE FIX
    -------
    Remember which model instance the outline is bound to. If it stops matching the entity's current
    render model, RE-BIND IMMEDIATELY in the same frame.

    Re-binding directly rather than clearing hiveSightVisible and waiting for vanilla to notice is
    deliberate: vanilla's re-add is edge-triggered AND debounced by a second, so it needs at least one
    further OnUpdate to fire -- exactly what a structure cannot be relied upon to provide. Because
    hiveSightVisible is already true here, vanilla has ALREADY decided this entity should be
    outlined, so no visibility rule is being second-guessed; only the binding moves.

    This deliberately does not reimplement vanilla's OnUpdate: GetMaxDistanceFor and GetIsObscurred
    are file-locals in HiveVisionMixin.lua and unreachable from a post-hook, so copying that body
    would silently break the distance and team rules.

    The parasite STATE was never at fault. Nothing clears it for structures except expiry and death;
    RemoveParasite is only ever called on players (armoury, observatory, weapon cache, console), and
    the flamethrower does not touch it. This is purely a rendering repair.
]]

if not Client then return end

-- Mirrors vanilla's colour choice for an outline that is already deemed visible.
local function GetHiveVisionColour(entity)

    if HasMixin(entity, "ParasiteAble") and entity:GetIsParasited() then
        return kHiveVisionOutlineColor.Yellow
    end

    if entity:isa("Gorge") then
        return kHiveVisionOutlineColor.DarkGreen
    end

    return kHiveVisionOutlineColor.Green

end

local baseHiveVisionOnUpdate = HiveVisionMixin.OnUpdate

if baseHiveVisionOnUpdate then

    function HiveVisionMixin:OnUpdate(deltaTime)

        baseHiveVisionOnUpdate(self, deltaTime)

        if not self.hiveSightVisible then
            self.ceHiveSightModel = nil
            return
        end

        -- Guarded: an entity carrying this mixin does not always have a render model.
        local model = self.GetRenderModel and self:GetRenderModel() or nil
        if model == nil then
            return
        end

        if self.ceHiveSightModel == nil then
            -- First frame we have seen this binding; just record it.
            self.ceHiveSightModel = model
            return
        end

        if model ~= self.ceHiveSightModel then

            -- The old instance is usually already destroyed, so removing it can fail harmlessly.
            pcall( HiveVision_RemoveModel, self.ceHiveSightModel )

            HiveVision_AddModel( model, GetHiveVisionColour( self ) )
            self.ceHiveSightModel = model

        end

    end

end

-- Vanilla clears hiveSightVisible here so its own next update re-adds. Drop our tracked instance in
-- step, so that normal path is not mistaken for a swap on the following frame.
local baseHiveVisionOnModelChanged = HiveVisionMixin.OnModelChanged

if baseHiveVisionOnModelChanged then

    function HiveVisionMixin:OnModelChanged(index)
        self.ceHiveSightModel = nil
        return baseHiveVisionOnModelChanged(self, index)
    end

end

-- Release the tracked instance with the entity, so nothing holds a stale model reference.
local baseHiveVisionOnDestroy = HiveVisionMixin.OnDestroy

if baseHiveVisionOnDestroy then

    function HiveVisionMixin:OnDestroy()
        self.ceHiveSightModel = nil
        return baseHiveVisionOnDestroy(self)
    end

end
