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

-- Per-level cadence. Index = bumpLevel + 1; values are
-- {intervalSeconds, lines}. L0 was bumped 3x faster than the original
-- AHK-ish baseline; later levels stay monotonic so wheel bumps still
-- accelerate instead of accidentally slowing the scroll.
local LEVELS = {
    {0.020, 1},  -- L0: ~50 lines/sec
    {0.015, 1},  -- L1: ~67 lines/sec  (close to timer floor)
    {0.015, 2},  -- L2: ~133 lines/sec
    {0.015, 3},  -- L3: ~200 lines/sec
}
local MAX_LEVEL = #LEVELS - 1
local TICKS_PER_LEVEL = 3       -- wheel ticks needed to advance one level
local RESTORE_WINDOW_SEC = 2.0  -- re-pressing same button within this keeps level

-- Hammerspoon delivers scroll events we post back through this same eventtap.
-- Mark synthetic ticks so wheelTap passes them through; otherwise they look
-- like real same-direction wheel ticks and get consumed by the bump counter.
local SYNTHETIC_SCROLL_MARKER = 7331

-- runtime state
local heldButton       = nil  -- 3, 4, or nil
local heldDirection    = 0    -- -1 (down) or +1 (up), 0 when idle
local bumpLevel        = 0
local bumpTicks        = 0
local scrollTimer      = nil
local initialWindowId  = nil
local lastReleaseTime  = 0    -- hs.timer.secondsSinceEpoch() of last release
local lastReleaseBtn   = nil  -- which button was last released

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
        lastReleaseBtn  = heldButton
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
    local lvl = LEVELS[bumpLevel + 1]
    postScroll(heldDirection, lvl[2])
    scrollTimer = hs.timer.doAfter(lvl[1], scrollTick)
end

local function startScroll(button, direction)
    if scrollTimer then
        scrollTimer:stop()
        scrollTimer = nil
    end
    -- Restore prior level if re-pressing the same button within the window;
    -- otherwise start fresh at L0.
    local now = hs.timer.secondsSinceEpoch()
    if button ~= lastReleaseBtn or (now - lastReleaseTime) >= RESTORE_WINDOW_SEC then
        bumpLevel = 0
        bumpTicks = 0
    end
    heldButton      = button
    heldDirection   = direction
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
        local direction = (btn == BTN_DOWN) and -1 or 1

        if e:getType() == types.otherMouseDown then
            startScroll(btn, direction)
        elseif heldButton == btn then
            stopScroll()
        end
        return true
    end
)

-- Wheel intercept: bump level if same direction as held button, passthrough
-- otherwise. Trackpad / continuous-scroll events always pass through (no
-- wheel detents to count).
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
        if wheelDirection ~= heldDirection then return false end

        if bumpLevel < MAX_LEVEL then
            bumpTicks = bumpTicks + 1
            if bumpTicks >= TICKS_PER_LEVEL then
                bumpLevel = bumpLevel + 1
                bumpTicks = 0
            end
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
