--[[
    BMAC character (design: NS2.0-TEH/BMAC_Character.md, Draft 6). Post-hook on MarineVariantMixin.lua,
    loaded AFTER CNBalance/MarineVariantMixin.lua so the wraps below sit on top of the active skin handler.

    A Marine wearing a vanilla BMAC skin is armour-only, like an Exo: the 100 HP becomes 100 extra AP and
    LiveMixin's existing healthIgnored mode kills it when AP reaches 0. The selected skin is locked from the
    Countdown until the round is won, drawn or reset.

    Shared: the classification predicate (also used by DamageTypes and the HUD).
    Server: the round lock and the durability switch, run from every skin application path.
]]

-- The Marine's 100 HP as AP at the damage rate (kHealthPointsPerArmor = 2): 100 HP = 50 AP, so a BMAC
-- has the same total EHP as a biological Marine with the same upgrades (Joshua, 14 Oct 2026).
kBMACBonusArmor = 50
kBMACExitFallbackArmor = 15     -- Exo exit only, and only when the saved entry AP is missing/invalid

-- The 24 vanilla kMarineVariants NAMES (NS2-Copy/ns2/lua/Globals.lua). Names, not ids: a mod that
-- appends variants (TEHSF desert/urban) gets new ids but can't take one of these names.
local kBMACVanillaMarineVariantNames =
{
    "green", "special", "deluxe", "assault", "eliteassault", "kodiak", "tundra", "anniv", "sandstorm", "chroma",
    "bigmac", "bigmac02", "bigmac03", "bigmac04", "bigmac05", "bigmac06", "chromabmac",
    "militarymac", "militarymac02", "militarymac03", "militarymac04", "militarymac05", "militarymac06", "chromamilbmac",
}
local kVanillaNameSet = {}
for _, name in ipairs(kBMACVanillaMarineVariantNames) do
    kVanillaNameSet[name] = true
end

-- Authoritative plugin metadata: a variant whose product id belongs to the TEHSF skin plugin is custom,
-- even if it somehow carried a vanilla name. (A plugin that reuses a vanilla id and publishes no metadata
-- cannot be detected - see the design doc, section 3.)
-- TEHSF is optional. rawget so a missing global is just nil (never an undefined-global error), and the
-- type checks cover a half-loaded or different plugin.
local function GetTEHSkins()
    local skins = rawget(_G, "TEHSkins")
    if type(skins) ~= "table" or type(rawget(skins, "GetProductList") or skins.GetProductList) ~= "function" then
        return nil
    end
    return skins
end

local function GetIsPluginSkin(variant)
    local skins = GetTEHSkins()
    if not skins then
        return false
    end
    local variantsData = rawget(_G, "kMarineVariantsData")
    local data = type(variantsData) == "table" and variantsData[variant]
    local productId = type(data) == "table" and data.productId
    if not productId or productId == 0 then
        return false
    end
    local ok, products = pcall(skins.GetProductList, skins)
    if not ok or type(products) ~= "table" then
        return false
    end
    for _, id in ipairs(products) do
        if id == productId then
            return true
        end
    end
    return false
end

local function GetVariantName(variant)
    return kMarineVariants[variant]
end

local function ComputeIsCustomVariant(variant)
    -- kMarineVariants is an engine enum (id -> name); an unknown id may throw, so look it up protected.
    local ok, name = pcall(GetVariantName, variant)
    if not ok or type(name) ~= "string" or not kVanillaNameSet[name] then
        return true
    end
    return GetIsPluginSkin(variant)
end

--[[
    Per-variant cache. These checks run on every damage hit, bot health check, HUD frame and armour
    calculation; computing them each time allocated (a closure, and TEHSkins:GetProductList() builds a new
    table per call) fast enough to exhaust the 1 GB Lua heap in a fight. A variant's classification
    never changes in a match, so after the first lookup each check is a plain table read. The cache is
    rebuilt if the TEHSF global appears/changes after the first lookup.
]]
local gCustomCache = {}
local gBMACCache = {}
local gCacheTEHSkins = false

local function CheckCacheOwner()
    local current = GetTEHSkins() or false
    if current ~= gCacheTEHSkins then
        gCacheTEHSkins = current
        gCustomCache = {}
        gBMACCache = {}
    end
end

function BMAC_GetIsCustomVariant(variant)
    if type(variant) ~= "number" then
        return true
    end
    CheckCacheOwner()
    local cached = gCustomCache[variant]
    if cached == nil then
        cached = ComputeIsCustomVariant(variant)
        gCustomCache[variant] = cached
    end
    return cached
end

function BMAC_GetIsBMACVariant(variant)
    if type(variant) ~= "number" or kRoboticMarineVariantIds == nil then
        return false    -- not cached: the robotic list may simply not be loaded yet
    end
    CheckCacheOwner()
    local cached = gBMACCache[variant]
    if cached == nil then
        cached = (not BMAC_GetIsCustomVariant(variant)) and table.icontains(kRoboticMarineVariantIds, variant)
        gBMACCache[variant] = cached
    end
    return cached
end

-- Body eligibility, decided ONCE when a skin is applied (BMAC_RefreshDurability): a real Marine
-- (JetpackMarine included) wearing a vanilla BMAC skin. HeavyMarine and DevouredPlayer inherit from
-- Marine and are excluded explicitly; Exos, commanders and spectators are not Marines.
local function GetIsEligibleMarineBody(entity)
    return entity ~= nil and entity.isa ~= nil and entity:isa("Marine")
        and not entity:isa("HeavyMarine") and not entity:isa("DevouredPlayer")
        and HasMixin(entity, "Live")
end

function BMAC_GetShouldBeBMAC(entity)
    return GetIsEligibleMarineBody(entity) and BMAC_GetIsBMACVariant(entity.variant)
end

-- The hot-path check (damage, HUD, bots, medpacks...): just reads the stored result of that decision,
-- the replicated armour-only flag. No skin lookup and no allocation, on server and client alike.
function GetIsBMACMarine(entity)
    if not GetIsEligibleMarineBody(entity) then
        return false
    end
    return entity:GetIgnoreHealth() == true
end

-- ── Per-round Marine choice: which skins a player may pick ────────────────────────────────────────
--[[
    (2026-10-15, Joshua) Two skins are free for everyone, so every player can choose either body without any DLC:
      - "Normal" (green), the default human skin (no item at all in vanilla);
      - "Chroma B.M.A.C." (chromabmac): a Thunderdome / Competitive Play reward (item 14002, menu2/items/itemDefs.lua
        "TD Chroma Items"), NOT a DLC skin. The base "B.M.A.C." is NOT free: it is in the paid B.M.A.C. Supporters Pack
        (kDlcBmacPackId / kDlcOnlyPurchasableItems), so it needs ownership like every other DLC skin.
    Every other skin - DLC or Competitive Play - is offered only if the player owns it.
]]
local function GetIsFreeVariant(variant)
    return variant == kMarineVariants.green or variant == kMarineVariants.chromabmac
end

-- Sorted ids of the skins of one body type (robotic = BMAC) that `owns(variant)` accepts, plus the free ones.
-- Custom (e.g. TEHSF) skins are Biological. Used by the choice window (client) and the server's validation.
function BMAC_GetChoosableVariants(robotic, owns)
    local list = {}
    for variant in pairs(kMarineVariantsData) do
        if type(variant) == "number" and (BMAC_GetIsBMACVariant(variant) == robotic)
                and (GetIsFreeVariant(variant) or owns(variant)) then
            list[#list + 1] = variant
        end
    end
    table.sort(list)
    return list
end

if not Server then
    return
end

-- ── Round lock ────────────────────────────────────────────────────────────────────────────────────
-- Keyed by account (Steam id) for humans, by client id for bots. Entry: { variant, marineType, custom }.
-- `variant` is the SELECTED skin; the Military Protocol chroma swap (GetVariantOverride) goes on top.
local gBMACLock = { active = false, generation = 0, entries = {} }

local function GetLockKey(client)
    if not client then
        return nil
    end
    if client.GetIsVirtual and client:GetIsVirtual() then
        return "bot:" .. tostring(client:GetId())
    end
    local userId = client.GetUserId and client:GetUserId()
    if not userId or userId == 0 then
        return nil
    end
    return "user:" .. tostring(userId)
end

--[[
    (2026-10-15) PER-ROUND CHOICE. Before each round every player picks Biological / BMAC / Random and then a skin
    (or Random) in the choice window (BMAC_RoundChoice_Client.lua); the window sends BMACRoundChoice. The choice is
    stored here and becomes the player's lock entry when the round starts (or when they first become a Marine later).
    Anything not chosen is random: no body type -> Biological or BMAC at random; no skin -> a random skin of that body
    the player owns (the default human skin and the Chroma B.M.A.C. are free). The options-menu skin no longer decides the
    round. Choices are kept until a round ends; messages during a round are ignored.
]]
local gBMACChoices = {}

-- Called by the BMACRoundChoice message hook (BMAC_NetworkMessages.lua).
function BMAC_OnRoundChoiceMessage(client, message)
    if gBMACLock.active then
        return
    end
    local key = GetLockKey(client)
    if not key then
        return
    end
    gBMACChoices[key] = { bodyType = message.bodyType, variant = message.variant ~= 0 and message.variant or nil }
end

function BMAC_ClearRoundChoices()
    gBMACChoices = {}
end

--[[
    (2026-10-15) SKIN OWNERSHIP. The server cannot check it: vanilla GetOwnsItem returns true on the server for every
    item, and every Marine skin is an item, so GetHasVariant(..., client) passes for ANY skin here. Each client reports
    the Marine skins it owns (BMACOwnedSkins, a "0"/"1" string by variant id) and the server only ever uses:
      - the free skins (Normal, Chroma B.M.A.C. - neither is DLC);
      - skins in that player's own report.
    Until a player's report has arrived, ONLY the free skins are worn (Joshua: a player must never wear a DLC skin they
    don't own, not even briefly); the report arrives within moments of connecting and their own skin then applies.
    Bots (no Steam account) may use any skin.
]]
local gBMACOwnedSkins = {}

-- Called by the BMACOwnedSkins message hook (BMAC_NetworkMessages.lua).
function BMAC_OnOwnedSkinsMessage(client, message)
    local key = GetLockKey(client)
    if key and type(message.owned) == "string" then
        gBMACOwnedSkins[key] = message.owned
        if BMAC_EnforceOwnedSkinNow then
            BMAC_EnforceOwnedSkinNow(client)    -- ownership is now known: apply the player's own (proven) skin
        end
    end
end

local function GetPlayerOwnsSkin(client, variant)
    if client.GetIsVirtual and client:GetIsVirtual() then
        return true
    end
    local key = GetLockKey(client)
    local owned = key and gBMACOwnedSkins[key]
    -- No report yet: nothing but the free skins (checked by the callers) - an unproven skin is never worn.
    return owned ~= nil and owned:sub(variant, variant) == "1"
end

-- The player's lock entry for this round from their choice, with random fill-ins. Always returns an entry.
local function ResolveRoundChoice(client)
    local key = GetLockKey(client)
    local choice = key and gBMACChoices[key]

    local bodyType = choice and choice.bodyType
    if bodyType ~= kBMACChoiceBiological and bodyType ~= kBMACChoiceBMAC then
        bodyType = math.random(2) == 1 and kBMACChoiceBiological or kBMACChoiceBMAC
    end
    local robotic = bodyType == kBMACChoiceBMAC

    -- Never a skin the player doesn't own: only free skins and skins in their own report (see above).
    local variants = BMAC_GetChoosableVariants(robotic, function(variant)
        return GetPlayerOwnsSkin(client, variant)
    end)
    local variant = choice and choice.variant
    if not (variant and table.icontains(variants, variant)) then
        if #variants > 0 then
            variant = variants[math.random(#variants)]
        else
            variant = robotic and kMarineVariants.chromabmac or kMarineVariants.green
        end
    end

    local marineType
    if robotic then
        marineType = kMarineVariantsBaseType.bigmac
    else
        -- Biological keeps the player's own male / female choice from their options.
        local data = client.variantData
        marineType = (data and data.isMale == false) and kMarineVariantsBaseType.female or kMarineVariantsBaseType.male
    end
    return { variant = variant, marineType = marineType, custom = BMAC_GetIsCustomVariant(variant) }
end

local ApplySkinToBody

local function ApplyLockToBody(marine, client)
    local key = GetLockKey(client)
    local entry = key and gBMACLock.entries[key]
    if entry then
        ApplySkinToBody(marine, client, entry)
    end
end

--[[
    (2026-10-15) Outside a round the body follows the options-menu skin (the active handler, CNBalance
    MarineVariantMixin.lua), whose server check always passes (GetOwnsItem is true on the server). This runs straight
    after it, in the same update, so nothing is ever sent to other players in between: an options skin that is neither
    free nor proven owned by the player's report (no report yet = not proven) becomes the free skin of the same body
    (Normal / Chroma B.M.A.C.). A DLC skin the player doesn't own is never worn.
]]
local function EnforceOwnedOptionsSkin(marine, client)
    local data = client and client.variantData
    local variant = data and data.marineVariant
    if type(variant) ~= "number" or GetIsFreeVariant(variant) or GetPlayerOwnsSkin(client, variant) then
        return
    end
    local robotic = BMAC_GetIsBMACVariant(variant)
    ApplySkinToBody(marine, client, {
        variant = robotic and kMarineVariants.chromabmac or kMarineVariants.green,
        marineType = robotic and kMarineVariantsBaseType.bigmac
            or (data.isMale == false and kMarineVariantsBaseType.female or kMarineVariantsBaseType.male),
    })
end

-- The owned-skins report just arrived (outside a round): re-run the normal skin update for the body the player controls,
-- so a skin they have now proven they own is applied (and anything else stays free).
function BMAC_EnforceOwnedSkinNow(client)
    if gBMACLock.active then
        return
    end
    local player = client.GetControllingPlayer and client:GetControllingPlayer()
    if player and (player:isa("Marine") or player:isa("MarineSpectator")) and player.OnClientUpdated then
        player:OnClientUpdated(client, false)
    end
end

ApplySkinToBody = function(marine, client, entry)
    local variant = marine.GetVariantOverride and marine:GetVariantOverride(entry.variant) or entry.variant
    if marine.variant == variant and marine.marineType == entry.marineType then
        return
    end
    marine.variant = variant
    marine.marineType = entry.marineType
    if not (marine.GetIgnoreVariantModels and marine:GetIgnoreVariantModels()) then
        local modelName = marine:GetVariantModel()
        if modelName and modelName ~= "" then
            marine:SetModel(modelName, MarineVariantMixin.kMarineAnimationGraph)
        end
    end
    if marine.UpdateWeaponSkin then
        marine:UpdateWeaponSkin(client)
    end
end

-- A player who first becomes a Marine during the round (late join) gets their entry now; an existing entry wins.
local function EnsureLockEntry(marine, client)
    if not gBMACLock.active or not client or marine:GetTeamNumber() ~= kMarineTeamType then
        return
    end
    local key = GetLockKey(client)
    if not key or gBMACLock.entries[key] then
        return
    end
    gBMACLock.entries[key] = ResolveRoundChoice(client)
end

-- (2026-10-15) Military Protocol completed mid-round: re-skin every Marine body of the team at once (its Chroma
-- swap, GetVariantOverride, is applied on top of the locked skin), instead of only on their next respawn.
function BMAC_ReapplyRoundLock(teamNumber)
    if not gBMACLock.active then
        return
    end
    for _, player in ipairs(GetEntitiesForTeam("Player", teamNumber)) do
        if player:isa("Marine") or player:isa("MarineSpectator") then
            ApplyLockToBody(player, player:GetClient())
        end
    end
end

function BMAC_BeginRoundLock()
    if gBMACLock.active then
        return
    end
    gBMACLock.active = true
    gBMACLock.generation = gBMACLock.generation + 1
    gBMACLock.entries = {}
    for _, player in ipairs(GetEntitiesForTeam("Player", kMarineTeamType)) do
        local client = player:GetClient()
        local key = GetLockKey(client)
        if key and not gBMACLock.entries[key] then
            gBMACLock.entries[key] = ResolveRoundChoice(client)
        end
        if player:isa("Marine") then
            ApplyLockToBody(player, client)
            BMAC_RefreshDurability(player)
        elseif player:isa("MarineSpectator") then
            ApplyLockToBody(player, client)     -- waiting to respawn: keeps the IP hologram on the locked skin
        end
    end
end

-- Safe to call repeatedly (win, draw, reset). New bodies after a reset use the latest options.
function BMAC_ClearRoundLock()
    gBMACLock.active = false
    gBMACLock.entries = {}
end

function BMAC_GetIsRoundLockActive()
    return gBMACLock.active
end

-- ── Durability ───────────────────────────────────────────────────────────────────────────────────
-- Brings a Marine's survivability mode in line with the skin it is actually wearing. Converts by
-- fraction of the pool (never a refill), and only syncs the maximum when the mode is unchanged, so
-- repeated option callbacks can't heal. `bmacCarryArmor` (set on a live BMAC -> Marine replacement such
-- as picking up a Jetpack) carries the exact AP across instead.
function BMAC_RefreshDurability(marine)
    if not marine or not marine:isa("Marine") or not HasMixin(marine, "Live") then
        return
    end

    local carry = marine.bmacCarryArmor
    marine.bmacCarryArmor = nil

    -- The one place the skin is checked against the list; the result is stored as the armour-only flag.
    local wantArmourOnly = BMAC_GetShouldBeBMAC(marine)
    local isArmourOnly = marine:GetIgnoreHealth() == true

    if not marine:GetIsAlive() then
        if wantArmourOnly ~= isArmourOnly then
            marine:SetIgnoreHealth(wantArmourOnly)
        end
        return
    end

    if wantArmourOnly then

        if not isArmourOnly then
            local maxEHP = marine:GetMaxHealth() + marine:GetMaxArmor() * kHealthPointsPerArmor
            local fraction = maxEHP > 0 and (marine:GetHealth() + marine:GetArmor() * kHealthPointsPerArmor) / maxEHP or 1
            marine:SetIgnoreHealth(true)    -- set first: GetArmorAmount's BMAC bonus reads this flag
            -- Poison doesn't affect a BMAC: drop any picked up while biological.
            marine.poisoned = false
            marine.timePoisoned = 0
            local newMaxArmor = marine:GetArmorAmount()
            marine:SetMaxArmor(newMaxArmor)
            local armor = carry or newMaxArmor * fraction
            marine:SetArmor(Clamp(armor, 1, newMaxArmor))
            -- Internal health is ignored; keep it full so no health-first code path ever sees "damaged".
            marine:SetHealth(marine:GetMaxHealth())
        else
            if marine:GetArmorAmount() ~= marine:GetMaxArmor() then
                marine:UpdateArmorAmount()
            end
            if carry then
                marine:SetArmor(Clamp(carry, 1, marine:GetMaxArmor()))
            end
        end

    elseif isArmourOnly then

        local maxArmor = marine:GetMaxArmor()
        local fraction = maxArmor > 0 and Clamp(marine:GetArmor() / maxArmor, 0, 1) or 1
        marine:SetIgnoreHealth(false)
        local newMaxArmor = marine:GetArmorAmount()
        marine:SetMaxArmor(newMaxArmor)
        marine:SetArmor(newMaxArmor * fraction)
        marine:SetHealth(math.max(1, marine:GetMaxHealth() * fraction))

    end
end

-- Exo exit: restore the AP the BMAC had when it got in. A positive saved value is kept exactly (clamped
-- only to the maximum); the fallback is for a missing/invalid value only, never a minimum.
function BMAC_RestoreAfterExoExit(marine, savedArmor)
    if not marine or not marine:isa("Marine") or not marine:GetIsAlive() then
        return
    end
    BMAC_RefreshDurability(marine)
    if not GetIsBMACMarine(marine) then
        return
    end
    local maxArmor = marine:GetArmorAmount()
    marine:SetMaxArmor(maxArmor)
    local armor
    if type(savedArmor) == "number" and savedArmor > 0 then
        armor = math.min(savedArmor, maxArmor)
    else
        armor = math.min(kBMACExitFallbackArmor, maxArmor)
    end
    marine:SetArmor(armor)
    marine:SetHealth(marine:GetMaxHealth())
end

-- ── Skin application paths ────────────────────────────────────────────────────────────────────────
-- Wrapping the MIXIN functions (not Marine's): the mixin merge runs the class function first and this
-- one last, so the variant is already set when these run.

--[[
    Bodies the round lock applies to: Marines, and the MarineSpectator a dead Marine becomes while waiting to
    respawn. The Infantry Portal's spawning hologram copies its model from that spectator
    (InfantryPortal queuedPlayerModel = playerToSpawn:GetVariantModel()), so an unlocked spectator showed the
    newly picked skin during the respawn and only reverted when the Marine appeared. Durability (below) is
    still Marine-only.
]]
local function GetIsLockableBody(entity)
    return entity:isa("Marine") or entity:isa("MarineSpectator")
end

local baseCopyPlayerDataFrom = MarineVariantMixin.CopyPlayerDataFrom
function MarineVariantMixin:CopyPlayerDataFrom(player)
    baseCopyPlayerDataFrom(self, player)

    if not GetIsLockableBody(self) then
        return
    end

    if not self:isa("Marine") then
        if gBMACLock.active then
            ApplyLockToBody(self, self:GetClient())
        elseif self:GetClient() then
            EnforceOwnedOptionsSkin(self, self:GetClient())
        end
        return
    end

    -- Live BMAC -> Marine body (Jetpack pickup, etc.): keep its exact AP, no refill.
    if player and player ~= self and player.isa and player:isa("Marine")
            and HasMixin(player, "Live") and player:GetIsAlive() and player:GetIgnoreHealth() then
        self.bmacCarryArmor = player:GetArmor()
    end

    if gBMACLock.active then
        ApplyLockToBody(self, self:GetClient())
    elseif self:GetClient() then
        EnforceOwnedOptionsSkin(self, self:GetClient())
    end
    BMAC_RefreshDurability(self)
end

local baseOnClientUpdated = MarineVariantMixin.OnClientUpdated
function MarineVariantMixin:OnClientUpdated(client, isPickup)
    baseOnClientUpdated(self, client, isPickup)

    if Shared.GetIsRunningPrediction() or not GetIsLockableBody(self) then
        return
    end

    if gBMACLock.active and client then
        EnsureLockEntry(self, client)
        -- The lock wins over whatever was just requested, custom or vanilla.
        ApplyLockToBody(self, client)
    elseif client then
        EnforceOwnedOptionsSkin(self, client)
    end
    if self:isa("Marine") then
        BMAC_RefreshDurability(self)
    end
end
