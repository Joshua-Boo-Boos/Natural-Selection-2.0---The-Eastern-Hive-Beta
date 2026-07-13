-- Server frame-time sampler + "perfdiag" console command.
-- Ring buffer of the last ~30s of server frame deltas; prints avg/worst
-- frame time, entity count and Lua heap size. Costs one clock read and two
-- table writes per tick.
if Server then

    local kMaxSamples = 900
    local samples = {}
    local sampleIndex = 1
    local lastTime

    local function PerfDiagSample()
        local now = Shared.GetSystemTimeReal()
        if lastTime then
            samples[sampleIndex] = now - lastTime
            sampleIndex = sampleIndex % kMaxSamples + 1
        end
        lastTime = now
    end
    Event.Hook("UpdateServer", PerfDiagSample)

    local function OnConsolePerfDiag(client)

        -- Server console always allowed; remote clients need cheats/tests.
        if client and not Shared.GetCheatsEnabled() and not Shared.GetTestsEnabled() then
            return
        end

        local count, total, worst = 0, 0, 0
        for i = 1, kMaxSamples do
            local dt = samples[i]
            if dt then
                count = count + 1
                total = total + dt
                if dt > worst then worst = dt end
            end
        end

        if count == 0 then
            Shared.Message("perfdiag: no samples yet")
            return
        end

        local avg = total / count
        Shared.Message(string.format(
            "perfdiag: avg frame %.2f ms (%.1f fps) | worst %.2f ms | entities %d | lua heap %.1f MB | samples %d",
            avg * 1000, 1 / avg, worst * 1000,
            Shared.GetEntitiesWithClassname("Entity"):GetSize(),
            collectgarbage("count") / 1024, count))

    end
    Event.Hook("Console_perfdiag", OnConsolePerfDiag)

end
