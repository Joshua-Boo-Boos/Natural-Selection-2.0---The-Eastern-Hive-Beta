local kMaxRotateSpeed = 1.0
local kTooFastRotateSpeed = 0.7
local kSlowRotateSpeed = 0.5

local kSafeAimStateToRotateSpeeds =
{
    [kAimDebuffState.None] = kMaxRotateSpeed,
    [kAimDebuffState.TooFast] = kTooFastRotateSpeed,
    [kAimDebuffState.UpHigh] = kSlowRotateSpeed,
}

function BotMotion:GetRotateSpeed()

    if not self.bot then return kMaxRotateSpeed end
    if not self.bot.aim then return kMaxRotateSpeed end

    local aimTurnRate = self.bot.aim.GetAimTurnRateModifier and self.bot.aim:GetAimTurnRateModifier() or 1.0
    local aimDebuffState = self.bot.aim.GetAimDebuffState and self.bot.aim:GetAimDebuffState() or kAimDebuffState.None

    return aimTurnRate * (kSafeAimStateToRotateSpeeds[aimDebuffState] or kMaxRotateSpeed)

end
