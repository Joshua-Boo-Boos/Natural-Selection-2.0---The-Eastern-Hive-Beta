-- CNBalance/CombatEngineers_Commander.lua
-- Combat Engineers: Military Protocol / Combat Engineers mutual exclusion, and the commander
-- lockdown that follows once CE is chosen.
--
-- Loaded post lua/MarineCommander.lua, which is late enough for the mod's own "replace" of that
-- file, for lua/MarineCommander_Server.lua, and for lua/Commander_Buttons.lua (pulled in via
-- lua/Commander.lua).
--
-- WHITELIST-MOD SAFETY: nothing here ever changes the CONTENTS or LENGTH of any tech button list.
-- Both mode buttons stay in CommandStation:GetTechButtons() for the whole round and every blocked
-- action keeps its slot. Buttons are made UNAVAILABLE instead, which is what greys them out. A mod
-- that whitelists buttons by position or tech id therefore keeps seeing exactly what it expects.

-- Read the TECH TREE rather than the Team object. Team methods like IsCombatEngineers() exist only
-- on the server; the tech tree is networked to commanders, so one implementation works on both
-- sides and the greying can never disagree with the enforcement.
local function GetTechNodeFor(commander, techId)

    local techTree = commander.GetTechTree and commander:GetTechTree()
    if not techTree and GetTechTree then
        techTree = GetTechTree()
    end

    return techTree and techTree:GetTechNode(techId) or nil
end

-- "Chosen" deliberately includes research still IN PROGRESS. Without that half a commander could
-- start both modes inside the 10 second window and end up with both.
local function GetIsModeChosen(commander, techId)

    -- Warmup makes TechNode:GetResearched() true for EVERY tech (TechNode.lua:105). Without this
    -- guard BOTH mode buttons would read as chosen during the pre-game, so each would grey the
    -- other out and the commander could pick neither - and the CE lockdown would already be active.
    if GetCombatEngineersWarmup() then
        return false
    end

    local node = GetTechNodeFor(commander, techId)
    return node ~= nil and (node:GetResearched() or node:GetResearching())
end

-- Is this tech id one of the two mutually exclusive mode researches, blocked because the OTHER one
-- has already been chosen?
local function GetIsModeBlocked(commander, techId)

    if techId == kTechId.MilitaryProtocol then
        return GetIsModeChosen(commander, kTechId.CombatEngineers)
    end

    if techId == kTechId.CombatEngineers then
        return GetIsModeChosen(commander, kTechId.MilitaryProtocol)
    end

    return false
end

-- Once CE is RESEARCHED (not merely started) the commander may only select, order, Scan, Beacon and
-- run ARCs. Using researched-only here means the 10 second research window is a genuine escape
-- hatch: the commander can still cancel it, because Cancel stays allowed and nothing else has locked
-- down yet.
local function GetIsLockedDown(commander, techId)

    -- Same warmup caveat as above: without this the commander would be locked out of everything
    -- during the pre-game, when every tech reads as researched.
    if GetCombatEngineersWarmup() then
        return false
    end

    local node = GetTechNodeFor(commander, kTechId.CombatEngineers)
    if not node or not node:GetResearched() then
        return false
    end

    return kCombatEngineersCommanderAllowed[techId] ~= true
end

function MarineCommander:GetIsCombatEngineersActionAllowed(techId)
    return not GetIsModeBlocked(self, techId) and not GetIsLockedDown(self, techId)
end

-- ============================================================
-- Visual: grey the button out
-- ============================================================
-- Commander:GetTechAllowed feeds menuTechButtonsAllowed, which CommanderUI_MenuButtonStatus turns
-- into status 3 ("greyed"). GUICommanderButtons only fires a click on status 1, so greying here also
-- stops the click - but it is presentation, and the server check below is what actually enforces it.
local baseGetTechAllowed = MarineCommander.GetTechAllowed

function MarineCommander:GetTechAllowed(techId, techNode, player)

    local allowed, canAfford = baseGetTechAllowed(self, techId, techNode, player)

    if not self:GetIsCombatEngineersActionAllowed(techId) then
        return false, canAfford
    end

    return allowed, canAfford
end

if Client then

-- GetTechAllowed above is NOT sufficient on its own: Commander_Buttons only consults the COMMANDER's
-- GetTechAllowed when nothing is selected. With a structure selected it calls that ENTITY's
-- GetTechAllowed instead, so a blocked button (Advanced Armory with an Armory selected, say) would
-- still look available and would fail silently on the server.
--
-- CommanderUI_MenuButtonStatus is the one choke point both paths pass through, so the greying is
-- applied here as well. Statuses: 0 hidden, 1 available, 2 red/unaffordable, 3 greyed, 4 passive.
local baseMenuButtonStatus = CommanderUI_MenuButtonStatus

function CommanderUI_MenuButtonStatus(index)

    local status = baseMenuButtonStatus(index)

    -- Only downgrade things that are currently clickable; never resurrect a hidden or passive button.
    if status ~= 1 and status ~= 2 then
        return status
    end

    local player = Client.GetLocalPlayer()
    if not player or not player.menuTechButtons or not player:isa("MarineCommander") then
        return status
    end

    local techId = player.menuTechButtons[index]
    if techId and player.GetIsCombatEngineersActionAllowed
       and not player:GetIsCombatEngineersActionAllowed(techId) then
        return 3
    end

    return status
end

end -- if Client

if Server then

-- ============================================================
-- Authoritative: refuse the action outright
-- ============================================================
local baseProcessTechTreeActionForEntity = MarineCommander.ProcessTechTreeActionForEntity

function MarineCommander:ProcessTechTreeActionForEntity(techNode, position, normal, pickVec, orientation, entity, trace, targetId)

    local techId = techNode:GetTechId()

    if not self:GetIsCombatEngineersActionAllowed(techId) then
        self:TriggerInvalidSound()
        return false, false
    end

    return baseProcessTechTreeActionForEntity(self, techNode, position, normal, pickVec, orientation, entity, trace, targetId)
end

end -- if Server
