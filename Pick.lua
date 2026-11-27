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

-- Diagnosis: the text lines the client gives for a bag slot (what the lock check reads)
function LP.SlotLines(bag, slot)
    if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return "no C_TooltipInfo" end
    local d = C_TooltipInfo.GetBagItem(bag, slot)
    if not d or not d.lines then return "no data" end
    local t = {}
    for _, line in ipairs(d.lines) do t[#t + 1] = tostring(line.leftText) end
    return table.concat(t, " | ")
end

-- Seams for the self tests (see LP.Game in Core.lua): tests replace these fields, never a game function
LP.Game.ContainerItemID = ContainerItemID
LP.Game.SlotLocked = SlotLocked
LP.Game.Time = function() return GetTime() end

-- Boxes just picked: the client needs a moment until the tooltip no longer shows "Locked".
-- During this grace period the slot counts as open, so "Pick Lock" is never cast again on an open box.
local recentPick = {}
local PICK_GRACE = 3
function LP.MarkPicked(bag, slot)
    recentPick[bag .. ":" .. slot] = LP.Game.Time()
end
function LP.ClearRecentPicks() for k in pairs(recentPick) do recentPick[k] = nil end end   -- for the self tests
function LP.RecentlyPicked(bag, slot)
    local t = recentPick[bag .. ":" .. slot]
    return t ~= nil and (LP.Game.Time() - t) < PICK_GRACE
end

local lockableID = {}      -- item IDs that have shown "Locked" at least once
local notLockableUntil = {} -- unknown items without a lock: do not check again for 30 seconds
function LP.IsLockedItem(bag, slot)
    local id = LP.Game.ContainerItemID(bag, slot)
    if not id then return false end
    if LP.RecentlyPicked(bag, slot) then return false end   -- just picked: counts as open (see above)
    local box = LP.BOXES[id]
    local req = box and box[1]
    if not box and not lockableID[id] then
        local untilT = notLockableUntil[id]
        if untilT and LP.Game.Time() < untilT then return false end
    end
    local locked = LP.Game.SlotLocked(bag, slot)
    if locked == nil then return false end
    if locked then
        lockableID[id] = true
        notLockableUntil[id] = nil
        return true, req
    end
    if not box and not lockableID[id] then notLockableUntil[id] = LP.Game.Time() + 30 end
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
-- The click area hangs on UIParent (see PlaceOverlay), not on a bag button, so it needs no state driver. (A "visibility" state driver
-- showed it again about once a second after our own Hide(): the area came back over boxes that were already picked and swallowed
-- every right-click on them.)

-- Remember WHAT was last picked via right-click (for the grace period after success)
overlay:HookScript("PreClick", function(self, button)
    if button == "RightButton" then
        LP.lastPickTarget = { bag = self.bag, slot = self.slot, trade = self.isTrade, t = GetTime() }
        LP.DevDebug("pick", "right-click pick started on %s", self.isTrade and "trade slot" or ("bag " .. tostring(self.bag) .. " slot " .. tostring(self.slot)))
    end
end)

-- Diagnosis: what happened after a click on the click area (the secure action runs after PreClick). Red game errors and failed casts
-- right after a click are logged too, so "nothing happens" can be explained.
overlay:HookScript("PostClick", function(self, button)
    if button ~= "RightButton" then return end
    LP.lastClickAt = GetTime()
    LP.DevDebug("pick", "after click: type=%s spell=%s bag=%s slot=%s casting=%s targeting=%s", tostring(self:GetAttribute("type")),
        tostring(self:GetAttribute("spell")), tostring(self:GetAttribute("target-bag")), tostring(self:GetAttribute("target-slot")),
        tostring(UnitCastingInfo and UnitCastingInfo("player") ~= nil), tostring(SpellIsTargeting and SpellIsTargeting()))
end)
LP.On("UI_ERROR_MESSAGE", function(_, _, msg)
    if LP.lastClickAt and GetTime() - LP.lastClickAt < 2 then LP.DevDebug("pick", "game message right after the click: %s", tostring(msg)) end
end)
for _, ev in ipairs({ "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_START" }) do
    LP.On(ev, function(e, unit, _, spellId)
        if unit == "player" and LP.lastClickAt and GetTime() - LP.lastClickAt < 5 then
            LP.DevDebug("pick", "%s spell=%s", e, tostring(spellId))
        end
    end)
end

-- Put the click area over a frame WITHOUT parenting or anchoring it to that frame: a protected frame that hangs on a Blizzard bag
-- button makes the button protected, and in combat Blizzard's own bag code is then blocked ("SetPassThroughButtons").
-- So the area stays on UIParent and is placed by screen position and scale. Returns false when the frame has no position yet.
local function PlaceOverlay(focus)
    local l, b, w, h = focus:GetRect()
    if not (l and b and w and h) then return false end
    local fs, ps = focus:GetEffectiveScale(), UIParent:GetEffectiveScale()
    overlay.target = focus
    overlay:SetParent(UIParent)
    overlay:SetScale((fs and ps and ps > 0) and fs / ps or 1)
    overlay:ClearAllPoints()
    overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
    overlay:SetSize(w, h)
    return true
end

local function HideOverlay()
    if not LP.Game.InCombat() and overlay:IsShown() then
        LP.DevDebug("pick", "click area hidden (bag %s slot %s)", tostring(overlay.bag), tostring(overlay.slot))
        overlay:Hide()
    end
    if not LP.Game.InCombat() then overlay.target = nil end
end

-- Is the thing under the click area still a box that needs picking? (false for an empty slot, an item that is not a box, a picked box)
local function StillLocked(self)
    if self.isTrade then return TradeSlotLocked() and true or false end
    if not (self.bag and self.slot) then return false end
    if LP.Game.ContainerItemID(self.bag, self.slot) == nil then return false end
    return LP.IsLockedItem(self.bag, self.slot) and true or false
end
LP.OverlayStillLocked = StillLocked
-- The tooltip hint "Right-click to pick": only while this very box is still locked (a picked box must not say it)
-- Returns the hint text for the tooltip, or nil.
local function TooltipHint(self)
    if StillLocked(self) and LP.db and LP.db.pick.hint then
        return "|cff00ccffPicky|r  |cff4de88a" .. L["Right-click to pick"] .. "|r"
    end
end
LP.OverlayTooltipHint = TooltipHint

-- The area no longer hangs on the bag button, so it does not disappear with it any more: while it is shown, check a few times a second
-- that the frame under it is still visible and that this very box is still locked; otherwise hide it (a right-click on a box that is
-- already picked would do nothing at all).
do
    local acc = 0
    overlay:HookScript("OnUpdate", function(self, dt)
        acc = acc + dt
        if acc < 0.2 then return end
        acc = 0
        if LP.Game.InCombat() or not self:IsShown() then return end
        local t = self.target
        if not t or not t:IsVisible() or not StillLocked(self) then HideOverlay() end
    end)
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

-- Windows where a right-click on a bag item already means something else (sell, deposit, attach, auction):
-- there the click area must not cover the box, otherwise the item cannot be sold or stored.
local BUSY_FRAMES = { "MerchantFrame", "BankFrame", "MailFrame", "AuctionHouseFrame", "AuctionFrame", "GuildBankFrame" }
local function RightClickBusy()
    for _, name in ipairs(BUSY_FRAMES) do
        local f = _G[name]
        if f and f.IsShown and f:IsShown() then return true end
    end
    return false
end

local function CheckOverlayRaw(focus)
    if LP.Game.InCombat() or not LP.db or not LP.IsRogue() then return end
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
            if overlay:IsShown() and overlay.isTrade and overlay.target == focus then return end   -- already there, do not set anything again
            overlay.isTrade, overlay.bag, overlay.slot = true, nil, nil
            if not PlaceOverlay(focus) then HideOverlay() return end
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

    if RightClickBusy() then HideOverlay() return end   -- vendor, bank, mail, auction house: normal right-click

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
                if overlay:IsShown() and overlay.bag == bag and overlay.slot == slot and overlay.target == focus then return end   -- already there
                overlay.isTrade, overlay.bag, overlay.slot = nil, bag, slot
                if not PlaceOverlay(focus) then HideOverlay() return end
                overlay:SetFrameLevel(focus:GetFrameLevel() + 5)
                overlay:SetAttribute("type", "spell")
                overlay:SetAttribute("spell", LP.PickName())
                overlay:SetAttribute("target-bag", bag)
                overlay:SetAttribute("target-slot", slot)
                overlay:SetAttribute("macrotext", nil)
                overlay:Show()
                LP.DevDebug("pick", "click area on bag %d slot %d (needs %s, skill %d, item %s) tooltip lines: %s", bag, slot, req, LP.Skill(),
                    tostring(LP.Game.ContainerItemID(bag, slot)), LP.SlotLines and LP.SlotLines(bag, slot) or "?")
                return
            else
                LP.Debug("pick", "bag %d slot %d is locked but your skill is too low (needs %s, skill %d)", bag, slot, req, LP.Skill())
            end
        end
    end
    HideOverlay()
end

-- Seams for the self tests (the frame and the decision functions; nothing here changes behaviour)
LP.Overlay = overlay
LP.CheckOverlayRaw = CheckOverlayRaw

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
    local hint = TooltipHint(self)
    if hint then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(hint)
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
    if LP.Game.InCombat() then return end
    if IsShiftKeyDown() then HideOverlay() else CheckOverlay(GetMouseFocusCompat()) end
end)
LP.On("TRADE_CLOSED", HideOverlay)
LP.On("PLAYER_ENTERING_WORLD", HideOverlay)   -- the state driver shows the area once at login: nothing to click yet
-- A vendor/bank/mail/auction window just opened: the click area must not stay on a box under the mouse
for _, ev in ipairs({ "MERCHANT_SHOW", "BANKFRAME_OPENED", "MAIL_SHOW", "AUCTION_HOUSE_SHOW", "GUILDBANKFRAME_OPENED" }) do
    LP.On(ev, HideOverlay)
end

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
    if LP.Game.InCombat() then return end
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
        tostring(overlay:IsShown()), tostring(LP.Game.InCombat()), tostring(IsShiftKeyDown()))
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
            LP.After(0.3, function() if RefreshTooltip then RefreshTooltip() end end)
        end
        if LP.OnPickSuccess then LP.OnPickSuccess() end
    end
end)

-- 5) The box list: which boxes are in the bags, and what comes next --------------------------------------------------------------
-- One entry per known box: action "open" (already picked, a normal use opens it) or "pick" (locked and your skill is enough).
-- Boxes that need more skill are only counted. Open boxes come first, then the highest skill you can pick (the best chance to rise).
LP.Game.BagSlots = function(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
    return (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
end
function LP.BoxList()
    local list, tooHigh = {}, 0
    local skill = LP.Skill()
    for bag = 0, 5 do
        for slot = 1, LP.Game.BagSlots(bag) do
            local id = LP.Game.ContainerItemID(bag, slot)
            local box = id and LP.BOXES[id]
            if box then
                local locked
                if LP.RecentlyPicked(bag, slot) then locked = false else locked = LP.Game.SlotLocked(bag, slot) end
                if locked == false then
                    list[#list + 1] = { bag = bag, slot = slot, id = id, action = "open", req = box[1] }
                elseif locked then
                    if LP.skillEstimated or skill >= box[1] then
                        list[#list + 1] = { bag = bag, slot = slot, id = id, action = "pick", req = box[1] }
                    else
                        tooHigh = tooHigh + 1
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.action ~= b.action then return a.action == "open" end
        if a.req ~= b.req then return a.req > b.req end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    return list, tooHigh
end

-- Refresh the stored list (LP.boxes, LP.boxesTooHigh) a moment after anything in the bags or the cast changed, then tell the UI.
local boxPending = false
function LP.RefreshBoxes()
    if boxPending then return end
    boxPending = true
    LP.After(0.2, function()
        boxPending = false
        if not LP.db or not LP.IsRogue() then LP.boxes, LP.boxesTooHigh = {}, 0 else LP.boxes, LP.boxesTooHigh = LP.BoxList() end
        if LP.ApplyBoxButton then LP.ApplyBoxButton() end
        if LP.UpdateMinimapState then LP.UpdateMinimapState() end
    end)
end
LP.boxes, LP.boxesTooHigh = {}, 0
-- (not ITEM_LOCK_CHANGED: it fires for every item picked up or dragged and changes nothing about a box)
for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED" }) do
    LP.On(ev, function() LP.RefreshBoxes() end)
end
LP.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit) if unit == "player" then LP.RefreshBoxes() end end)

function LP.OnLogin()
    if LP.BuildMinimap then LP.BuildMinimap() end
end
