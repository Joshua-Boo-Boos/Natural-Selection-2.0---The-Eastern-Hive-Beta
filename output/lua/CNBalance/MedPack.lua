

--[[
    (2026-10-28) THE COMMANDER'S MEDPACK HAS TWO MODES - MULTI MEDPACK (the default) and AREA HEAL - switched by the Marine
    Commander with the MIDDLE MOUSE BUTTON while the big map is closed (CNBalance/MedPackModeUI.lua: the button icon,
    its name and tooltip, and the "Medpack Mode:" line in the bottom-right of the Commander's screen). Every new Commander
    starts in Multi Medpack. The mode is sent to the server (network message "TEHMedMode"); the existing MedPack class
    is reused for both, so no networked class or variable is added.

    MULTI MEDPACK (1 team res PER MEDPACK GIVEN, kMedPackCost in Balance.lua):
      * Every Marine / Jetpack Marine within kMultiMedRadius (4.5 m) who NEEDS a medpack (MedPack:GetIsValidRecipient)
        gets one at once - the normal medpack heal, sound and effect on each Marine healed - and the medpack is gone.
        Exos never get one. When there is NO Marine at all inside the ring, it is left as ONE normal medpack on the
        ground (1 team res) for anyone to pick up; Marines in the ring but none needing one - refused.
      * (2026-10-28) NO AUTO-LOCK: NS2's lock onto a targeted Marine is switched off for the medpack (CNBalance/
        TechData.lua, kTechDataOverrideCoordsMethod) - the drop goes on the floor right under the cursor.
      * The Commander sees the 4.5 m ring at the cursor.

    AREA HEAL (kMedFieldCost = 2 team res a field):
      * A sentry battery MESH (just the model - it powers nothing), tinted blue, is placed where the medpack is dropped.
      * For kMedFieldDuration (5) seconds, each second every living Marine / Jetpack Marine (never an Exo) within
        kMedFieldRadius (4.5 m) below full health gets kMedFieldTickHeal (8) health - 40 over the 5 seconds - and the
        medpack pickup sound. (A BMAC, in a mod that has them, gets the armour equal.)
      * Its area is shown to EVERY player as a solid, full-size ring on the ground for the whole 5 seconds, with
        translucent blue "+" icons floating up and down inside it.
      * It can be placed anywhere the team can pay kMedFieldCost (MedPack_GetPlacementAllowed).
      * NO OVERLAPS: a new field whose area would overlap an older one removes the older one.
      * The Commander sees the 4.5 m ring at the cursor, and the placement ghost is the sentry battery
        (CNBalance/MedPackModeUI.lua swaps the medpack's ghost model with the mode).
]]
kMultiMedRadius = 4.5   -- (2026-10-28) was 5 (and 3 before that); the same as Area Heal's

kMedFieldDuration = 5     -- (2026-10-28) was 10
kMedFieldTickHeal = 8     -- (2026-10-28) was 4: 8 health a second for 5 seconds
kMedFieldRadius = 4.5     -- (2026-10-28) was 4; the same as Multi Medpack's
kMedFieldCost = 2         -- team res a field (the drop itself charges kMedPackCost; the rest is taken on placement)

local kFieldModelName = PrecacheAsset("models/marine/portable_node/portable_node.model")
MedPack.kFieldModelName = kFieldModelName   -- the Area Heal placement ghost (CNBalance/MedPackModeUI.lua)
local kFieldGraph = PrecacheAsset("models/marine/portable_node/portable_node.animation_graph")
local kFieldTint = PrecacheAsset("materials/teh/medfield_blue.material")
local kFieldRingMaterial = PrecacheAsset("models/misc/circle/circle.material")
local kFieldRingLayers = 3   -- the ring decal drawn this many times over itself: strong and easy to see

-- ---- The mode: sent by the Commander's game, kept per client on the server ---------------------------------------
if not TEHMedModeMessageRegistered then
    TEHMedModeMessageRegistered = true
    Shared.RegisterNetworkMessage("TEHMedMode", { areaHeal = "boolean" })
end

local serverModes = setmetatable({}, { __mode = "k" })
if Server then
    Server.HookNetworkMessage("TEHMedMode", function(client, message)
        if client then serverModes[client] = message.areaHeal == true end
    end)

    -- (2026-10-28) The Marine Commander BOT switches its own mode (CNBalance/MedFieldBots.lua) - it has no game to send it.
    function MedPack_SetServerAreaHeal(client, areaHeal)
        if client then serverModes[client] = areaHeal == true end
    end
end

-- True when this Commander's medpack is in Area Heal mode. On the Commander's own game: the mode they chose
-- (CNBalance/MedPackModeUI.lua); on the server: the mode their game last sent. Bots and everyone else: Multi Medpack.
function MedPack_IsAreaHeal(commander)
    if Client then
        return TEHMedMode_IsAreaHeal ~= nil and TEHMedMode_IsAreaHeal() == true
    end
    if Server then
        local client = commander and commander.GetClient and commander:GetClient()
        return client ~= nil and serverModes[client] == true
    end
    return false
end

local function IsMedTarget(player)
    return player:isa("Marine") and not player:isa("Exo") and player.GetIsAlive and player:GetIsAlive()
end

local function RemoveMultiMed(self)
    DestroyEntity(self)
    return false
end

--[[
    (2026-10-28) THE HEAL AREA IS A COLUMN, for both modes: within the ring's radius across the floor (4.5 m for both
    modes), from the height the medpack / field was placed at (kHealColumnBelow lower, for slopes and steps) up
    to kHealColumnHeight above it - so a Jetpack Marine flying over the ring is healed too, both modes also reach 3 metres below their placement height - and with a clear line from just above the drop point to the Marine, so nobody is healed through a
    ceiling or floor.
]]
kHealColumnHeight = 12
-- Both modes measure their cylinder from the server-registered placement origin.
kHealColumnBelow = 3
kMedFieldBelow = kHealColumnBelow

local function InHealColumn(player, origin, radius, below)
    local point = player:GetOrigin()
    local dy = point.y - origin.y
    if dy < -(below or kHealColumnBelow) or dy > kHealColumnHeight then return false end
    local dx, dz = point.x - origin.x, point.z - origin.z
    if dx * dx + dz * dz > radius * radius then return false end
    local trace = Shared.TraceRay(origin + Vector(0, 0.5, 0), point + Vector(0, 1, 0),
        CollisionRep.LOS, PhysicsMask.Bullets, EntityFilterAll())
    return trace.fraction > 0.98
end

-- Every live Marine / Jetpack Marine of `team` inside the heal column at `origin`, NEAREST TO THE CENTRE FIRST (distance
-- across the floor) - so when a Multi Medpack runs out of team res, the Marines closest to the middle got theirs.
local function GetColumnTargets(team, origin, radius, below)
    local targets, distances = {}, {}
    for _, player in ipairs(GetEntitiesForTeamWithinXZRange("Player", team, origin, radius)) do
        if IsMedTarget(player) and InHealColumn(player, origin, radius, below) then
            targets[#targets + 1] = player
            local point = player:GetOrigin()
            distances[player] = (point.x - origin.x) ^ 2 + (point.z - origin.z) ^ 2
        end
    end
    table.sort(targets, function(a, b) return distances[a] < distances[b] end)
    return targets
end

-- (2026-10-28) For the Marine Commander bot (CNBalance/MedFieldBots.lua): exactly who a drop clicked at `point` would
-- reach - the placement origin, the heal column, nearest the centre first.
function MedPack_GetColumnTargets(team, point, radius)
    return GetColumnTargets(team, point, radius)
end

-- (2026-10-28) Field Marine bots' FIND MEDPACK (bots/MarineBrain_Data.lua): a medpack worth walking to. An Area Heal
-- field only while the bot is outside its heal column (inside, it is already being healed - keep fighting); a
-- multi-med that is being used up (hidden) never.
function MedPack_BotShouldSeek(marine, med)
    if not med or (med.GetIsVisible and not med:GetIsVisible()) then return false end
    if med.tehIsField then
        return not InHealColumn(marine, med.tehHealOrigin or med:GetOrigin(), kMedFieldRadius, kMedFieldBelow)
    end
    return true
end

--[[
    PLACEMENT CHECK (kTechDataBuildRequiresMethod, set on the medpack's tech data in CNBalance/TechData.lua; NS2 runs it
    for the Commander's placement ghost on the client and again on the server before charging):
      * Area Heal: anywhere the team can pay the field's kMedFieldCost (otherwise the ghost is invalid, with the reason).
      * Multi Medpack (its 1 team res is NS2's normal cost check):
          - NO Marine at all in the ring: allowed - it is left as one medpack on the ground (MedPack:OnInitialized);
          - Marines in the ring and at least one needs a medpack: allowed - only those who need one get one;
          - Marines in the ring but none needs a medpack: refused (nothing placed or charged).
]]
function MedPack_GetPlacementAllowed(techId, origin, normal, commander)
    local team = commander and commander.GetTeamNumber and commander:GetTeamNumber()
    if not team or not origin then return true end
    if MedPack_IsAreaHeal(commander) then
        local res = commander.GetTeamResources and commander:GetTeamResources()
        if type(res) == "number" and res < kMedFieldCost then
            return false, "COMMANDERERROR_MEDFIELD_RES"
        end
        return true   -- (2026-10-28) a field can be placed anywhere the team can pay for it
    end
    local targets = GetColumnTargets(team, origin, kMultiMedRadius)
    if #targets == 0 then return true end
    for _, player in ipairs(targets) do
        if MedPack.GetIsValidRecipient(MedPack, player) then return true end
    end
    return false, "COMMANDERERROR_MULTIMED_NOBODY"
end

-- ---- Area Heal field (server) -------------------------------------------------------------------------------------
local function EndField(self)
    DestroyEntity(self)
    return false
end

local function PlayHealSound(player)
    player:TriggerEffects("medpack_pickup", { effecthostcoords = Coords.GetTranslation(player:GetOrigin()) })
end

local function HealTick(self)
    local origin = self.tehHealOrigin or self:GetOrigin()   -- where the field was placed: the column's reference height
    for _, player in ipairs(GetColumnTargets(self:GetTeamNumber(), origin, kMedFieldRadius, kMedFieldBelow)) do
        do
            -- Healed (health, or a BMAC's armour) -> the medpack pickup sound on that Marine; full -> nothing.
            if GetIsBMACMarine and GetIsBMACMarine(player) then
                if player:GetArmor() < player:GetMaxArmor() then
                    player:AddArmor(kMedFieldTickHeal / (kHealthPointsPerArmor or 2), false, true)
                    PlayHealSound(player)
                end
            elseif player:GetHealth() < player:GetMaxHealth() then
                player:AddHealth(kMedFieldTickHeal, false, true, true)
                PlayHealSound(player)
            end
        end
    end
    return true   -- every second until the field is removed
end

local function StartField(self, teamEntity)
    self:SetModel(kFieldModelName, kFieldGraph)
    self.tehIsField = true
    self.tehHealOrigin = Vector(self:GetOrigin())   -- the heal column's reference height: where it was placed
    self.pickupRange = 0                                   -- nobody picks it up
    self.expireTime = Shared.GetTime() + kMedFieldDuration
    self:AddTimedCallback(EndField, kMedFieldDuration + 0.05)   -- just after the last (5th) heal
    self:AddTimedCallback(HealTick, 1)

    -- The drop charged kMedPackCost; the field costs kMedFieldCost (the placement check made sure the team can pay).
    local extra = kMedFieldCost - (kMedPackCost or 1)
    if extra > 0 and teamEntity and teamEntity.GetTeamResources and teamEntity:GetTeamResources() >= extra then
        teamEntity:AddTeamResources(-extra)
    end

    -- No overlaps: older fields whose area would overlap this one go.
    local origin = self:GetOrigin()
    for _, other in ientitylist(Shared.GetEntitiesWithClassname("MedPack")) do
        if other ~= self and other.tehIsField and (other:GetOrigin() - origin):GetLength() < kMedFieldRadius * 2 then
            DestroyEntity(other)
        end
    end
end

local function GetNormalModelName()
    return (GetSeason and GetSeason() == Seasons.kWinter) and MedPack.kModelNameWinter or MedPack.kModelName
end

function MedPack:OnInitialized()

    DropPack.OnInitialized(self)

    if not Server then return end   -- the model, and whether this is a field, come from the server

    -- Use the registered entity placement point without projecting it onto a lower floor.
    local origin = Vector(self:GetOrigin())
    local team = self:GetTeamNumber()
    local teamEntity = GetGamerules and GetGamerules():GetTeam(team)
    local commander = teamEntity and teamEntity.GetCommander and teamEntity:GetCommander()

    if MedPack_IsAreaHeal(commander) then
        StartField(self, teamEntity)
        return
    end

    -- (2026-10-28) the normal medpack model (it was missing)
    self:SetModel(GetNormalModelName())

    --[[
        A multi-med (no lock onto a Marine any more): a medpack for every Marine within 4.5 m who needs one, then gone.
        1 team res PER MEDPACK, no limit on how many: the drop itself paid for the first (kMedPackCost), each further
        Marine costs 1 more while the team can pay it.
        (2026-10-28) NO MARINE AT ALL IN THE RING: the drop stays as ONE NORMAL MEDPACK on the ground (its 1 team res
        already paid by the drop) for anyone who needs it to walk over and pick up - so a Commander can lay a trail of
        them for Marines near the ring. With Marines in the ring, no medpack is ever left on the ground.
    ]]
    local pickupRange = self.pickupRange   -- DropPack's normal pickup range, kept for the medpack-on-the-ground case
    self.pickupRange = 0
    local given = 0
    local targets = GetColumnTargets(team, origin, kMultiMedRadius)
    for _, player in ipairs(targets) do
        if self:GetIsValidRecipient(player) then
            local paid = given == 0   -- the first medpack was paid for by the drop
            if not paid and teamEntity and teamEntity.GetTeamResources
                    and teamEntity:GetTeamResources() >= kMedPackCost then
                teamEntity:AddTeamResources(-kMedPackCost)
                paid = true
            end
            if not paid then break end   -- out of team res: nobody further gets one
            self:OnTouch(player)   -- the normal medpack heal, sound and effect (a BMAC: its armour)
            given = given + 1
        end
    end
    if given == 0 and #targets == 0 then
        self.pickupRange = pickupRange   -- nobody in the ring: a normal medpack on the ground, picked up as usual
        return
    end
    if given == 0 and teamEntity and teamEntity.SetTeamResources and teamEntity.GetTeamResources then
        -- Marines in the ring but none needed one (the placement check refuses this; it can only happen if their
        -- health changed in between): the drop's cost back - never past the team res cap (kMaxTeamResources, 200).
        -- Set directly rather than through AddTeamResources, which may also pay out the team's stored income fraction.
        teamEntity:SetTeamResources(math.min(kMaxTeamResources or 200, teamEntity:GetTeamResources() + kMedPackCost))
    end
    self:SetIsVisible(false)
    self:AddTimedCallback(RemoveMultiMed, 0.05)

end

if Client then

    -- ---- Area Heal field visuals: everyone sees them ------------------------------------------------------------
    local fieldModelIndex
    local function IsField(self)
        fieldModelIndex = fieldModelIndex or Shared.GetModelIndex(kFieldModelName)
        return fieldModelIndex ~= nil and fieldModelIndex ~= 0 and self.modelIndex == fieldModelIndex
    end

    -- A solid ring on the ground, the field's full 4.5 m healing area, static for its whole 5 seconds (the old expanding
    -- power-node cinematic is gone: it is a binary asset that cannot be held at full size). Drawn several times over
    -- itself so it is strong and easy to see, for every player.
    function MedPack:OnUpdateRender()
        if not IsField(self) then return end
        if not self.tehFieldRings then
            self.tehFieldRings = {}
            pcall(Shared.RemoveTagFromEntity, self:GetId(), "Pickupable")   -- not an item to walk over
            for i = 1, kFieldRingLayers do
                local decal = Client.CreateRenderDecal()
                local material = Client.CreateRenderMaterial()
                material:SetMaterial(kFieldRingMaterial)
                decal:SetMaterial(material)
                decal:SetExtents(Vector(1, 1, 1) * kMedFieldRadius)
                self.tehFieldRings[i] = { decal = decal, material = material }
            end
        end
        local coords = Coords.GetTranslation(self:GetOrigin())   -- follows the battery while it settles
        for _, ring in ipairs(self.tehFieldRings) do ring.decal:SetCoords(coords) end

        local model = self.GetRenderModel and self:GetRenderModel()
        if model and self.fieldTintModel ~= model then
            self.fieldTintModel = model
            AddMaterial(model, kFieldTint)
        end

        local ok, err = pcall(MedPack.UpdateFieldPluses, self)
        if not ok and not MedPack.tehPlusError then
            MedPack.tehPlusError = true
            Shared.Message("[Area Heal] floating + icons: " .. tostring(err))
        end
    end

    --[[
        (2026-10-28) FLOATING "+" ICONS inside the Area Heal ring, for every player: kFieldPlusCount translucent blue
        "+" signs spread over the 4.5 m area, each bobbing slowly up and down. They are screen icons placed at their
        world spots every frame (Client.WorldToScreen), smaller with distance, and hidden behind walls (a trace from
        the camera) and behind the camera - so they read as part of the field without any new 3D asset.
    ]]
    local kFieldPlusCount = 12
    local kFieldPlusColour = { 0.35, 0.75, 1.0 }
    local kFieldPlusAlpha = 0.6
    local kGoldenAngle = math.pi * (3 - math.sqrt(5))

    local function DestroyPluses(self)
        if self.tehFieldPluses then
            for _, plus in ipairs(self.tehFieldPluses) do GUI.DestroyItem(plus.item) end
            self.tehFieldPluses = nil
        end
    end

    function MedPack.UpdateFieldPluses(self)
        if not self.tehFieldPluses then
            self.tehFieldPluses = {}
            for i = 1, kFieldPlusCount do
                local item = GUI.CreateItem()
                item:SetOptionFlag(GUIItem.ManageRender)
                item:SetFontName(Fonts.kAgencyFB_Large)
                item:SetText("+")
                item:SetTextAlignmentX(GUIItem.Align_Center)
                item:SetTextAlignmentY(GUIItem.Align_Center)
                item:SetLayer(kGUILayerPlayerHUDBackground or 0)
                item:SetIsVisible(false)
                -- Spread evenly over the disc (sunflower pattern), at different heights and bob speeds.
                local angle = i * kGoldenAngle
                local radius = kMedFieldRadius * 0.9 * math.sqrt((i - 0.5) / kFieldPlusCount)
                self.tehFieldPluses[i] = {
                    item = item,
                    dx = math.cos(angle) * radius, dz = math.sin(angle) * radius,
                    height = 0.4 + (i % 4) * 0.35, phase = i * 1.7, speed = 1.2 + (i % 3) * 0.3,
                }
            end
        end

        local camera = GetRenderCameraCoords()
        if not camera then return end
        local origin = self:GetOrigin()
        local now = Shared.GetTime()
        local scaleBase = GUIScale and GUIScale(1) or 1
        for _, plus in ipairs(self.tehFieldPluses) do
            local point = origin + Vector(plus.dx, plus.height + math.sin(now * plus.speed + plus.phase) * 0.3, plus.dz)
            local toPoint = point - camera.origin
            local distance = toPoint:GetLength()
            local shown = distance > 0.3 and toPoint:DotProduct(camera.zAxis) > 0.2
            if shown then
                local trace = Shared.TraceRay(camera.origin, point, CollisionRep.Default, PhysicsMask.Bullets, EntityFilterAll())
                shown = trace.fraction > 0.98
            end
            if shown then
                local screen = Client.WorldToScreen(point)
                local scale = math.max(0.25, math.min(2.0, 8 / distance)) * scaleBase
                plus.item:SetPosition(Vector(screen.x, screen.y, 0))
                plus.item:SetScale(Vector(scale, scale, 1))
                plus.item:SetColor(Color(kFieldPlusColour[1], kFieldPlusColour[2], kFieldPlusColour[3], kFieldPlusAlpha))
            end
            plus.item:SetIsVisible(shown)
        end
    end

    function MedPack:OnDestroy()
        if self.tehFieldRings then
            for _, ring in ipairs(self.tehFieldRings) do
                Client.DestroyRenderDecal(ring.decal)
                Client.DestroyRenderMaterial(ring.material)
            end
            self.tehFieldRings = nil
        end
        DestroyPluses(self)
        ScriptActor.OnDestroy(self)
    end

    -- ---- The Commander's placement ring at the cursor -----------------------------------------------------------
    --[[
        While the Commander has the medpack selected: the 4.5 m ring (both modes);
        centred where the drop would land. Added to the Commander's own ghost guides (Commander:UpdateGhostGuides runs
        only in the Commander view, every frame), so nobody else sees it. Patched once the Commander classes exist.
    ]]
    local function AddMedRing(commander)

        if commander.currentTechId ~= kTechId.MedPack or CommanderUI_GetMouseIsOverUI() then return end

        -- Where the drop would actually land - the placement ghost's coords (already put on the floor under the cursor
        -- by the medpack's coords method, CNBalance/TechData.lua).
        local coords = GetCommanderGhostStructureCoords and GetCommanderGhostStructureCoords()
        local point = coords and coords.origin
        if not point then
            local xScalar, yScalar = Client.GetCursorPos()
            local x, y = xScalar * Client.GetScreenWidth(), yScalar * Client.GetScreenHeight()
            local trace = GetCommanderPickTarget(commander, CreatePickRay(commander, x, y), false, true)
            point = trace and trace.endPoint
        end
        if not point then return end

        commander:AddGhostGuide(Vector(point), MedPack_IsAreaHeal(commander) and kMedFieldRadius or kMultiMedRadius)

    end

    local function PatchCommanderRings()
        if MedPack.srRingsPatched or not (Commander and Commander.UpdateGhostGuides) then return end
        MedPack.srRingsPatched = true
        for _, cls in ipairs({ Commander, MarineCommander }) do
            local base = cls and rawget(cls, "UpdateGhostGuides")
            if base then
                cls.UpdateGhostGuides = function(self, ...)
                    base(self, ...)
                    local ok, err = pcall(AddMedRing, self)
                    if not ok and not MedPack.srRingsError then
                        MedPack.srRingsError = true
                        Shared.Message("[Medpack] placement ring: " .. tostring(err))
                    end
                end
            end
        end
    end
    Event.Hook("UpdateClient", PatchCommanderRings)

end

MedPack.kRegen = kMedpackRegen
MedPack.kMedpackRegenWhenHealing = kMedpackRegenWhenHealing

function MedPack:OnTouch(recipient)

    if not recipient.timeLastMedpack or recipient.timeLastMedpack + self.kPickupDelay <= Shared.GetTime() then

        local oldHealth = recipient:GetHealth()
        if recipient:GetRegeneratingHealth() <= 0 then
            recipient:AddHealth(MedPack.kHealth, false, true)
            recipient:AddRegeneration(MedPack.kRegen)
        else
            recipient:AddHealth(kMedpackHealWhenRegening, false, true)
            recipient:AddRegeneration(kMedpackRegenWhenRegening)
        end

        recipient.timeLastMedpack = Shared.GetTime()

        -- (2026-10-27) On the Marine who got it - once per Marine healed (a multi-med plays it on each of them; a
        -- normal medpack at their feet, where it lay).
        self:TriggerEffects("medpack_pickup", { effecthostcoords = recipient:GetCoords() })

        -- Handle Stats
        if Server then

            local commanderStats = StatsUI_GetStatForCommander(StatsUI_GetMarineCommmaderSteamID())

            -- If the medpack hits immediatly expireTime is 0
            if ConditionalValue(self.expireTime == 0, Shared.GetTime(), self.expireTime - kItemStayTime) + 0.025 > Shared.GetTime() then
                commanderStats["medpack"].hitsAcc = commanderStats["medpack"].hitsAcc + 1
            end

            commanderStats["medpack"].misses = commanderStats["medpack"].misses - 1
            commanderStats["medpack"].picks = commanderStats["medpack"].picks + 1
            commanderStats["medpack"].refilled = commanderStats["medpack"].refilled + recipient:GetHealth() - oldHealth

        end

    end

end
