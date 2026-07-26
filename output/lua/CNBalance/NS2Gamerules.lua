 if Server then

     NS2Gamerules.kBalanceConfig = LoadConfigFile("NS2.0Config.json", {
        bountyActive = true,
        resourceEfficiency = true,
        recentWinsBalance = true,
        deadlockEnabled = true,        -- master on/off switch for the deadlock decay system
        deadlockInitialTime = 2400,    -- deadlock starts 40 minutes (2400s) into the round
        deadlockRequireMinPlayers = true,
        deadlockMinPlayers = 10        -- combined human players on Marine + Alien teams; spectators/ready room/bots do not count
     }, true)

     NS2Gamerules.kRecentRoundStatus = LoadConfigFile("NS2.0RoundStatus.json",{
     },true)
     
     function NS2Gamerules:GetRecentRoundAlienWins()
         local kRecentRoundAliensWins = 0
         if NS2Gamerules.kBalanceConfig.recentWinsBalance then
             for k,v in pairs(NS2Gamerules.kRecentRoundStatus) do
                 if v.winningTeam == kMarineTeamType then
                     kRecentRoundAliensWins = kRecentRoundAliensWins - 1
                 elseif v.winningTeam == kAlienTeamType then
                     kRecentRoundAliensWins = kRecentRoundAliensWins + 1
                 end
             end
         end
         return kRecentRoundAliensWins
     end
     
     local kRandomTencentage = -1
     function NS2Gamerules:RandomTechPoint(techPoints, teamNumber)
         local chosenIndex = math.random(1,#techPoints)
         local chosenTechPoint = techPoints[chosenIndex]
          table.removevalue(techPoints, chosenTechPoint)
         return chosenTechPoint
     end

     --local baseSetGameState = NS2Gamerules.SetGameState
     function NS2Gamerules:SetGameState(state)
         if state ~= self.gameState then

             self.gameState = state
             self.gameInfo:SetState(state)
             self.timeGameStateChanged = Shared.GetTime()
             self.timeSinceGameStateChanged = 0

             if self.gameState == kGameState.Started then

                 self.gameStartTime = Shared.GetTime()
                 self._lastDeadlockTickTime = nil

                 self.gameInfo:SetStartTime(self.gameStartTime)

                 SendTeamMessage(self.team1, kTeamMessageTypes.GameStarted)
                 SendTeamMessage(self.team2, kTeamMessageTypes.GameStarted)

                 -- Reset player resources to normal starting amounts when the game
                 -- transitions from pre-game to Started (force-start or countdown end).
                 -- Pre-game grants 100 p-res for testing; clear that on real start.
                 local function ResetPlayerRes(player, startingRes)
                     if player.SetResources and player.GetIsAlive and player:GetIsAlive() then
                         player:SetResources(startingRes)
                     end
                     player._preGameResGranted = false
                 end
                 for _, p in ipairs(GetEntitiesForTeam("Player", kTeam1Index)) do
                     ResetPlayerRes(p, kMarineInitialIndivRes)
                 end
                 for _, p in ipairs(GetEntitiesForTeam("Player", kTeam2Index)) do
                     ResetPlayerRes(p, kAlienInitialIndivRes)
                 end

             end

             -- On end game, check for map switch conditions
             if state == kGameState.Team1Won or state == kGameState.Team2Won then

                 if MapCycle_TestCycleMap() then
                     self.timeToCycleMap = Shared.GetTime() + kPauseToSocializeBeforeMapcycle
                 else
                     self.timeToCycleMap = nil
                 end

             end

         end
         
         self.team1:OnGameStateChanged(state)
         self.team2:OnGameStateChanged(state)

     end

     function NS2Gamerules:ResetGame()

         StatsUI_ResetStats()

         self:SetGameState(kGameState.NotStarted)

         TournamentModeOnReset()

         -- save commanders for later re-login
         local team1CommanderClient = self.team1:GetCommander() and self.team1:GetCommander():GetClient()
         local team2CommanderClient = self.team2:GetCommander() and self.team2:GetCommander():GetClient()

         -- Cleanup any peeps currently in the commander seat by logging them out
         -- have to do this before we start destroying stuff.
         self:LogoutCommanders()

         -- Destroy any map entities that are still around
         DestroyLiveMapEntities()

         -- Reset all players, delete other not map entities that were created during 
         -- the game (hives, command structures, initial resource towers, etc)
         -- We need to convert the EntityList to a table since we are destroying entities
         -- within the EntityList here.
         for _, entity in ientitylist(Shared.GetEntitiesWithClassname("Entity")) do

             local allowDestruction = true

             for _, className in ipairs(self.resetProtectedEntities) do
                 allowDestruction = allowDestruction and not entity:isa(className)
             end

             if allowDestruction and entity:GetParent() == nil then

                 -- Reset all map entities and all player's that have a valid Client (not ragdolled players for example).
                 local resetEntity = entity:isa("TeamInfo") or entity:GetIsMapEntity() or (entity:isa("Player") and entity:GetClient() ~= nil)
                 if resetEntity then

                     if entity.Reset then
                         entity:Reset()
                     end

                 else
                     DestroyEntity(entity)
                 end

             end

         end

         -- Clear out obstacles from the navmesh before we start repopualating the scene
         RemoveAllObstacles()

         -- Build list of tech points
         local techPoints = EntityListToTable(Shared.GetEntitiesWithClassname("TechPoint"))
         if #techPoints < 2 then
             Print("Warning -- Found only %d %s entities.", table.maxn(techPoints), TechPoint.kMapName)
         end

         local resourcePoints = Shared.GetEntitiesWithClassname("ResourcePoint")
         if resourcePoints:GetSize() < 2 then
             Print("Warning -- Found only %d %s entities.", resourcePoints:GetSize(), ResourcePoint.kPointMapName)
         end

         -- add obstacles for resource points back in
         for _, resourcePoint in ientitylist(resourcePoints) do
             resourcePoint:AddToMesh()
         end


         local randomSpawn = math.random(1,10)<= kRandomTencentage
         local team1TechPoint, team2TechPoint

         if randomSpawn then
             team1TechPoint = self:RandomTechPoint(techPoints, kTeam1Index)
             team2TechPoint = self:RandomTechPoint(techPoints, kTeam2Index)
         elseif Server.teamSpawnOverride and #Server.teamSpawnOverride > 0 then

             for t = 1, #techPoints do

                 local techPointName = string.lower(techPoints[t]:GetLocationName())
                 local selectedSpawn = Server.teamSpawnOverride[1]
                 if techPointName == selectedSpawn.marineSpawn then
                     team1TechPoint = techPoints[t]
                 elseif techPointName == selectedSpawn.alienSpawn then
                     team2TechPoint = techPoints[t]
                 end

             end

             if not team1TechPoint or not team2TechPoint then
                 Shared.Message("Invalid spawns, defaulting to normal spawns")
                 if Server.spawnSelectionOverrides then

                     local selectedSpawn = self.techPointRandomizer:random(1, #Server.spawnSelectionOverrides)
                     selectedSpawn = Server.spawnSelectionOverrides[selectedSpawn]

                     for t = 1, #techPoints do

                         local techPointName = string.lower(techPoints[t]:GetLocationName())
                         if techPointName == selectedSpawn.marineSpawn then
                             team1TechPoint = techPoints[t]
                         elseif techPointName == selectedSpawn.alienSpawn then
                             team2TechPoint = techPoints[t]
                         end

                     end

                 else

                     -- Reset teams (keep players on them)
                      team1TechPoint = self:ChooseTechPoint(techPoints, kTeam1Index)
                      team2TechPoint = self:ChooseTechPoint(techPoints, kTeam2Index)

                 end

             end

         elseif Server.spawnSelectionOverrides then

             local selectedSpawn = self.techPointRandomizer:random(1, #Server.spawnSelectionOverrides)
             selectedSpawn = Server.spawnSelectionOverrides[selectedSpawn]

             for t = 1, #techPoints do

                 local techPointName = string.lower(techPoints[t]:GetLocationName())
                 if techPointName == selectedSpawn.marineSpawn then
                     team1TechPoint = techPoints[t]
                 elseif techPointName == selectedSpawn.alienSpawn then
                     team2TechPoint = techPoints[t]
                 end

             end

         else

             -- Reset teams (keep players on them)
             team1TechPoint = self:ChooseTechPoint(techPoints, kTeam1Index)
             team2TechPoint = self:ChooseTechPoint(techPoints, kTeam2Index)

         end

         self.team1:ResetPreservePlayers(team1TechPoint)
         self.team2:ResetPreservePlayers(team2TechPoint)

         assert(self.team1:GetInitialTechPoint() ~= nil)
         assert(self.team2:GetInitialTechPoint() ~= nil)

         -- Save data for end game stats later.
         self.startingLocationNameTeam1 = team1TechPoint:GetLocationName()
         self.startingLocationNameTeam2 = team2TechPoint:GetLocationName()
         self.startingLocationsPathDistance = GetPathDistance(team1TechPoint:GetOrigin(), team2TechPoint:GetOrigin())
         self.initialHiveTechId = nil

         self.worldTeam:ResetPreservePlayers(nil)
         self.spectatorTeam:ResetPreservePlayers(nil)

         -- Reset all bot brains
         for i = 1, #gServerBots do
             gServerBots[i]:Reset()
         end

         for i = 1, #gCommanderBots do
             gCommanderBots[i]:Reset()
         end

         -- Reset location contention variables after resetting players to ensure old data is cleared
         GetLocationContention():ResetAllGroups()

         -- Reset location staleness after all entities are destroyed
         GetLocationContention():ResetAllGroupsStaleness()
         Log("Reset location group stale timers")

         -- Replace players with their starting classes with default loadouts at spawn locations
         self.team1:ReplaceRespawnAllPlayers()
         self.team2:ReplaceRespawnAllPlayers()

         self.clientpres = {}

         -- Create team specific entities
         local commandStructure1 = self.team1:ResetTeam()
         local commandStructure2 = self.team2:ResetTeam()

         -- login the commanders again
         local function LoginCommander(commandStructure, client)
             local player = client and client:GetControllingPlayer()

             if commandStructure and player and commandStructure:GetIsBuilt() then

                 -- make up for not manually moving to CS and using it
                 commandStructure.occupied = not client:GetIsVirtual()

                 player:SetOrigin(commandStructure:GetDefaultEntryOrigin())

                 commandStructure:LoginPlayer( player, true )
             else
                 if player then
                     Log("%s| Failed to Login commander[%s - %s(%s)] on ResetGame", self:GetClassName(), player:GetClassName(), player:GetId(),
                             client:GetIsVirtual() and "BOT" or "HUMAN"
                     )
                 end
             end
         end

         LoginCommander(commandStructure1, team1CommanderClient)
         LoginCommander(commandStructure2, team2CommanderClient)
         
         -- Create living map entities fresh
         CreateLiveMapEntities()

         self.forceGameStart = false
         self.preventGameEnd = nil

         -- Reset banned players for new game
         if not self.bannedPlayers then
             self.bannedPlayers = unique_set()
         end
         self.bannedPlayers:Clear()

         -- Send scoreboard and tech node update, ignoring other scoreboard updates (clearscores resets everything)
         for _, player in ientitylist(Shared.GetEntitiesWithClassname("Player")) do
             Server.SendCommand(player, "onresetgame")
             player.sendTechTreeBase = true
         end

         self.team1:OnResetComplete()
         self.team2:OnResetComplete()

         StatsUI_InitializeTeamStatsAndTechPoints(self)
     end

     
     
     function NS2Gamerules:OnUpdate(timePassed)

         PROFILE("NS2Gamerules:OnUpdate")

         if Server then

             if self.justCreated then
                 if not self.gameStarted then
                     self:ResetGame()
                 end
                 self.justCreated = false
             end

             if self:GetMapLoaded() then

                 self:CheckGameStart()
                 self:CheckGameEnd()

                 self:UpdateWarmUp()
                 self:UpdatePregame(timePassed)
                 self:UpdateToReadyRoom()
                 self:UpdateMapCycle()
                 self:ServerAgeCheck()
                 self:UpdateAutoTeamBalance(timePassed)

                 self.timeSinceGameStateChanged = self.timeSinceGameStateChanged + timePassed

                 self.worldTeam:Update(timePassed)
                 self.team1:Update(timePassed)
                 self.team2:Update(timePassed)
                 self.spectatorTeam:Update(timePassed)

                 self:UpdatePings()
                 self:UpdateHealth()
                 self:UpdateTechPoints()

                 self:CheckForNoCommander(self.team1, "MarineCommander")
                 --self:CheckForNoCommander(self.team2, "AlienCommander")
                 self:KillEnemiesNearCommandStructureInPreGame(timePassed)

                 self:UpdatePlayerSkill()
                 self:UpdateNumPlayersForScoreboard()
                 self:UpdatePreGameResources()

                 self.gameInfo:SetMarineDeadlockTime(self.team1.deadlockTime)
                 self.gameInfo:SetAlienDeadlockTime(self.team2.deadlockTime)
                 if Shared.GetThunderdomeEnabled() then
                     GetThunderdomeRules():CheckForAutoConcede(self)
                 end

             end

         end

     end
     
     -- ── Pre-game: 100 p-res on every spawn ───────────────────────────────────
     -- While the round has NOT started yet (any state before kGameState.Started),
     -- give every marine/alien player 100 personal resources each time they spawn,
     -- so players can freely test purchases until the game state changes.
     -- The grant fires once per life (tracked by a per-entity flag that resets on
     -- death; respawns create fresh entities, so each spawn re-grants).
     local kPreGameSpawnResources = 100
     function NS2Gamerules:UpdatePreGameResources()

         -- Only during the pre-round period; once the game has started, stop.
         if self:GetGameState() >= kGameState.Started then
             return
         end

         local function ProcessPlayer(player)
             if not player.SetResources or not player.GetIsAlive then return end
             if player:GetIsAlive() then
                 if not player._preGameResGranted then
                     player:SetResources(kPreGameSpawnResources)
                     player._preGameResGranted = true
                 end
             else
                 player._preGameResGranted = false
             end
         end

         for _, player in ipairs(GetEntitiesForTeam("Player", kTeam1Index)) do
             ProcessPlayer(player)
         end
         for _, player in ipairs(GetEntitiesForTeam("Player", kTeam2Index)) do
             ProcessPlayer(player)
         end

     end

     function NS2Gamerules:BroadCastVO(_name)
         self.worldTeam:PlayPrivateTeamSound(_name)
         self.team1:PlayPrivateTeamSound(_name)
         self.team2:PlayPrivateTeamSound(_name)
         self.spectatorTeam:PlayPrivateTeamSound(_name)
     end
     
     local baseEndGame = NS2Gamerules.EndGame
     function NS2Gamerules:EndGame(winningTeam, autoConceded)
         baseEndGame(self,winningTeam,autoConceded)
         local lastRoundData = CHUDGetLastRoundStats();
         
         if not lastRoundData then
             Shared.Message("[NS2.0] ERROR Option 'savestats' not enabled ")
             return
         end
         
         local roundLength = lastRoundData.RoundInfo.roundLength
         local playerCount = table.countkeys(lastRoundData.PlayerStats)
         if roundLength < 300 or playerCount < 12 then return end
         
         table.insert(self.kRecentRoundStatus, 1, {
                time = os.time() ,
                winningTeam = lastRoundData.RoundInfo.winningTeam,
                map = lastRoundData.RoundInfo.mapName,
                length = roundLength,
                playerCount = playerCount,
            }
         )
         self.kRecentRoundStatus[11] = nil
         SaveConfigFile("NS2.0RoundStatus.json",self.kRecentRoundStatus)
     end

     -- Override vanilla: cross-team voice is allowed only while the game state
     -- is still <= PreGame. As soon as the state transitions to Countdown (after
     -- shuffle + base spawn), cross-team voice is cut off mid-stream so plans don't
     -- leak to the enemy when players hold the talk key through round start.
     -- 'alltalk' (full all-talk) is preserved unconditionally.
     function NS2Gamerules:GetCanPlayerHearPlayer(listenerPlayer, speakerPlayer, channelType)

         local canHear = false

         if Server.GetConfigSetting("alltalk")
            or (Server.GetConfigSetting("pregamealltalk") and self:GetGameState() <= kGameState.PreGame) then
             return true
         end

         -- Check if the listener has the speaker muted.
         if listenerPlayer:GetClientMuted(speakerPlayer:GetClientIndex()) then
             return false
         end

         -- If both players have the same team number, they can hear each other
         if listenerPlayer:GetTeamNumber() == speakerPlayer:GetTeamNumber() then
             if channelType == nil or channelType == VoiceChannel.Global then
                 canHear = true
             else
                 canHear = listenerPlayer:GetDistance(speakerPlayer) < kMaxWorldSoundDistance
             end
         end

         -- Cheats + dev mode override
         if Shared.GetCheatsEnabled() and Shared.GetDevMode() then
             canHear = true
         end

         return canHear

     end

     -- Credit a Prowler for an environmental (lava / void) kill of a marine it reeled.
     -- Lava and void pits kill via a DeathTrigger entity, which is passed as BOTH the
     -- attacker and the doer (see DeathTrigger:DoDamageOverTime / :KillEntity) - never an
     -- alien weapon. So "attacker is a DeathTrigger" is exactly the case where the game
     -- world (not an alien) landed the killing blow. If the marine was reeled by a Prowler
     -- within kProwlerReelKillWindow seconds, reattribute the kill to that Prowler + its
     -- Rappel weapon. If instead an alien (e.g. a Fade's swipe) dealt the killing blow, the
     -- attacker is that alien, this branch is skipped, and the alien correctly keeps the kill.
     -- The reel-window / DeathTrigger / Prowler-still-alive test lives in ONE place
     -- (GetProwlerReelKillCredit, CNBalance/Globals.lua) so this killfeed path and the
     -- PointGiverMixin:PreOnKill path (scoreboard kill + bounty + p-res) can never disagree.
     local baseOnEntityKilled = NS2Gamerules.OnEntityKilled
     function NS2Gamerules:OnEntityKilled(targetEntity, attacker, doer, point, direction)

         local prowler = GetProwlerReelKillCredit
                         and GetProwlerReelKillCredit(targetEntity, attacker)
         if prowler then
             attacker = prowler
             -- Doer = the Prowler's Rappel weapon so the kill is credited "with the
             -- Rappel weapon" (its death icon); fall back to the Prowler itself.
             local rappelMapName = VolleyRappel and VolleyRappel.kMapName or "volley"
             doer = (prowler.GetWeapon and prowler:GetWeapon(rappelMapName)) or prowler
         end

         baseOnEntityKilled(self, targetEntity, attacker, doer, point, direction)
     end
 end
