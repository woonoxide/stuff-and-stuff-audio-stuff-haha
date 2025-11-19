-- undertale-style blip + drums + voice (clientside)
-- plays positional letter blips, cycles drums from your head and plays voice.mp3
-- fixed: uses raw.githubusercontent.com urls, safer attachment lookup, robust segment split

if SERVER then return end

local letterDelay = 0.06

local skipChars = {
    [" "] = true,
    ["!"] = true,
    ["-"] = true,
    ["."] = true,
}

-- undertale-style blip sounds (kept unchanged)
local blipSounds = {
    "garrysmod/balloon_pop_cute.wav"
}

-- base raw url for your repo files
local base_raw = "https://raw.githubusercontent.com/woonoxide/stuff-and-stuff-audio-stuff-haha/main/"

-- drums sequence filenames (will be requested from raw github)
local drumOrder = {
    base_raw .. "Tambor_1.mp3",
    base_raw .. "Tambor_2.mp3",
    base_raw .. "Tambor_3.mp3"
}
local drumIndex = 1

-- voice file (play once at message start)
local voiceURL = base_raw .. "voice.mp3"

-- helper: get a good position near player's head (fallback to eye pos)
local function GetPlayerHeadPos(ply)
    if not IsValid(ply) then return vector_origin end

    local attachId = ply:LookupAttachment("eyes") or ply:LookupAttachment("anim_attachment_head") or 0

    if attachId and attachId > 0 then
        local att = ply:GetAttachment(attachId)
        if att and att.Pos then
            return att.Pos
        end
    end

    -- fallback
    if ply.EyePos then
        return ply:EyePos()
    end

    return ply:GetPos()
end

-- play a blip sound pos-audio at player's head
local function PlayBlipAtPlayer(ply)
    if not IsValid(ply) then return end

    local pos = GetPlayerHeadPos(ply)

    -- sound.Play will do positional playback on client
    sound.Play(table.Random(blipSounds), pos, 75, 100, 1)
end

-- play single drum (url) at player's head
local function PlaySingleDrumAtPlayer(ply, url)
    if not IsValid(ply) then return end

    local pos = GetPlayerHeadPos(ply)

    -- use sound.PlayURL with "3d" to get a pos-audio channel
    sound.PlayURL(url, "3d", function(ch)
        if not IsValid(ch) then return end

        -- some implementations return object with :SetPos
        if ch.SetPos then
            ch:SetPos(pos)
        end

        -- ensure it's audible and play
        if ch.SetVolume then ch:SetVolume(1) end
        if ch.SetPlaybackRate then ch:SetPlaybackRate(1) end

        -- play if available
        if ch.Play then
            ch:Play()
        end
    end)
end

-- cycles and plays the next drum in order
local function PlayDrumAtPlayer(ply)
    if not IsValid(ply) then return end

    local snd = drumOrder[drumIndex] or drumOrder[1]

    drumIndex = drumIndex + 1
    if drumIndex > #drumOrder then
        drumIndex = 1
    end

    PlaySingleDrumAtPlayer(ply, snd)
end

-- play voice.mp3 once at player's head (non-blocking)
local function PlayVoiceAtPlayer(ply)
    if not IsValid(ply) then return end

    local pos = GetPlayerHeadPos(ply)

    sound.PlayURL(voiceURL, "3d", function(ch)
        if not IsValid(ch) then return end

        if ch.SetPos then ch:SetPos(pos) end
        if ch.SetVolume then ch:SetVolume(1) end
        if ch.SetPlaybackRate then ch:SetPlaybackRate(1) end
        if ch.Play then ch:Play() end
    end)
end

-- split text into segments: text parts and "*drums*" tokens
local function SplitSegments(text)
    local segments = {}
    if not text or text == "" then return segments end

    local pattern = "(.-)(%*drums%*)"
    local last = 1
    local s, e, before, token = text:find(pattern, 1)
    while s do
        before = text:sub(last, s - 1)
        if before ~= "" then table.insert(segments, before) end
        table.insert(segments, "*drums*")
        last = e + 1
        s, e = text:find(pattern, last)
    end

    local tail = text:sub(last)
    if tail ~= "" then table.insert(segments, tail) end

    return segments
end

-- play undertale blips for a text segment, returns total time used
local function PlayUTVoiceSegment(segment, ply, startDelay)
    local t = startDelay or 0
    for i = 1, #segment do
        local ch = segment:sub(i, i)
        if not skipChars[ch] then
            timer.Simple(t, function()
                -- safety: ensure ply still valid
                if not IsValid(ply) then return end
                PlayBlipAtPlayer(ply)
            end)
        end
        t = t + letterDelay
    end
    return t
end

-- play drum sequence (the full drumSounds cycle) starting at delay, returns end delay
local function PlayDrumsSequence(startDelay)
    local t = startDelay or 0
    -- play 3 drums in quick sequence (using PlaySingleDrumAtPlayer won't schedule SetPos update exactly at time,
    -- but that's acceptable - each drum is played with PlaySingleDrumAtPlayer from the caller)
    for i = 1, #drumOrder do
        timer.Simple(t, function()
            -- the caller will call PlaySingleDrumAtPlayer with correct ply - but we want just url here
            -- to keep positional we expect caller to wrap this; so here we just advance time and return
        end)
        t = t + 0.15
    end
    return t
end

-- main hook: clientside OnPlayerChat
hook.Add("OnPlayerChat", "UTVoiceChatClient", function(ply, text, teamOnly, isDead)
    if not IsValid(ply) then return end
    if type(text) ~= "string" then return end

    -- split into segments
    local segments = SplitSegments(text)

    -- play voice once at start (user requested voice.mp3 used as "voice")
    PlayVoiceAtPlayer(ply)

    -- process segments with scheduling
    local delay = 0
    for _, seg in ipairs(segments) do
        if seg == "*drums*" then
            -- schedule drum sequence: we will play each drum at the player's head with timed timers
            for i = 1, #drumOrder do
                timer.Simple(delay + (i - 1) * 0.15, function()
                    if not IsValid(ply) then return end
                    PlaySingleDrumAtPlayer(ply, drumOrder[i])
                end)
            end
            delay = delay + (#drumOrder * 0.15)
        else
            -- schedule blip letters for this text segment
            for i = 1, #seg do
                local ch = seg:sub(i, i)
                if not skipChars[ch] then
                    timer.Simple(delay + (i - 1) * letterDelay, function()
                        if not IsValid(ply) then return end
                        PlayBlipAtPlayer(ply)
                    end)
                end
            end
            delay = delay + (#seg * letterDelay)
        end
    end
end)
