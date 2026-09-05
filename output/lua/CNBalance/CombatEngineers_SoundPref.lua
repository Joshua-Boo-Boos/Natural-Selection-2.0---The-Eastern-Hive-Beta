-- CNBalance/CombatEngineers_SoundPref.lua
-- The "play Combat Engineers sounds" client preference, and the plumbing that lets a CLIENT-side
-- checkbox suppress SERVER-side sounds.
--
-- Most CE cues are played with Server.PlayPrivateSound (see CombatEngineers_Team.lua), which the
-- receiving client has no say in - so the preference has to travel to the server. The client sends
-- it whenever it changes and whenever it (re)joins; the server remembers it per player and skips
-- them when broadcasting. Anyone who has never sent anything is treated as ENABLED, which matches
-- the option's default and means an older client, or one that somehow never sends, behaves exactly
-- as before rather than going silent.
--
-- Loaded post lua/TechData.lua, alongside the other CE shared files.

-- Also read directly by the Mods-menu checkbox (CombatEngineers_ModsMenuData.lua) as its optionPath,
-- so the two can never disagree about where the value lives.
kCombatEngineersSoundOptionPath = "CombatEngineers/PlaySounds"

if Client then

    -- Renders a Combat Engineers announcement with no "(Team)"/"(All)" prefix.
    --
    -- ChatUI_AddSystemMessage is the only entry point Chat.lua exposes that writes a bare line - the
    -- message list itself is a file-local, so nothing else can reach it without replacing that whole
    -- file. It carries the system colour rather than marine blue; that is the cost of getting the
    -- exact requested format, and it is easy to revisit if the colour matters more than the prefix.
    Client.HookNetworkMessage("CETeamAnnounce", function(message)

        if not message or not message.message then
            return
        end

        -- Team-coloured, no "(Team)" prefix (CombatEngineers_Chat.lua). Falls back to the plain
        -- system line if that hook did not load, so an announcement is never lost outright - it just
        -- comes through in the system colour instead.
        if CombatEngineers_AddTeamChatLine and CombatEngineers_AddTeamChatLine(message.message) then
            return
        end

        if ChatUI_AddSystemMessage then
            ChatUI_AddSystemMessage(message.message)
        end

    end)

    -- The local player's current setting. Used directly for the one CE sound that is played
    -- client-side (the build-menu open in CombatBuilder.lua); everything else is server-driven and
    -- goes through the message below.
    function CombatEngineers_GetSoundsEnabled()
        return Client.GetOptionBoolean(kCombatEngineersSoundOptionPath, true) == true
    end

    --[[
        CLIENT-SIDE once-per-life, for the two cues that never reach the server.

        The build-menu open and the credits-taken cues are played locally with Shared.PlaySound so
        they are instant, which means the server's ledger never sees them. This is the same rule kept
        on this side: each plays at most once per life, and nothing plays with the option off.

        The life boundary is watched rather than hooked. LocalPlayerChanged alone would be wrong - it
        also fires on a class change, and a marine buying an Exo has not started a new life - so what
        is actually tracked is the DEAD -> ALIVE transition of the local player, which is what a new
        life is. Starting from `true` means a client that loads mid-life does not immediately grant
        itself a fresh set.
    ]]
    local gCEPlayedThisLife = {}
    local gCEWasAlive       = true

    Event.Hook("UpdateClient", function()

        local player = Client.GetLocalPlayer()
        local alive  = player ~= nil and player.GetIsAlive ~= nil and player:GetIsAlive() == true

        if alive and not gCEWasAlive then
            gCEPlayedThisLife = {}
        end

        gCEWasAlive = alive

    end)

    -- Claim-and-play, mirroring the server's CombatEngineers_ClaimSound: asking and playing are one
    -- step so the ledger cannot drift from what was actually heard.
    function CombatEngineers_PlayLocalSoundOnce(soundName)

        if not soundName then
            return false
        end

        if not CombatEngineers_GetSoundsEnabled() then
            return false
        end

        if gCEPlayedThisLife[soundName] then
            return false
        end

        gCEPlayedThisLife[soundName] = true
        Shared.PlaySound(nil, soundName, kCombatEngineersSoundVolume or 1.0)

        return true
    end

    function CombatEngineers_SendSoundPref(enabled)

        if enabled == nil then
            enabled = CombatEngineers_GetSoundsEnabled()
        end

        Client.SendNetworkMessage("CESoundPref", { enabled = enabled == true }, true)

    end

    -- Sent on every local player change, not just on connect: that covers the initial join, a map
    -- change, and rejoining a server, all of which give the server a fresh player entity with no
    -- recollection of this client's preference.
    Event.Hook("LocalPlayerChanged", function()
        CombatEngineers_SendSoundPref()
    end)

end

if Server then

    -- Keyed by Steam id rather than by player entity: the entity is destroyed and recreated on every
    -- respawn, team change and class change, and the preference must survive all of those.
    local gCombatEngineersSoundPref = {}

    function CombatEngineers_GetSoundsEnabledFor(player)

        if not player or not player.GetClient then
            return true
        end

        local client = player:GetClient()
        if not client or not client.GetUserId then
            return true
        end

        -- Absent = never told otherwise = enabled, matching the checkbox default.
        return gCombatEngineersSoundPref[client:GetUserId()] ~= false
    end

    -- Broadcast a Combat Engineers line to every player on a team, in that team's colour.
    --
    -- Deliberately the SAME mechanism the alien Origin Form resource-fetch announcement uses
    -- (AlienTeam:OnOriginFormResourceFetch): a "Chat" network message built by BuildChatMessage and
    -- sent to each player on the team individually. The team TYPE argument is what colours the line,
    -- so passing the marine team's type is what makes these come out marine blue - there is no
    -- separate colour parameter to set.
    --
    -- Not gated on the sound option: that checkbox is about audio, and silencing the cues should not
    -- also hide what the team is doing.
    function CombatEngineers_SendTeamMessage(team, text)

        if not team or not text then
            return
        end

        for _, player in ipairs(GetEntitiesForTeam("Player", team:GetTeamNumber())) do
            Server.SendNetworkMessage(player, "CETeamAnnounce", { message = string.sub(text, 1, 220) }, true)
        end

    end

    -- A display name that is safe to build on the SERVER.
    --
    -- LookupTechData returns a LOCALE KEY ("COMMAND_STATION"), and Locale.ResolveString turns that
    -- into "Command Station" - but Locale is a client-side facility, and calling it server-side is
    -- the most likely reason these announcements silently never arrived: the placement itself had
    -- already finished, so a throw here lost the message while leaving the structure standing, which
    -- is exactly the reported symptom.
    --
    -- Resolves through Locale when it is genuinely available and otherwise turns the key into
    -- readable text itself, so the announcement is never the thing that breaks.
    -- The six Arms Lab upgrades get explicit names. Their tech data display names resolve to things
    -- like "Marine Armor2", which is how the commander's own UI labels them but reads badly in a
    -- sentence - "Armor Level 2" is what these are called everywhere else in this mode.
    local kCombatEngineersTechNames =
    {
        [kTechId.Armor1]   = "Armor Level 1",
        [kTechId.Armor2]   = "Armor Level 2",
        [kTechId.Armor3]   = "Armor Level 3",
        [kTechId.Weapons1] = "Weapons Level 1",
        [kTechId.Weapons2] = "Weapons Level 2",
        [kTechId.Weapons3] = "Weapons Level 3",
    }

    function CombatEngineers_GetDisplayName(techId)

        local explicit = kCombatEngineersTechNames[techId]
        if explicit then
            return explicit
        end

        local key = LookupTechData(techId, kTechDataDisplayName, nil)
        if not key or key == "" then
            return "Structure"
        end

        if Locale and Locale.ResolveString then
            local resolved = Locale.ResolveString(key)
            -- ResolveString hands the key straight back when there is no entry for it, so an
            -- unresolved key has to be detected and tidied rather than printed raw.
            if resolved and resolved ~= "" and resolved ~= key then
                return resolved
            end
        end

        -- "COMMAND_STATION" -> "Command Station"
        local pretty = key:gsub("_", " "):lower()
        pretty = pretty:gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end)
        return pretty
    end

    -- "a" or "an" to suit the word that follows.
    --
    -- A plain leading-vowel test, which is correct for every structure in this mode: an Armory, an
    -- Arms Lab, an Extractor, an Observatory, an Infantry Portal; a Command Station, a Phase Gate, a
    -- Prototype Lab, a Robotics Factory, a Sentry Battery. English also wants "a" before a vowel
    -- LETTER that is pronounced as a consonant ("a Unit"), but nothing here starts with one - worth
    -- knowing if a structure named that way is ever added.
    function CombatEngineers_GetArticleFor(word)

        local first = word and word:sub(1, 1):lower()

        if first and first:match("[aeiou]") then
            return "an"
        end

        return "a"
    end

    -- The room a point sits in, or a sane placeholder.
    function CombatEngineers_GetLocationName(origin)

        local location = origin and GetLocationForPoint and GetLocationForPoint(origin)
        return (location and location:GetName()) or "an unknown location"
    end

    -- Every Combat Engineers announcement carries this tag so the team can tell them apart from
    -- ordinary chat at a glance.
    function CombatEngineers_FormatTeamMessage(text)
        return string.format("[Com. Eng.]: %s", text)
    end

    --[[
        HOW OFTEN A CE VOICE CLIP IS ALLOWED TO PLAY

        The cues are announcements, not feedback: hearing "Arms Lab constructed" on the fifth Arms
        Lab of a life tells a player nothing the first one did not, and repeating them turns a piece
        of flavour into noise. So each clip is CLAIMED rather than simply played.

        Option ON  - every clip plays at most ONCE PER LIFE, per player. Dying resets the slate, so a
                     new life hears each cue again the first time it is earned.
        Option OFF - silence, with ONE exception: the Combat Engineers research cue. That one is not
                     flavour, it is the announcement that the whole game mode has just turned on, and
                     a player who muted the voices still needs to know. It ignores the opt-out.
        Either way - the research cue plays ONCE PER ROUND and never again, whatever the setting.

        Both ledgers are keyed by STEAM ID, not by player entity: the entity is destroyed and rebuilt
        on respawn, team change and class change, and a marine buying an Exo has not started a new
        life. Keying by entity would hand them the whole set of cues over again.
    ]]

    -- [userId] = { [soundName] = true }. Cleared when that player respawns.
    local gCESoundsPlayedThisLife = {}

    -- [userId] = true. Cleared when the round resets.
    local gCEResearchedPlayedThisRound = {}

    local function GetSoundUserId(player)

        if not player or player.isVirtual or not player.GetClient then
            return nil
        end

        local client = player:GetClient()
        if not client or not client.GetUserId then
            return nil
        end

        return client:GetUserId()
    end

    -- A new life for this player: everything is hearable again.
    function CombatEngineers_ResetSoundHistoryForPlayer(player)

        local userId = GetSoundUserId(player)
        if userId then
            gCESoundsPlayedThisLife[userId] = nil
        end

    end

    -- A new round: both ledgers start empty, including the once-per-round research cue.
    function CombatEngineers_ResetSoundHistory()
        gCESoundsPlayedThisLife      = {}
        gCEResearchedPlayedThisRound = {}
    end

    --[[
        Decide whether this player hears this clip right now, and RECORD the decision.

        Claiming and playing are one step deliberately. Splitting them into "may I?" followed by
        "played it" invites a caller to ask without playing, or play without asking, and either drifts
        the ledger out of step with what was actually heard.
    ]]
    function CombatEngineers_ClaimSound(player, soundName)

        if not soundName then
            return false
        end

        -- No client behind it = nothing to play to (bots, entities mid-teardown). Nothing is recorded
        -- either, so a player taking over a bot slot still gets a full set of cues.
        local userId = GetSoundUserId(player)
        if not userId then
            return false
        end

        -- The research cue: once per round, opt-out or not.
        if soundName == kCombatEngineersResearchedSound then

            if gCEResearchedPlayedThisRound[userId] then
                return false
            end

            gCEResearchedPlayedThisRound[userId] = true
            return true

        end

        -- Everything else obeys the checkbox, and then once per life.
        if not CombatEngineers_GetSoundsEnabledFor(player) then
            return false
        end

        local played = gCESoundsPlayedThisLife[userId]

        if not played then
            played = {}
            gCESoundsPlayedThisLife[userId] = played
        end

        if played[soundName] then
            return false
        end

        played[soundName] = true
        return true

    end

    -- Play a CE sound privately to one player. Every CE sound goes through here or through
    -- CombatEngineers_ClaimSound directly, so the volume, the opt-out, the bot guard and the
    -- once-per-life rule can never drift apart between call sites.
    function CombatEngineers_PlaySoundFor(player, soundName)

        if not CombatEngineers_ClaimSound(player, soundName) then
            return
        end

        Server.PlayPrivateSound(player, soundName, player, kCombatEngineersSoundVolume or 1.0, Vector(0, 0, 0))

    end

    -- Forget a disconnecting player's ledgers, so a reconnect is a clean slate rather than an
    -- inherited one, and the tables do not grow across a long-running server.
    Event.Hook("ClientDisconnect", function(client)

        local userId = client and client.GetUserId and client:GetUserId()

        if userId then
            gCESoundsPlayedThisLife[userId]      = nil
            gCEResearchedPlayedThisRound[userId] = nil
        end

    end)

    -- Every player on a team hears their OWN copy.
    function CombatEngineers_PlaySoundForTeamNumber(teamNumber, soundName)

        for _, player in ipairs(GetEntitiesForTeam("Player", teamNumber)) do
            CombatEngineers_PlaySoundFor(player, soundName)
        end

    end

    Server.HookNetworkMessage("CESoundPref", function(client, message)

        if not client or not client.GetUserId then
            return
        end

        gCombatEngineersSoundPref[client:GetUserId()] = message.enabled == true

    end)

end
