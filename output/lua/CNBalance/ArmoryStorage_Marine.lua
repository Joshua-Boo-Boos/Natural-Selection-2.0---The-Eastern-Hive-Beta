-- ARMORY WEAPON STORAGE - spending stock and the Machine Gun entitlement.
-- Loaded post lua/Marine_Server.lua, where ProcessBuyAction, AttemptToBuy, InitWeapons and
-- GetHostStructureFor live.

if not Server then return end

--[[
    The 30 p-res Machine Gun is the LIGHT machine gun, bought via LightMachineGunAcquire. (The
    vanilla HeavyMachineGun is a different, 20 p-res weapon and is deliberately not involved here.)

    RESOLVED LAZILY, and this is critical rather than stylistic. This file is a post-hook on
    Marine_Server.lua, which the engine reaches like this:

        Server.lua:16  Script.Load("lua/Shared.lua")
                         -> Shared.lua:147 ReadyRoomPlayer.lua -> Marine.lua -> Marine_Server.lua
        Server.lua:18  Script.Load("lua/TechData.lua")     <-- defines LookupTechData

    So this file runs at line 16, two lines BEFORE LookupTechData exists. Calling it at file scope
    raises "attempt to call a nil value" and the WHOLE FILE fails to load -- taking the
    ProcessBuyAction override with it, silently, so every purchase falls through to vanilla and is
    charged full price. That is exactly what was happening. Deferring to first use fixes it, because
    by the time a marine spawns or buys anything, the tech data is long since loaded.
]]
local ceLmgMapName = nil

local function GetLmgMapName()

    if ceLmgMapName == nil then
        ceLmgMapName = (LookupTechData and LookupTechData(kTechId.LightMachineGun, kTechDataMapName)) or false
    end

    return ceLmgMapName ~= false and ceLmgMapName or nil

end

-- A marine who buys the Machine Gun keeps it across deaths; a marine who DROPS it forfeits that and
-- respawns with the standard rifle instead. Keyed by client id rather than stored on the player,
-- because the player entity is destroyed and rebuilt on every respawn.
local ceLmgEntitlement = {}

local function GetClientKey(player)
    local client = Server.GetOwner(player)
    return client and client:GetId()
end

-- Diagnostics for the retrieval path. Kept behind a flag so it can be switched off with a single edit
-- once confirmed working, and wrapped in pcall so a formatting mistake can never take down a purchase.
local kArmoryStorageDebug = false

local function DebugLog(fmt, ...)

    if not kArmoryStorageDebug then
        return
    end

    pcall(Log, "[ArmoryStorageDebug] " .. fmt, ...)

end

--[[
    TEMPORARY: send the buying player a private chat line stating exactly which branch this purchase
    took. Server console logs require finding and reading a log file; this shows up directly in the
    same game window the purchase itself is happening in, so there is no gap between "the code ran"
    and "the evidence is visible" -- the next single click settles this outright.

    Uses the same private-message pattern vanilla's own admin PM commands use
    (ServerAdminCommands.lua): Server.SendNetworkMessage(player, "Chat", BuildChatMessage(...), true)
    targeted at one client rather than broadcast.
]]
local function ChatDebug(player, fmt, ...)

    if not kArmoryStorageDebug or not player then
        return
    end

    local ok, text = pcall(string.format, fmt, ...)
    if not ok then
        return
    end

    pcall(function()

        local client = Server.GetOwner(player)

        if client then
            Server.SendNetworkMessage(player, "Chat",
                BuildChatMessage(false, "ArmoryStorage", -1, player:GetTeamNumber(), kNeutralTeamType, text), true)
        end

    end)

end

-- An armory in reach holding a stored copy of techId, or nil.
--
-- The purchase-funds sound proved the previous version was reaching the PAID path with stock sitting
-- in the armory, i.e. this returned nil when it should not have. The only way that happens is my own
-- range scan disagreeing with the one vanilla uses to validate the purchase. So the scan is no longer
-- the primary source: GetHostStructureFor is asked FIRST, because that is by definition the exact
-- structure AttemptToBuy will resolve for this same purchase -- they cannot disagree with each other.
-- The range scan remains only as a fallback for the multi-armory case.
--
-- The eligibility test is also reduced to what actually matters: it must be an armory allowed to hold
-- the type, powered, and holding at least one. GetIsBuilt/GetIsAlive were dropped -- an armory you can
-- open a buy menu at is necessarily both, so they could only ever produce a false negative like this.
local function GetStockFrom(armory, techId)

    if not armory or not armory.isa or not armory:isa("Armory") then
        return nil
    end

    local powered = not armory.GetIsPowered or armory:GetIsPowered()

    if powered
    and GetArmoryCanStoreTechId(armory, techId)
    and armory.GetStoredCount and armory:GetStoredCount(techId) > 0 then
        return armory
    end

    return nil

end

local function GetArmoryWithStockFor(player, techId)

    if not GetIsArmoryStorableTechId(techId) then
        ChatDebug(player, "AS: techId %s is NOT a storable type (cost<=0 or not on the list)", tostring(techId))
        return nil
    end

    -- Vanilla's own resolution for this exact purchase.
    local host = GetHostStructureFor and GetHostStructureFor(player, techId)
    local fromHost = GetStockFrom(host, techId)

    if fromHost then
        DebugLog("stock found on canonical host %s (stored=%d)", fromHost:GetId(), fromHost:GetStoredCount(techId))
        ChatDebug(player, "AS: techId %s FOUND on canonical host %s, stored=%d",
                  tostring(techId), tostring(fromHost:GetId()), fromHost:GetStoredCount(techId))
        return fromHost
    end

    ChatDebug(player, "AS: techId %s canonical host=%s (stock there=%s)", tostring(techId),
              host and host:GetClassName() or "NIL",
              host and host.GetStoredCount and tostring(host:GetStoredCount(techId)) or "n/a")

    local candidates = GetEntitiesForTeamWithinRange("Armory", player:GetTeamNumber(),
                                                       player:GetOrigin(), Armory.kResupplyUseRange)

    ChatDebug(player, "AS: fallback scan found %d armor%s in range", #candidates, #candidates == 1 and "y" or "ies")

    for _, armory in ipairs(candidates) do

        local found = GetStockFrom(armory, techId)
        if found then
            DebugLog("stock found on nearby armory %s (stored=%d)", found:GetId(), found:GetStoredCount(techId))
            ChatDebug(player, "AS: techId %s FOUND on nearby armory %s, stored=%d",
                      tostring(techId), tostring(found:GetId()), found:GetStoredCount(techId))
            return found
        end

        local powered = not armory.GetIsPowered or armory:GetIsPowered()
        local canStore = GetArmoryCanStoreTechId(armory, techId)
        local stored = armory.GetStoredCount and armory:GetStoredCount(techId)

        DebugLog("  armory %s rejected: powered=%s canStore=%s stored=%s",
                 armory:GetId(), tostring(powered), tostring(canStore), tostring(stored))
        ChatDebug(player, "AS: armory %s rejected: powered=%s canStore=%s stored=%s",
                  tostring(armory:GetId()), tostring(powered), tostring(canStore), tostring(stored))

    end

    DebugLog("techId %s -> NO armory with stock (host was %s)",
             techId, host and host:GetClassName() or "nil")
    ChatDebug(player, "AS: techId %s -> NO stock found anywhere, will pay full price", tostring(techId))
    return nil

end

--[[
    Hand a techId to the player for free, using vanilla's OWN item-giving path.

    This calls self:AttemptToBuy({techId}) directly -- the exact function vanilla purchases funnel
    through -- rather than reimplementing weapon slot handling, effects, and the "destroy my own
    free dropped copies" cleanup it already does. Critically, for a plain weapon (not Jetpack, not an
    Exo) AttemptToBuy charges NOTHING on its own; all charging happens outside it, in
    Player:ProcessBuyAction, which this call bypasses entirely. So there is no credit/refund dance
    and nothing that has to be kept in sync with vanilla's own cost math -- the weapon is simply
    free, because the code path that would have charged for it is never invoked.
]]
local function GiveForFree(player, techId)
    return player:AttemptToBuy({ techId })
end

local basePlayerProcessBuyAction = Marine.ProcessBuyAction or Player.ProcessBuyAction
function Marine:ProcessBuyAction(techIds)

    -- Unconditional, before any gating: if this line never appears in chat, the hook installed by
    -- THIS file is not the one being invoked at all, and the problem is not in the logic below --
    -- it is in deployment or class identity, and no amount of further logic changes here will help.
    ChatDebug(self, "AS: ProcessBuyAction called with techIds=[%s]",
              techIds and table.concat(techIds, ",") or "nil")

    if not techIds then
        return basePlayerProcessBuyAction(self, techIds)
    end

    local paidTechIds = {}
    local gaveAnyFree = false

    for _, techId in ipairs(techIds) do

        local armory = GetArmoryWithStockFor(self, techId)
        local lmgAlreadyOwned = techId == kTechId.LightMachineGunAcquire
                              and ceLmgEntitlement[GetClientKey(self) or false]

        if armory then

            ChatDebug(self, "AS: techId %s -> armory %s claimed to have stock, consuming...", tostring(techId), tostring(armory:GetId()))

            if armory:ConsumeStoredWeapon(techId) then

                if GiveForFree(self, techId) then
                    DebugLog("techId %s: given free from armory %s", techId, armory:GetId())
                    ChatDebug(self, "AS: techId %s -> GIVEN FREE (AttemptToBuy succeeded)", tostring(techId))
                    gaveAnyFree = true
                else
                    -- AttemptToBuy itself rejected it (e.g. moved out of range mid-click). Put the
                    -- stock back and fall through to a normal paid attempt.
                    ChatDebug(self, "AS: techId %s -> AttemptToBuy REFUSED it after consuming stock, stock restored, falling to paid", tostring(techId))
                    armory:RestoreStoredWeapon(techId)
                    table.insert(paidTechIds, techId)
                end

            else
                ChatDebug(self, "AS: techId %s -> armory %s ConsumeStoredWeapon FAILED (race?), falling to paid", tostring(techId), tostring(armory:GetId()))
                table.insert(paidTechIds, techId)
            end

        elseif lmgAlreadyOwned then

            if GiveForFree(self, techId) then
                DebugLog("techId %s: Machine Gun re-armed free (already owned)", techId)
                ChatDebug(self, "AS: techId %s -> Machine Gun already owned, GIVEN FREE", tostring(techId))
                gaveAnyFree = true
            else
                ChatDebug(self, "AS: techId %s -> Machine Gun owned but AttemptToBuy REFUSED, falling to paid", tostring(techId))
                table.insert(paidTechIds, techId)
            end

        else
            table.insert(paidTechIds, techId)
        end

    end

    local paidSuccess = false

    if #paidTechIds > 0 then
        paidSuccess = basePlayerProcessBuyAction(self, paidTechIds)
    end

    -- Grant the one-time Machine Gun entitlement once it has actually been paid for.
    if paidSuccess then

        for _, techId in ipairs(paidTechIds) do

            if techId == kTechId.LightMachineGunAcquire then

                local key = GetClientKey(self)
                if key then

                    ceLmgEntitlement[key] = true

                    local client = Server.GetOwner(self)
                    if client then
                        Server.SendNetworkMessage(client, "ArmoryLmgOwned", { owned = true }, true)
                    end

                end

            end

        end

    end

    return gaveAnyFree or paidSuccess

end

-- Dropping revokes nothing: the Machine Gun despawns rather than being left for someone else, so the
-- owner simply re-arms for free. Marine:Drop is not hooked.

local baseInitWeapons = Marine.InitWeapons
function Marine:InitWeapons()

    baseInitWeapons(self)

    local key = GetClientKey(self)
    local lmgMapName = GetLmgMapName()

    if key and lmgMapName and ceLmgEntitlement[key] then
        self:GiveItem(lmgMapName)
        self:SetActiveWeapon(lmgMapName)
    end

end

-- Sync stock to a spawning client. Covers state that existed before they could receive anything --
-- otherwise they read a stocked armory as empty and get charged for what should be free. On spawn
-- rather than connect, since a player can change teams without reconnecting.
-- Push the full picture to one client: stock for every armory, plus Machine Gun ownership.
local function SyncEverythingToClient(player, client)

    if not client then
        return
    end

    if ArmoryStorage_SyncAllToClient then
        ArmoryStorage_SyncAllToClient(client, player:GetTeamNumber())
    end

    local key = client.GetId and client:GetId()
    if key and ceLmgEntitlement[key] then
        Server.SendNetworkMessage(client, "ArmoryLmgOwned", { owned = true }, true)
    end

end

--[[
    Resync whenever a client TAKES CONTROL of a marine.

    This is the reliable moment, and OnInitialized is not. Player:SetControllerClient is what attaches
    the client and it calls OnClientUpdated afterwards -- so during OnInitialized Server.GetOwner can
    still be nil and the sync there silently does nothing.

    It also covers the case OnInitialized cannot: logging OUT of a command station. While commanding,
    the player is a Commander entity and receives no marine stock updates, so they return to a marine
    holding whatever counts were current when they sat down. This fires on that transition and
    replaces the whole picture.
]]
local baseOnClientUpdated = Marine.OnClientUpdated or Player.OnClientUpdated
function Marine:OnClientUpdated(client, isPickup)

    if baseOnClientUpdated then
        baseOnClientUpdated(self, client, isPickup)
    end

    SyncEverythingToClient(self, client)

end

local baseMarineOnInitialized = Marine.OnInitialized
function Marine:OnInitialized()

    baseMarineOnInitialized(self)

    -- Kept as well as the OnClientUpdated hook above: on a plain respawn the client is often already
    -- attached, and syncing here makes the counts correct a fraction earlier. Harmless when the
    -- client is not yet set -- it simply does nothing and OnClientUpdated covers it.
    SyncEverythingToClient(self, Server.GetOwner(self))

end
