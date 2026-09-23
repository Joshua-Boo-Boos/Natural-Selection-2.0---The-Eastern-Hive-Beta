
Script.Load("lua/BiomassHealthMixin.lua")
local baseOnCreate = ARC.OnCreate
function ARC:OnCreate()
    baseOnCreate(self)
    InitMixin(self, BiomassHealthMixin)
end

function ARC:GetExtraHealth(techLevel,extraPlayers,recentWins)
    return kARCHealthPerPlayerAdd * extraPlayers
end

local baseValidateTargetPosition = ARC.ValidateTargetPosition
function ARC:ValidateTargetPosition(position)
    -- The base (vanilla ARC:ValidateTargetPosition) ALREADY returns false when any
    -- ShadeInk cloud is within kShadeInkDisorientRadius of the target - so an existing
    -- cloud already blocks the ARC (and cancels a charging shot, since UpdateTargetingPosition
    -- re-runs this every update). This override only ADDS the auto-ink parry: if no cloud
    -- exists yet, a READY nearby shade inks on this shot ("oh no, quickly Ink!") and the
    -- fresh cloud then blocks the ARC via the base check on subsequent updates.
    local successful = baseValidateTargetPosition(self,position)
    if successful then
        successful = not AlienDetectionParry(GetEnemyTeamNumber(self:GetTeamNumber()),position,ShadeInk.kShadeInkDisorientRadius)
    end
    return successful
end

-- A DEPLOYED ARC MUST NEVER SLEEP.
--
-- Vanilla ARC:GetCanSleep() is `self.mode == ARC.kMode.Stationary`, and ARC:AcquireTarget() sets
-- exactly that mode whenever it fails to find a target. So a deployed ARC with nothing to shoot
-- becomes eligible to sleep, and sleeping stops OnUpdate - which is the ONLY caller of UpdateOrders,
-- which is the only caller of AcquireTarget. The ARC therefore loses the ability to notice that a
-- target has arrived, and nothing in its own code can ever wake it again: SleeperMixin only re-wakes
-- an entity whose GetCanSleep() has turned false, and this one's cannot change while it is asleep.
--
-- An ARC that nobody can deploy must deploy ITSELF.
--
-- ARCs spawn Undeployed (ARC.lua sets kDeployMode.Undeployed on init) and GetInAttackMode() - the
-- gate on all auto-targeting - is literally "am I Deployed". The only thing that ever deploys one is
-- an ARCDeploy order, which comes from a commander clicking the deploy button. So with NO COMMANDER
-- in the chair an ARC is built, is controllable, looks perfectly healthy, and can never fire, because
-- nothing in the game will ever ask it to deploy. That is the reported bug, and it is upstream of the
-- sleep deadlock handled below - fixing sleep alone would not have helped an ARC that never deploys.
--
-- Deploy() takes an optional commander purely to decide whether to QUEUE the deploy behind a shift
-- order; passed nil it deploys immediately, so calling it unattended is exactly the intended path.
local function GetShouldAutoDeploy(self)

    if self.deployMode ~= ARC.kDeployMode.Undeployed then
        return false
    end

    --[[
        NO GetIsBuilt CHECK. An ARC has no ConstructMixin.

        This line used to read `if not self:GetIsBuilt() or not self:GetIsAlive()`, and GetIsBuilt is
        a ConstructMixin method. ARC:OnCreate never inits that mixin (vanilla ARC.lua) because an ARC
        is MANUFACTURED by the Robotics Factory and arrives complete - there is no such thing as a
        half-built ARC, so there was never anything for the check to mean.

        Calling it therefore threw "attempt to call method 'GetIsBuilt' (a nil value)" from
        GetShouldAutoDeploy, EVERY FRAME, because GetCanSleep and OnUpdate both reach this function.
        An error raised inside the server's entity update loop stops the entities after it from being
        updated that tick, so the visible symptom was not an ARC problem at all: bots froze in place -
        in mid-air if they happened to be jumping - and stopped responding to orders.

        GetIsAlive comes from LiveMixin, which an ARC does have, and is the check that was actually
        wanted here.
    ]]
    if not self:GetIsAlive() then
        return false
    end

    -- Only when there is nobody who COULD deploy it. With a commander present the button is theirs,
    -- and auto-deploying would override a deliberate decision to keep the ARC mobile.
    local team = self:GetTeam()
    return team ~= nil and team.GetCommander ~= nil and team:GetCommander() == nil
end

-- A DEPLOYED ARC MUST NEVER SLEEP, and neither must one that is waiting to auto-deploy.
--
-- Vanilla ARC:GetCanSleep() is `self.mode == ARC.kMode.Stationary`, and ARC:AcquireTarget() sets
-- exactly that mode whenever it fails to find a target. So a deployed ARC with nothing to shoot
-- becomes eligible to sleep, and sleeping stops OnUpdate - which is the ONLY caller of UpdateOrders,
-- which is the only caller of AcquireTarget. The ARC therefore loses the ability to notice that a
-- target has arrived, and nothing in its own code can ever wake it again: SleeperMixin only re-wakes
-- an entity whose GetCanSleep() has turned false, and this one's cannot change while it is asleep.
--
-- In a normal round that deadlock is invisible, because a commander is forever selecting, moving and
-- manually target-ordering ARCs, and each of those interactions wakes it.
--
-- The auto-deploy term matters for the same reason in reverse: SleeperMixin re-checks GetCanSleep on
-- sleeping entities, so an ARC that fell asleep undeployed wakes by itself the moment the commander
-- leaves the chair, runs OnUpdate, and deploys.
function ARC:GetCanSleep()
    return self.mode == ARC.kMode.Stationary
           and not self:GetInAttackMode()
           and not GetShouldAutoDeploy(self)
end

-- Killfeed / kill credit.
--
-- TeamDeathMessageMixin:GetDeathMessage resolves a non-player killer via `killer:GetOwner()` - if
-- that returns a Player the kill is credited to them, otherwise it falls back to the killer's own
-- techId ("ARC" in the feed).
--
-- ARC DOES already have an owner: ScriptActor InitMixins OwnerMixin, and
-- RoboticsFactory:ManufactureEntity sets it to whoever ordered the ARC. So this must EXTEND that,
-- never replace it - an earlier version of this override returned the commander unconditionally and
-- silently discarded the real owner, which would have broken every other consumer of GetOwner.
--
-- Order of preference: the genuine owner if it is still a valid Player (vanilla behaviour, fully
-- preserved), then whoever is or was last in the command chair, then nil so the ARC itself is shown.
local baseARCGetOwner = ARC.GetOwner

function ARC:GetOwner()

    local owner = baseARCGetOwner and baseARCGetOwner(self)
    if owner and owner.isa and owner:isa("Player") then
        return owner
    end

    local team = self:GetTeam()
    if not team then
        return nil
    end

    local commander = team.GetCommander and team:GetCommander()
    if commander then
        return commander
    end

    if team.GetLastCommander then
        return team:GetLastCommander()
    end

    return nil
end

function ARC:GetCanFireAtTargetActual(target, targetPoint, manuallyTargeted)

    if not target.GetReceivesStructuralDamage or not target:GetReceivesStructuralDamage() then
        return false
    end

    -- don't target eggs (they take only splash damage)
    -- Hydra exclusion has to due with people using them to prevent ARC shooting Hive. 
    if target:isa("Egg") or target:isa("Cyst") then -- or target:isa("Contamination") then
        return false
    end

    if not manuallyTargeted and (target:isa("Hydra") or target:isa("SporeMine"))then
        return false
    end

    if target.GetIsSighted then
        if not target:GetIsSighted() and not GetIsTargetDetected(target) then
            return false
        end
    end

    local distToTarget = (target:GetOrigin() - self:GetOrigin()):GetLengthXZ()
    if (distToTarget > ARC.kFireRange) or (distToTarget < ARC.kMinFireRange) then
        return false
    end
    
    return true

end

if Server then

    -- Runs every frame the ARC is awake; GetCanSleep above guarantees it IS awake whenever a deploy
    -- is owed, so this cannot be starved by the sleep system.
    local baseOnUpdate = ARC.OnUpdate
    function ARC:OnUpdate(deltaTime)

        baseOnUpdate(self, deltaTime)

        if GetShouldAutoDeploy(self) then
            self:Deploy()
        end

    end

    local basePerformAttack = ARC.PerformAttack
    function ARC:PerformAttack()
        basePerformAttack(self)


        local team = self:GetTeam()
        if team then
            team:OnDeadlockExtend(kTechId.ARCDeploy)
        end
    end
    
end 