-- CNPerf: pure performance module. NO gameplay changes live here.
-- Each hooked file is loaded ONCE per SetupFileHook line; never hook the
-- same Perf file onto two targets (it would double-wrap functions).

-- Server frame-time diagnostics ("perfdiag" console command).
ModLoader.SetupFileHook("lua/Shared.lua", "lua/Perf/PerfDiag.lua", "post")

-- Skip TeamBrain memory bookkeeping while #gServerBots == 0.
ModLoader.SetupFileHook("lua/bots/BotUtils.lua", "lua/Perf/BotPerf.lua", "post")

-- Allocation-free GetBulletTargets (identical hit results).
ModLoader.SetupFileHook("lua/NS2Utility.lua", "lua/Perf/BulletTargetsPerf.lua", "post")

-- Allocation-free AttackMeleeCapsule (identical hit results). Hoists the
-- EntityFilterList/traceFilter closures out of the per-swing trace loop.
ModLoader.SetupFileHook("lua/NS2Utility.lua", "lua/Perf/MeleeTargetsPerf.lua", "post")

-- REVERTED: structure SetUpdates rate clamps (Whip/ARC/Armory/PrototypeLab/
-- Drifter/MAC). BaseModelMixin's UpdateAnimationState (core/lua/Mixins/
-- BaseModelMixin.lua:205-213) advances the animation graph by exactly one
-- native-tick span (Shared.GetPreviousTime()..Shared.GetTime(), a global
-- engine clock) every time OnUpdate fires - it does NOT scale by however
-- many ticks were skipped. Throttling SetUpdates therefore doesn't delay
-- tag-driven gameplay events (ARC fire_start, Whip slap, etc.) - it plays
-- their animation graphs in slow motion, since fewer OnUpdate calls means
-- fewer one-tick advances per unit of real time. Confirmed at the reported
-- tick rate of 21 (0.0476s/tick): a 0.05s clamp needs ceil(0.05/0.0476)=2
-- ticks to fire, halving the graph's effective playback rate - and the
-- same quantization even happens at the original 30Hz design baseline
-- (ceil(0.05/0.0333)=2, i.e. ~15Hz delivered instead of the intended 20Hz).
-- Reverted rather than fixed: these six structures are few enough per
-- server that the CPU saving was never worth this class of risk.
