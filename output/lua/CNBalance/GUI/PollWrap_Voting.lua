--[[
    POLL LINE WRAPPING - part 1 of 2 (post hook on lua/Voting.lua; part 2 is PollWrap_VoteMenu.lua).

    A poll's question is wrapped onto lines of at most kPollWrapLineLength characters, so long polls become a tall, narrow
    block instead of a box across the screen. Lines break between words; a word too long for a line of its own is split,
    with a '-' at the end of the first part.

    WHICH VOTES ARE POLLS is decided by the vote TYPE, not by its text: Shine's poll (TEHSF basecommands, sh_customvote)
    starts a "ShineCustomVote", whatever prefix the server puts in front of the question. Add other poll vote types to
    kPollWrapVoteTypes. Every other vote (kick, map, Combat Enhancer, ...) is untouched.

    Client only: no server code, no network changes. Shared by several mods (NS2.0-TEH, Siege2.0-TEH, Defense2.0-TEH,
    Combat Enhancer); the global guard makes sure it is only installed once when more than one of them is loaded.
]]

if not Client or gPollWrapVotingInstalled or type(AddVoteStartListener) ~= "function" then return end
gPollWrapVotingInstalled = true

kPollWrapLineLength = kPollWrapLineLength or 40
kPollWrapVoteTypes = kPollWrapVoteTypes or { ShineCustomVote = true }

-- Wrapped poll texts, so the vote menu knows which titles to lay out over several lines.
gPollWrapTexts = gPollWrapTexts or {}

function PollWrap_WrapText(text)

    if type(text) ~= "string" then return text end

    local maxLen = kPollWrapLineLength
    local lines = {}
    local current = ""

    for word in string.gmatch(text, "%S+") do

        local rest = word
        while #rest > 0 do

            if current == "" then

                if #rest <= maxLen then
                    current = rest
                    rest = ""
                else
                    -- A word longer than a whole line: split it, '-' at the end of the first part.
                    table.insert(lines, string.sub(rest, 1, maxLen - 1) .. "-")
                    rest = string.sub(rest, maxLen)
                end

            elseif #current + 1 + #rest <= maxLen then

                current = current .. " " .. rest
                rest = ""

            elseif #rest <= maxLen then

                -- Fits on a line of its own: start a new line rather than splitting it.
                table.insert(lines, current)
                current = ""

            else

                -- A word longer than a line: use the space left on this line (at least 2 letters and the '-').
                local room = maxLen - #current - 1
                if room >= 3 then
                    table.insert(lines, current .. " " .. string.sub(rest, 1, room - 1) .. "-")
                    rest = string.sub(rest, room)
                else
                    table.insert(lines, current)
                end
                current = ""

            end

        end

    end

    if current ~= "" then
        table.insert(lines, current)
    end

    return table.concat(lines, "\n")

end

local oldAddVoteStartListener = AddVoteStartListener

function AddVoteStartListener(voteName, queryTextGenerator, ...)

    if kPollWrapVoteTypes[voteName] and type(queryTextGenerator) == "function" then

        local generator = queryTextGenerator
        queryTextGenerator = function(data)
            local text = generator(data)
            local ok, wrapped = pcall(PollWrap_WrapText, text)
            if ok and type(wrapped) == "string" then
                gPollWrapTexts[wrapped] = true
                return wrapped
            end
            return text
        end

    end

    return oldAddVoteStartListener(voteName, queryTextGenerator, ...)

end
