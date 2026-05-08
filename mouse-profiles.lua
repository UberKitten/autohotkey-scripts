-- mouse-profiles.lua — Hammerspoon port of mouse-profiles.ahk.
--
-- Mirrors the desktop profile only: hold a side button to scroll, tick the
-- wheel in the same direction to bump speed level. Opposite-direction wheel
-- ticks pass through normally. Scroll loop bails when the focused window
-- changes (alt-tab, click into another app), the same alt-tab safety the
-- AHK version has.
--
-- Install (one of):
--   1. Symlink as your Hammerspoon entry point if this is your only config:
--        ln -s ~/path/to/autohotkey-scripts/mouse-profiles.lua \
--              ~/.hammerspoon/init.lua
--   2. Or load from your existing ~/.hammerspoon/init.lua:
--        mouseProfiles = dofile(os.getenv("HOME")
--          .. "/path/to/autohotkey-scripts/mouse-profiles.lua")
--      (Assign to a variable so Hammerspoon doesn't GC the eventtaps.)
--
-- Then grant Hammerspoon Accessibility permission:
--   System Settings → Privacy & Security → Accessibility → enable Hammerspoon.

local M = {}

-- macOS mouse-button numbering (zero-indexed). 3/4 are the standard side
-- buttons on most multi-button mice (Razer, Logitech, etc.):
--   3 = "Back"    / XB1 in Windows → bound to scroll DOWN
--   4 = "Forward" / XB2 in Windows → bound to scroll UP
local BTN_DOWN = 3
local BTN_UP   = 4

-- Per-level cadence. L0 has a slightly slower interval; from L1 onward we
-- run at the timer floor and grow chunk by 1 per level. No cap — gotta go
-- fast — though apps will eventually saturate.
local L0_INTERVAL_SEC = 0.020   -- ~50 lines/sec at L0
local FAST_INTERVAL_SEC = 0.015 -- L1+: ~67 * lvl lines/sec
local function levelParams(lvl)
    if lvl == 0 then return L0_INTERVAL_SEC, 1 end
    return FAST_INTERVAL_SEC, lvl
end

local TICKS_PER_LEVEL = 3       -- wheel ticks needed to advance one level
local RESTORE_WINDOW_SEC = 3.0  -- press within this window keeps the level
                                -- (any direction)

-- Hammerspoon delivers scroll events we post back through this same eventtap.
-- Mark synthetic ticks so wheelTap passes them through; otherwise they look
-- like real same-direction wheel ticks and get consumed by the bump counter.
local SYNTHETIC_SCROLL_MARKER = 7331

-- runtime state. heldButtons tracks every physically-pressed scroll button;
-- heldButton is the one currently driving the scroll loop (most-recent press
-- still held). Lets the user chord XB1/XB2 to swap directions on the fly.
local heldButtons      = {}   -- {[3]=true, [4]=true}; missing/nil = released
local heldButton       = nil  -- active button (3, 4, or nil)
local heldDirection    = 0    -- -1 (down) or +1 (up), 0 when idle
local bumpLevel        = 0
local bumpTicks        = 0
local scrollTimer      = nil
local initialWindowId  = nil
local lastReleaseTime  = 0    -- hs.timer.secondsSinceEpoch() of last release

local props = hs.eventtap.event.properties
local types = hs.eventtap.event.types

local function focusedWindowId()
    local w = hs.window.focusedWindow()
    return w and w:id() or nil
end

local function postScroll(direction, lines)
    -- newScrollEvent({x, y}, modifiers, unit). y > 0 = up, y < 0 = down.
    hs.eventtap.event
        .newScrollEvent({0, direction * lines}, {}, "line")
        :setProperty(props.eventSourceUserData, SYNTHETIC_SCROLL_MARKER)
        :post()
end

local function stopScroll()
    if scrollTimer then
        scrollTimer:stop()
        scrollTimer = nil
    end
    -- Record release for the restore-window check on next press. Don't
    -- reset bumpLevel/bumpTicks — they're remembered.
    if heldButton ~= nil then
        lastReleaseTime = hs.timer.secondsSinceEpoch()
    end
    heldButton      = nil
    heldDirection   = 0
    initialWindowId = nil
end

local function scrollTick()
    if focusedWindowId() ~= initialWindowId then
        stopScroll()
        return
    end
    local interval, chunk = levelParams(bumpLevel)
    postScroll(heldDirection, chunk)
    scrollTimer = hs.timer.doAfter(interval, scrollTick)
end

local function directionFor(button)
    return (button == BTN_DOWN) and -1 or 1
end

local function startScroll(button)
    if scrollTimer then
        scrollTimer:stop()
        scrollTimer = nil
    end
    -- Mid-session swap (other button was already held) keeps the level —
    -- only fresh starts (idle) check the restore window.
    if heldButton == nil
            and (hs.timer.secondsSinceEpoch() - lastReleaseTime) >= RESTORE_WINDOW_SEC then
        bumpLevel = 0
        bumpTicks = 0
    end
    heldButton      = button
    heldDirection   = directionFor(button)
    initialWindowId = focusedWindowId()
    scrollTick()
end

-- Side-button down/up. We suppress (return true) so the OS doesn't fire the
-- button's default action (Back/Forward in browsers, etc.).
M.buttonTap = hs.eventtap.new(
    {types.otherMouseDown, types.otherMouseUp},
    function(e)
        local btn = e:getProperty(props.mouseEventButtonNumber)
        if btn ~= BTN_DOWN and btn ~= BTN_UP then return false end

        if e:getType() == types.otherMouseDown then
            heldButtons[btn] = true
            -- New press always becomes the active driver (preempting the
            -- other if it was running).
            if heldButton ~= btn then
                startScroll(btn)
            end
        else  -- otherMouseUp
            heldButtons[btn] = nil
            if heldButton == btn then
                -- Active button released — fall back to the other if it's
                -- still held; otherwise stop.
                local fallback = nil
                for b, v in pairs(heldButtons) do
                    if v then fallback = b; break end
                end
                if fallback then
                    startScroll(fallback)
                else
                    stopScroll()
                end
            end
        end
        return true
    end
)

-- Wheel intercept: while a scroll button is held, same-direction wheel
-- ticks bump the level up, opposite-direction bump it down (floored at
-- L0). Wheel input is consumed in both cases. Trackpad / continuous-
-- scroll events always pass through (no wheel detents to count).
M.wheelTap = hs.eventtap.new(
    {types.scrollWheel},
    function(e)
        if e:getProperty(props.eventSourceUserData) == SYNTHETIC_SCROLL_MARKER then
            return false
        end
        if e:getProperty(props.scrollWheelEventIsContinuous) ~= 0 then
            return false
        end
        if heldButton == nil then return false end

        local dy = e:getProperty(props.scrollWheelEventDeltaAxis1)
        if dy == 0 then return false end
        local wheelDirection = (dy > 0) and 1 or -1
        local delta = (wheelDirection == heldDirection) and 1 or -1
        bumpTicks = bumpTicks + delta

        if bumpTicks >= TICKS_PER_LEVEL then
            bumpLevel = bumpLevel + 1
            bumpTicks = 0
        elseif bumpTicks <= -TICKS_PER_LEVEL then
            if bumpLevel > 0 then bumpLevel = bumpLevel - 1 end
            bumpTicks = 0
        end
        return true  -- suppress: this tick was consumed by the bump counter
    end
)

function M.start()
    M.buttonTap:start()
    M.wheelTap:start()
end

function M.stop()
    M.buttonTap:stop()
    M.wheelTap:stop()
    stopScroll()
end

M.start()
return M
