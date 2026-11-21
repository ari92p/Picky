-- Picky / Pick.lua : right-click picking (inventory + trade window)
local ADDON, LP = ...
local L = LP.L

-- 1) Detect "locked" ------------------------------------------------------------
local LOCKED_SET = { ["locked"] = true, ["verschlossen"] = true, ["abgeschlossen"] = true }
local function IsTextLocked(t)
    if not t then return false end
    if _G.LOCKED and t == _G.LOCKED then return true end
    return LOCKED_SET[t:lower()] == true
end
LP.IsLockedText = IsTextLocked

local function DataLocked(data)
    if not data or not data.lines then return false end
    for _, line in ipairs(data.lines) do
        if IsTextLocked(line.leftText) then return true end
    end
    return false
end

local function ContainerItemID(bag, slot)
    if C_Container and C_Container.GetContainerItemID then return C_Container.GetContainerItemID(bag, slot) end
    return GetContainerItemID(bag, slot)
end

local scan = CreateFrame("GameTooltip", "PickyScanTip", nil, "GameTooltipTemplate")

-- Is exactly THIS box (bag/slot) currently locked? The state belongs to the individual item,
-- not to the item ID: a picked box no longer shows "Locked" and must be opened normally.
local function SlotLocked(bag, slot)
    if C_TooltipInfo and C_TooltipInfo.GetBagItem then
        local data = C_TooltipInfo.GetBagItem(bag, slot)
        if not data then return nil end
        return DataLocked(data)
    end
    scan:SetOwner(UIParent, "ANCHOR_NONE")
    scan:SetBagItem(bag, slot)
    local locked = false
    for i = 2, scan:NumLines() do
        local fs = _G["PickyScanTipTextLeft" .. i]
        if fs and IsTextLocked(fs:GetText()) then locked = true end
    end
    scan:Hide()
    return locked
end

-- Boxes just picked: the client needs a moment until the tooltip no longer shows "Locked".
-- During this grace period the slot counts as open, so "Pick Lock" is never cast again on an open box.
local recentPick = {}
local PICK_GRACE = 3
function LP.MarkPicked(bag, slot)
    recentPick[bag .. ":" .. slot] = GetTime()
end
function LP.RecentlyPicked(bag, slot)
    local t = recentPick[bag .. ":" .. slot]
    return t ~= nil and (GetTime() - t) < PICK_GRACE
end

local lockableID = {}      -- item IDs that have shown "Locked" at least once
local notLockableUntil = {} -- unknown items without a lock: do not check again for 30 seconds
function LP.IsLockedItem(bag, slot)
    local id = ContainerItemID(bag, slot)
    if not id then return false end
    if LP.RecentlyPicked(bag, slot) then return false end   -- just picked: counts as open (see above)
    local box = LP.BOXES[id]
    local req = box and box[1]
    if not box and not lockableID[id] then
        local untilT = notLockableUntil[id]
        if untilT and GetTime() < untilT then return false end
    end
    local locked = SlotLocked(bag, slot)
    if locked == nil then return false end
    if locked then
        lockableID[id] = true
        notLockableUntil[id] = nil
        return true, req
    end
    if not box and not lockableID[id] then notLockableUntil[id] = GetTime() + 30 end
    return false
end

local function TradeSlotLocked()
    if not GetTradeTargetItemLink or not GetTradeTargetItemLink(7) then return false end
    if LP.tradePickedAt and (GetTime() - LP.tradePickedAt) < PICK_GRACE then return false end   -- eben geknackt
    if C_TooltipInfo and C_TooltipInfo.GetTradeTargetItem then
        return DataLocked(C_TooltipInfo.GetTradeTargetItem(7))
    end
    scan:SetOwner(UIParent, "ANCHOR_NONE")
    scan:SetTradeTargetItem(7)
    local locked = false
    for i = 2, scan:NumLines() do
        local fs = _G["PickyScanTipTextLeft" .. i]
        if fs and IsTextLocked(fs:GetText()) then locked = true end
    end
    scan:Hide()
    return locked
end

-- 2) Click area: right-click on the box = pick ----------------------------------------------
-- Secure buttons must not be changed in combat -> only outside combat.
local overlay = CreateFrame("Button", "PickyOverlay", UIParent, "SecureActionButtonTemplate")
overlay:RegisterForClicks("RightButtonUp", "RightButtonDown")   -- trigger depends on client setting (down/up)
overlay:SetFrameStrata("DIALOG")
overlay:EnableMouse(true)
overlay:Hide()

-- Remember WHAT was last picked via right-click (for the grace period after success)
overlay:HookScript("PreClick", function(self, button)
    if button == "RightButton" then
        LP.lastPickTarget = { bag = self.bag, slot = self.slot, trade = self.isTrade, t = GetTime() }
        LP.DevDebug("pick", "right-click pick started on %s", self.isTrade and "trade slot" or ("bag " .. tostring(self.bag) .. " slot " .. tostring(self.slot)))
    end
end)

local function HideOverlay()
    if not InCombatLockdown() and overlay:IsShown() then overlay:Hide() end
end

local function GetMouseFocusCompat()
    if GetMouseFoci then
        local f = GetMouseFoci()
        return f and f[1]
    end
    return GetMouseFocus and GetMouseFocus()
end

local function GetBagAndSlot(frame)
    if not frame then return nil, nil end
    local bag, slot
    local via = "api"   -- where we got the bag slot from: "api" = the button tells us itself, "parent" = guessed via the parent frame
    if type(frame.GetBagID) == "function" then
        bag = frame:GetBagID()
    elseif frame.bag then
        bag = frame.bag
    elseif frame.bagID then
        bag = frame.bagID
    elseif frame.GetParent and frame:GetParent() and frame:GetParent().GetID then
        bag = frame:GetParent():GetID()
        via = "parent"
    end
    if type(frame.GetID) == "function" then slot = frame:GetID() end
    if type(bag) == "number" and type(slot) == "number" and slot > 0 then return bag, slot, via end
    return nil, nil
end

-- Safety for the guessed bag slot (parent ID): if the tooltip shows a DIFFERENT item than the one in this slot,
-- it is a foreign window (action bar, chat link ...) and gets no click area. If unsure, it is not rejected.
local function TooltipItemMismatch(bag, slot)
    local want = ContainerItemID(bag, slot)
    if not want then return true end
    local ok, _, link = pcall(GameTooltip.GetItem, GameTooltip)
    local have = ok and type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    return have ~= nil and have ~= want
end

local function CheckOverlayRaw(focus)
    if InCombatLockdown() or not LP.db or not LP.IsRogue() then return end
    if not focus or not focus:IsVisible() then HideOverlay() return end
    if focus == overlay or (focus.GetParent and focus:GetParent() == overlay) then return end
    if IsShiftKeyDown() then HideOverlay() return end   -- Shift held = move the box normally

    -- Trade window, slot 7 ("Wird nicht getauscht" / "Will not be traded")
    -- Foreign frames sometimes return no text from GetName() (e.g. the damage meter): only use strings
    local function SafeName(f)
        if not f or type(f.GetName) ~= "function" then return "" end
        local ok, n = pcall(f.GetName, f)
        return (ok and type(n) == "string") and n or ""
    end
    local fname = SafeName(focus)
    local parent = type(focus.GetParent) == "function" and focus:GetParent() or nil
    local pname = SafeName(parent)
    if fname:find("TradeRecipientItem7") or pname:find("TradeRecipientItem7") then
        if TradeSlotLocked() then
            if overlay:IsShown() and overlay.isTrade and overlay:GetParent() == focus then return end   -- already there, do not set anything again
            overlay.isTrade, overlay.bag, overlay.slot = true, nil, nil
            overlay:SetParent(focus)
            overlay:ClearAllPoints()
            overlay:SetAllPoints(focus)
            overlay:SetFrameLevel(focus:GetFrameLevel() + 5)
            overlay:SetAttribute("type", "macro")
            overlay:SetAttribute("macrotext", "/cast " .. LP.PickName() .. "\n/run ClickTargetTradeButton(7)")
            overlay:SetAttribute("spell", nil)
            overlay:SetAttribute("target-bag", nil)
            overlay:SetAttribute("target-slot", nil)
            overlay:Show()
            LP.DevDebug("pick", "click area on the trade slot (item is locked)")
            return
        end
    end

    -- Inventar
    local bag, slot, via = GetBagAndSlot(focus)
    if bag and slot and via == "parent" and TooltipItemMismatch(bag, slot) then
        -- this fires for every item tooltip of foreign frames: log each guessed slot only once in a row
        local key = bag .. ":" .. slot
        if key ~= LP.lastForeignKey then
            LP.lastForeignKey = key
            LP.DevDebug("pick", "ignored a foreign frame (guessed bag %d slot %d, tooltip shows another item)", bag, slot)
        end
        HideOverlay()
        return
    end
    if bag and slot then
        local locked, req = LP.IsLockedItem(bag, slot)
        if locked then
            local ok = (not req) or LP.skillEstimated or LP.Skill() >= req
            if ok then
                if overlay:IsShown() and overlay.bag == bag and overlay.slot == slot and overlay:GetParent() == focus then return end   -- already there
                overlay.isTrade, overlay.bag, overlay.slot = nil, bag, slot
                overlay:SetParent(focus)
                overlay:ClearAllPoints()
                overlay:SetAllPoints(focus)
                overlay:SetFrameLevel(focus:GetFrameLevel() + 5)
                overlay:SetAttribute("type", "spell")
                overlay:SetAttribute("spell", LP.PickName())
                overlay:SetAttribute("target-bag", bag)
                overlay:SetAttribute("target-slot", slot)
                overlay:SetAttribute("macrotext", nil)
                overlay:Show()
                LP.DevDebug("pick", "click area on bag %d slot %d (needs %s, skill %d)", bag, slot, req, LP.Skill())
                return
            else
                LP.Debug("pick", "bag %d slot %d is locked but your skill is too low (needs %s, skill %d)", bag, slot, req, LP.Skill())
            end
        end
    end
    HideOverlay()
end

-- The tooltip hook runs for EVERY item tooltip in the whole game (including other addons, damage meters, ...):
-- an error must never escape here; when in doubt the click area is simply hidden.
local function CheckOverlay(focus)
    local ok = pcall(CheckOverlayRaw, focus)
    if not ok then HideOverlay() end
end

overlay:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.isTrade then
        if GameTooltip.SetTradeTargetItem then GameTooltip:SetTradeTargetItem(7) end
    elseif self.bag and self.slot then
        GameTooltip:SetBagItem(self.bag, self.slot)
    end
    if LP.db and LP.db.pick.hint then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ccffPicky|r  |cff4de88a" .. L["Right-click to pick"] .. "|r")
    end
    GameTooltip:Show()
end)
overlay:SetScript("OnLeave", function()
    HideOverlay()
    GameTooltip:Hide()
end)

-- Tooltip hook (modern client) or fallback for older clients
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        if tooltip == GameTooltip then CheckOverlay(GetMouseFocusCompat()) end
    end)
elseif GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", function() CheckOverlay(GetMouseFocusCompat()) end)
end

LP.On("MODIFIER_STATE_CHANGED", function()
    if InCombatLockdown() then return end
    if IsShiftKeyDown() then HideOverlay() else CheckOverlay(GetMouseFocusCompat()) end
end)
LP.On("TRADE_CLOSED", HideOverlay)

-- After picking (or any change to bags/trade) re-check the state:
-- click area gone, then decide again with the box's current state.
-- If the box is open now, the area stays gone and the normal right-click opens it.
-- After combat: the click area cannot be hidden in combat. Clean up now and decide again,
-- so it does not hang on a reused button with stale bag/slot values.
LP.On("PLAYER_REGEN_ENABLED", function()
    HideOverlay()
    LP.After(0.1, function() CheckOverlay(GetMouseFocusCompat()) end)
end)

-- Refresh the tooltip without mouse movement: otherwise the client only rebuilds it on re-entering.
-- For that we trigger the "enter" of the bag slot (or our click area) ourselves.
local function RefreshTooltip()
    pcall(function()
        if overlay:IsShown() and overlay:IsMouseOver() then
            local fn = overlay:GetScript("OnEnter")
            if fn then fn(overlay) end
            return
        end
        local focus = GetMouseFocusCompat()
        if not focus or focus == overlay then return end
        local isSlot = GetBagAndSlot(focus) ~= nil
        if not isSlot then
            local n = type(focus.GetName) == "function" and focus:GetName()
            isSlot = type(n) == "string" and n:find("TradeRecipientItem7", 1, true) ~= nil
        end
        if not isSlot then return end
        if type(focus.UpdateTooltip) == "function" then
            focus:UpdateTooltip()
        else
            local fn = focus.GetScript and focus:GetScript("OnEnter")
            if fn then fn(focus) end
        end
    end)
end

local function Recheck(refreshTip)
    if InCombatLockdown() then return end
    HideOverlay()
    LP.After(0.15, function()
        CheckOverlay(GetMouseFocusCompat())
        if refreshTip then RefreshTooltip() end
    end)
end
LP.On("BAG_UPDATE_DELAYED", function() Recheck(true) end)
LP.On("ITEM_LOCK_CHANGED", function() Recheck(false) end)
LP.On("TRADE_TARGET_ITEM_CHANGED", function() Recheck(true) end)
LP.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, a, b)
    if unit ~= "player" then return end
    local id = (type(b) == "number" and b) or (type(a) == "number" and a)
    local name = (type(a) == "string" and a)
    -- only re-check after "Pick Lock" (not after every spell)
    if id == LP.PICK_SPELL_ID or (name and name == LP.PickName()) then Recheck(true) end
end)

-- Hover check (debug): explains why a click area appears under the mouse or not ----------------------
function LP.InspectHover()
    local focus = GetMouseFocusCompat()
    if not focus then LP.Print(L["Nothing under the mouse."]) return end
    local function SafeName(f)
        if not f or type(f.GetName) ~= "function" then return "?" end
        local ok, n = pcall(f.GetName, f)
        return (ok and type(n) == "string") and n or "(unnamed)"
    end
    local lines = {}
    lines[#lines + 1] = "frame: " .. SafeName(focus)
    local parent = type(focus.GetParent) == "function" and focus:GetParent() or nil
    lines[#lines + 1] = "parent: " .. SafeName(parent)
    local bag, slot = GetBagAndSlot(focus)
    lines[#lines + 1] = ("bag/slot: %s / %s"):format(tostring(bag), tostring(slot))
    if bag and slot then
        local id = (C_Container and C_Container.GetContainerItemID and C_Container.GetContainerItemID(bag, slot)) or nil
        local locked, req = LP.IsLockedItem(bag, slot)
        lines[#lines + 1] = ("item id: %s, locked: %s, needs skill: %s"):format(tostring(id), tostring(locked), tostring(req))
        lines[#lines + 1] = ("your skill: %d (estimated: %s) -> %s"):format(LP.Skill(), tostring(LP.skillEstimated),
            (not locked) and "no click area (not locked)" or ((not req) or LP.skillEstimated or LP.Skill() >= req) and "click area expected" or "no click area (skill too low)")
    end
    local nm = SafeName(focus) .. SafeName(parent)
    if nm:find("TradeRecipientItem7", 1, true) then
        lines[#lines + 1] = "trade slot 7: locked = " .. tostring(TradeSlotLocked())
    end
    lines[#lines + 1] = ("click area shown: %s | combat lockdown: %s | shift held: %s"):format(
        tostring(overlay:IsShown()), tostring(InCombatLockdown()), tostring(IsShiftKeyDown()))
    for _, l in ipairs(lines) do
        LP.Print("hover> " .. l)
        LP.DevDebug("pick", "hover> %s", l)
    end
end

-- 4) Detect success (-> statistics, auto-leave) -------------------------------------
LP.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, a, b)
    if unit ~= "player" then return end
    local id = (type(b) == "number" and b) or (type(a) == "number" and a)
    local name = (type(a) == "string" and a)
    if id == LP.PICK_SPELL_ID or (name and name == LP.PickName()) then
        -- treat the picked box as open for a short time (no second "Pick Lock" on an open box)
        local t = LP.lastPickTarget
        if t and (GetTime() - t.t) < 15 then
            if t.bag and t.slot then LP.MarkPicked(t.bag, t.slot) end
            if t.trade then LP.tradePickedAt = GetTime() end
            LP.DevDebug("pick", "marked as picked: %s (no click area for %ds)", t.trade and "trade slot" or ("bag " .. tostring(t.bag) .. " slot " .. tostring(t.slot)), PICK_GRACE)
            LP.lastPickTarget = nil
        end
        if LP.OnPickSuccess then LP.OnPickSuccess() end
    end
end)

function LP.OnLogin()
    if LP.BuildMinimap then LP.BuildMinimap() end
end
