-- ARMORY WEAPON STORAGE - stock bookkeeping and absorption. Loaded post lua/Armory.lua.
--
-- The Marine and Weapon halves hook their own files rather than being folded in here: load order
-- BETWEEN hooks on different targets is not guaranteed.

if not Server then return end

-- Diagnostics for the absorption path, matching the flag in ArmoryStorage_Marine.lua (a SEPARATE
-- local here -- each hooked file is its own Lua chunk, so nothing there is visible from this file).
-- BROADCASTS to everyone rather than targeting one player: at drop time there is no convenient
-- "whose screen should this land on" answer, and a broadcast removes any doubt about whether the
-- right client was resolved -- everyone on the server sees it or no one does.
local kArmoryStorageDebug = false

local function BroadcastDebug(fmt, ...)

    if not kArmoryStorageDebug then
        return
    end

    local ok, text = pcall(string.format, fmt, ...)
    if not ok then
        return
    end

    pcall(Server.SendNetworkMessage, "Chat",
          BuildChatMessage(false, "ArmoryStorage", -1, kTeamReadyRoom, kNeutralTeamType, text), true)

end

--[[
    The radius in which an armory claims dropped weapons.

    This is the COMMANDER'S WEAPON DROP RADIUS (kArmoryWeaponAttachRange = 10), not the armory's use
    range (kResupplyUseRange = 2). Absorption previously used the use range, so anything the commander
    dropped more than 2 units from the armory -- i.e. most of a normal drop spread -- was never
    claimed. That is why shotguns sat on the floor inside the visible drop circle.

    Keying off the same constant the drop itself uses means the two can never drift apart: if a drop
    lands somewhere legal, it lands somewhere storable, by construction.

    Read through a function rather than captured at file scope, because this file is a post-hook and
    the balance constant is not guaranteed to exist yet when it loads.
]]
local function GetAbsorbRange()
    return kArmoryWeaponAttachRange or 10
end

-- Backstop sweep, for weapons that arrive in range AFTER being dropped (slid, or the armory was
-- still building) -- cases no drop-time hook can catch.
local kAbsorbCheckInterval = 0.5

function Armory:GetStoredCount(techId)
    return (self.ceStoredWeapons and self.ceStoredWeapons[techId]) or 0
end

-- Broadcast to the whole team: cheaper than tracking who has which armory's menu open.
--
-- "Player", not "Marine". A commander is a Commander entity, NOT a Marine, so a marine-only sweep
-- silently skipped them for the entire time they were in the chair -- every stock change made while
-- commanding (including their own weapon drops) never reached their client. On logging out they then
-- saw stale counts until some later change happened to refresh them.
function Armory:SendStoredCount(techId)

    local message = { armoryId = self:GetId(), techId = techId, count = self:GetStoredCount(techId) }

    for _, player in ipairs(GetEntitiesForTeam("Player", self:GetTeamNumber())) do

        local client = Server.GetOwner(player)
        if client then
            Server.SendNetworkMessage(client, "ArmoryStock", message, true)
        end

    end

end

function Armory:GetCanAcceptStoredWeapon(techId)

    -- A dying armory must not swallow its own spill: OnKill runs while it is still alive and listed.
    -- Clearing the stock table is NOT sufficient -- that frees space and makes re-absorption likelier.
    if self.ceIsSpilling then
        return false
    end

    -- Unpowered stores nothing. The sweep keeps retrying, so it is picked up once power returns.
    local powered = not self.GetIsPowered or self:GetIsPowered()

    return powered
       and GetArmoryCanStoreTechId(self, techId)
       and self:GetStoredCount(techId) < kArmoryMaxStoredPerWeapon
       and self:GetIsAlive() and self:GetIsBuilt()

end

function Armory:AddStoredWeapon(techId)

    if not self:GetCanAcceptStoredWeapon(techId) then
        return false
    end

    self.ceStoredWeapons = self.ceStoredWeapons or {}
    self.ceStoredWeapons[techId] = self:GetStoredCount(techId) + 1
    self:SendStoredCount(techId)

    return true

end

-- Put a copy back unconditionally. Used to roll back a purchase that failed after the stock was
-- taken; it deliberately skips the accept checks, because if the armory lost power or hit its cap in
-- the meantime, refusing here would destroy a weapon the player owns rather than merely decline one.
function Armory:RestoreStoredWeapon(techId)

    self.ceStoredWeapons = self.ceStoredWeapons or {}
    self.ceStoredWeapons[techId] = self:GetStoredCount(techId) + 1
    self:SendStoredCount(techId)

end

-- True if a copy was consumed. Empty stock is not an error -- it just means the player pays.
function Armory:ConsumeStoredWeapon(techId)

    local count = self:GetStoredCount(techId)
    if count <= 0 then
        return false
    end

    self.ceStoredWeapons[techId] = count - 1
    self:SendStoredCount(techId)

    return true

end

-- Full authoritative resync for one client.
--
-- Sends EVERY storable techId including zeros. Sending only non-zero entries is not enough: a client
-- holding a stale non-zero count for something the server now has none of would never be corrected,
-- because no message would ever mention that pair again. Zeros are what actually clear stale state.
function Armory:SendFullStockToClient(client)

    if not client then
        return
    end

    for _, techId in ipairs(kArmoryStorableTechIds or {}) do
        Server.SendNetworkMessage(client, "ArmoryStock",
            { armoryId = self:GetId(), techId = techId, count = self:GetStoredCount(techId) }, true)
    end

end

function ArmoryStorage_SyncAllToClient(client, teamNumber)

    if not client then
        return
    end

    for _, armory in ipairs(GetEntitiesForTeam("Armory", teamNumber)) do
        armory:SendFullStockToClient(client)
    end

end

local function GetWeaponStorageTechId(weapon)

    if not weapon or not kArmoryStorableMapNames then
        return nil
    end

    if not (weapon.GetWeaponWorldState and weapon:GetWeaponWorldState()) then
        return nil
    end

    return kArmoryStorableMapNames[weapon:GetMapName()]

end

-- Destroy the weapon ONLY if it was actually banked. AddStoredWeapon can refuse (cap reached, power
-- lost, armory dying) between the eligibility check and this call; destroying regardless would delete
-- a weapon the player paid for and store nothing in its place. Returns whether it was taken.
function Armory:AbsorbWeapon(weapon, techId)

    if not self:AddStoredWeapon(techId) then
        return false
    end

    DestroyEntity(weapon)
    return true

end

--[[
    Queue a weapon for absorption on the next server frame.

    Absorption DESTROYS the weapon, and it is triggered from Weapon:SetWeaponWorldState -- which
    vanilla calls on the FIRST LINE of Weapon:Dropped and then keeps using the weapon afterwards:

        function Weapon:Dropped(prevOwner)
            self.prevOwnerId = prevOwner:GetId()
            self:SetWeaponWorldState(true)      -- absorbing here destroys the entity
            if self.physicsModel then
                self.physicsModel:AddImpulse(...)   -- ...and vanilla then touches the dead entity

    Destroying it inline therefore breaks the rest of the drop, which is why dropped weapons were not
    being stored. ResetGame has the same shape and that is what hung the server. So nothing is ever
    destroyed from inside an engine call: the weapon is queued here and claimed a frame later, from
    the top of the server update where no engine code is mid-way through using it.
]]
local ceLmgMapName = nil

function ArmoryStorage_GetIsLmg(weapon)

    if not weapon then
        return false
    end

    if ceLmgMapName == nil then
        ceLmgMapName = LookupTechData(kTechId.LightMachineGun, kTechDataMapName) or false
    end

    return ceLmgMapName ~= false
       and weapon.GetWeaponWorldState and weapon:GetWeaponWorldState()
       and weapon:GetMapName() == ceLmgMapName

end

local ceAbsorbQueue = {}

-- Will this weapon be claimed (stored, or despawned in the Machine Gun's case) rather than left lying
-- on the floor? Answered WITHOUT absorbing, so the drop path can reserve it a frame ahead of time.
function ArmoryStorage_GetWillBeClaimed(weapon)

    if gArmoryStorageSuspended or not weapon then
        return false
    end

    if ArmoryStorage_GetIsLmg(weapon) then
        return true
    end

    local techId = GetWeaponStorageTechId(weapon)
    if not techId then
        return false
    end

    local isPaid = GetIsArmoryStorableTechId(techId)

    for _, armory in ipairs(GetEntitiesWithinRange("Armory", weapon:GetOrigin(), GetAbsorbRange())) do

        if isPaid and armory:GetCanAcceptStoredWeapon(techId) then
            return true
        end

        if not isPaid and armory:GetIsAlive() and armory:GetIsBuilt() then
            return true
        end

    end

    return false

end

function ArmoryStorage_QueueAbsorb(weapon)

    if gArmoryStorageSuspended or not weapon then
        return
    end

    ceAbsorbQueue[weapon:GetId()] = true

    -- RESERVE it immediately. Absorption happens a frame later (destroying entities inside the engine's
    -- own drop call breaks the drop -- see the queue comment), and in that gap a marine standing in
    -- front of the dropper could auto-pick the weapon up, stealing something bound for storage. The
    -- reservation blocks every pickup route for that gap; it is cleared again below if nothing claims
    -- it, so a weapon dropped away from an armory stays freely pickup-able.
    if ArmoryStorage_GetWillBeClaimed(weapon) then
        weapon.ceReservedForStorage = true
    end

end

--[[
    Route a weapon to the right armory.

    Destination rule: the CLOSEST armory that can actually accept it. Eligibility is checked before
    distance, not after, which is what makes the mixed case behave: an advanced weapon dropped between
    a nearer basic Armory and a further Advanced Armory goes to the Advanced Armory, because the basic
    one was never a candidate. If nothing eligible is in range the weapon is left lying there --
    undecayed and pickup-able -- rather than deleted. The same applies when every eligible armory is
    unpowered, or already at its ceiling of ten.
]]
function ArmoryStorage_TryAbsorb(weapon)

    if gArmoryStorageSuspended then
        return
    end

    -- The Machine Gun (LMG) is not stored: it despawns outright (one-time purchase, re-armed free).
    -- Handled here rather than at the drop site so it shares the deferred, safe destruction path.
    if ArmoryStorage_GetIsLmg(weapon) then
        DestroyEntity(weapon)
        return
    end

    local techId = GetWeaponStorageTechId(weapon)
    if not techId then
        -- Only worth announcing for weapons this system COULD have cared about, i.e. it was in world
        -- state but did not resolve to a storable techId at all. A held weapon (GetWeaponStorageTechId
        -- returning nil because it is not yet dropped) is silent by design -- this fires only once
        -- something has actually landed on the floor.
        if weapon.GetWeaponWorldState and weapon:GetWeaponWorldState() then
            BroadcastDebug("AS: dropped weapon '%s' is not a storable type, ignored", tostring(weapon:GetMapName()))
        end
        weapon.ceReservedForStorage = nil
        return
    end

    BroadcastDebug("AS: absorb check for techId %s (weapon %s)", tostring(techId), tostring(weapon:GetId()))

    -- Free weapons are discarded rather than banked, but only when an armory is actually there to
    -- discard them -- otherwise a free weapon dropped in the open would vanish.
    local isPaid = GetIsArmoryStorableTechId(techId)

    local best, bestDistance
    local candidateCount = 0

    for _, armory in ipairs(GetEntitiesWithinRange("Armory", weapon:GetOrigin(), GetAbsorbRange())) do

        candidateCount = candidateCount + 1

        local eligible = isPaid and armory:GetCanAcceptStoredWeapon(techId)
                      or (not isPaid) and armory:GetIsAlive() and armory:GetIsBuilt()

        BroadcastDebug("AS:   armory %s eligible=%s (isPaid=%s canAccept=%s alive=%s built=%s)",
                        tostring(armory:GetId()), tostring(eligible), tostring(isPaid),
                        tostring(armory.GetCanAcceptStoredWeapon and armory:GetCanAcceptStoredWeapon(techId)),
                        tostring(armory:GetIsAlive()), tostring(armory:GetIsBuilt()))

        if eligible then

            local distance = (armory:GetOrigin() - weapon:GetOrigin()):GetLengthSquared()
            if not bestDistance or distance < bestDistance then
                best, bestDistance = armory, distance
            end

        end

    end

    BroadcastDebug("AS:   %d armor%s checked, best=%s",
                    candidateCount, candidateCount == 1 and "y" or "ies", best and tostring(best:GetId()) or "NONE")

    -- Nothing claimed it (no armory in range, all full, all unpowered, advanced weapon at a basic
    -- Armory). It stays on the floor, so it must become pickup-able again.
    if not best then
        weapon.ceReservedForStorage = nil
        return
    end

    if isPaid then

        -- If the armory refuses it after all, the weapon stays on the floor -- so release the
        -- reservation, otherwise it would sit there permanently unpickupable.
        if best:AbsorbWeapon(weapon, techId) then
            BroadcastDebug("AS:   ABSORBED into armory %s, stock now %d", tostring(best:GetId()), best:GetStoredCount(techId))
        else
            BroadcastDebug("AS:   armory %s REFUSED to absorb after all", tostring(best:GetId()))
            weapon.ceReservedForStorage = nil
        end

    else
        DestroyEntity(weapon)
    end

end

-- Drain the queue. Runs at the top of the server update, so no engine code is part-way through using
-- any of these weapons and destroying them is safe.
local function ProcessAbsorbQueue()

    if gArmoryStorageSuspended or not next(ceAbsorbQueue) then
        return
    end

    local queue = ceAbsorbQueue
    ceAbsorbQueue = {}

    for entityId in pairs(queue) do

        local weapon = Shared.GetEntity(entityId)

        -- May have been picked up, destroyed or expired in the intervening frame. A destroyed entity
        -- can still come back as a table, so test that explicitly rather than just for nil: calling
        -- GetOrigin/GetMapName on one would error and abort the whole drain, stranding every other
        -- weapon in this batch (and leaving them reserved, so nobody could pick them up either).
        local valid = weapon ~= nil
                  and weapon.GetWeaponWorldState ~= nil
                  and (weapon.GetIsDestroyed == nil or not weapon:GetIsDestroyed())

        if valid then
            ArmoryStorage_TryAbsorb(weapon)
        end

    end

end

Event.Hook("UpdateServer", ProcessAbsorbQueue)

local function AbsorbNearbyWeapons(self)

    if gArmoryStorageSuspended or not self:GetIsAlive() or not self:GetIsBuilt() then
        return kAbsorbCheckInterval
    end

    -- Backstop sweep. Routing still goes through ArmoryStorage_TryAbsorb rather than straight into
    -- this armory, so a weapon that drifts into range of two armories lands in the closer one here
    -- too, instead of whichever happened to sweep first.
    for _, weapon in ipairs(GetEntitiesWithinRange("Weapon", self:GetOrigin(), GetAbsorbRange())) do
        ArmoryStorage_TryAbsorb(weapon)
    end

    return kAbsorbCheckInterval

end

--[[
    Spill the entire stock onto the floor when the armory dies.

    Weapons stored in an armory were paid for, so destroying the building must not delete them -- it
    drops them where the building stood, ready to be picked up or claimed by another armory in range.

    Two details matter here:

    * ceIsSpilling is set FIRST. Spawning a weapon puts it into world state, which fires
      ArmoryStorage_TryAbsorb -- and at OnKill time this armory is still alive and still in the entity
      list, so it would otherwise re-absorb its own spill and take the weapons down with it. Other
      armories in range are still free to claim them, which is fine and intended.
    * Weapons are spread in a ring rather than stacked on one point, so ten welders are ten reachable
      pickups instead of one unreachable pile.
]]
local function SpillStockToFloor(self)

    local stock = self.ceStoredWeapons
    if not stock then
        return
    end

    self.ceIsSpilling = true
    self.ceStoredWeapons = {}

    local origin = self:GetOrigin()
    local teamNumber = self:GetTeamNumber()
    local index = 0
    local total = 0

    for _, count in pairs(stock) do
        total = total + count
    end

    for techId, count in pairs(stock) do

        local mapName = LookupTechData(techId, kTechDataMapName)

        if mapName then

            for _ = 1, count do

                local angle = (index / math.max(1, total)) * math.pi * 2
                local spread = 0.35 + (index % 3) * 0.25
                local dropOrigin = origin + Vector(math.cos(angle) * spread, 0.2, math.sin(angle) * spread)

                local weapon = CreateEntity(mapName, dropOrigin, teamNumber)
                if weapon and weapon.SetWeaponWorldState then
                    weapon:SetWeaponWorldState(true)
                end

                index = index + 1

            end

        end

        -- Tell clients this armory now holds nothing, so no buy menu keeps showing a dead stock.
        self:SendStoredCount(techId)

    end

end

-- Recycling must spill exactly as destruction does -- the weapons inside were paid for either way.
local baseArmoryOnRecycled = Armory.OnRecycled
function Armory:OnRecycled()

    SpillStockToFloor(self)

    if baseArmoryOnRecycled then
        return baseArmoryOnRecycled(self)
    end

end

local baseArmoryOnKill = Armory.OnKill
function Armory:OnKill(attacker, doer, point, direction)

    SpillStockToFloor(self)

    if baseArmoryOnKill then
        return baseArmoryOnKill(self, attacker, doer, point, direction)
    end

end

local baseArmoryOnInitialized = Armory.OnInitialized
function Armory:OnInitialized()

    baseArmoryOnInitialized(self)

    self.ceStoredWeapons = {}
    self:AddTimedCallback(AbsorbNearbyWeapons, kAbsorbCheckInterval)

    -- Clear every client's cached counts for this entity id. Entity ids are RECYCLED, so a new armory
    -- can inherit the id of a destroyed one and, with it, that armory's stale counts on every client --
    -- showing phantom stock the server does not have. Counts are only ever pushed on change, so
    -- without this nothing would ever correct it.
    for _, techId in ipairs(kArmoryStorableTechIds or {}) do
        self:SendStoredCount(techId)
    end

end
