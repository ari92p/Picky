-- Picky / Finder.lua : chat detection, auto-invite, announcement, thanks, auto-leave
local ADDON, LP = ...
local L = LP.L

LP.requests = {}   -- newest first; after loading this is LP.db.orders (stored permanently), see LoadOrders
LP.STATUS = {
    new = { L["New"], "ffd100" },
    queued = { L["Waiting"], "9aa0ad" },
    invited = { L["Invited"], "00bdf2" },
    grouped = { L["In group"], "4de88a" },
    done = { L["Done"], "6c7280" },
    toohigh = { L["Skill too low"], "ff5959" },
    manual = { L["Manual"], "ffd100" },
    timeout = { L["No answer"], "6c7280" },
}

-- Keywords (de + en) ---------------------------------------------------------
local ROGUE = { "rogue", "rogues", "rouge", "rog", "schurke", "schurken", "schurkin" }
local LOCKTOK = { "lockpick", "lockpicker", "lockpicking", "picklock", "lockbox", "lockboxes", "junkbox", "junkboxes", "lock", "locked",
    "chest", "chests", "box", "boxes", "kiste", "kisten", "truhe", "truhen", "footlocker", "schloss", "schlösser", "schlüssel" }
-- "open / unlock" alone: enough for whispers and together with "rogue"
local VERB = { "open", "opening", "unlock", "unlocking" }
local LOCKSUB = { "lockpick", "pick lock", "schlossknack", "schlösser", "knack", "aufschlie", "schließkass", "schliesskass", "öffnen", "aufmachen", "aufbrechen",
    "kiste", "truhe", "kassette", "plunder" }   -- German compounds: "Eisenkiste", "Holztruhe", "Stahlschließkassette", "Plunderkiste"
local SEEK = { "lf", "lf1", "suche", "suchen", "sucht", "gesucht", "need", "needs", "brauche", "braucht", "wer", "jemand",
    "anyone", "anybody", "someone", "wtb", "pls", "plz", "bitte", "please", "help", "hilfe", "can", "could", "would" }
local EXCL = { "lfm", "dps", "tank", "tanks", "healer", "heal", "wts", "wtt", "biete", "bietet", "bieten", "offering",
    "offers", "boost", "raid", "sell", "verkaufe", "where", "wo", "how", "wie", "quest", "quests" }

local function HasTok(s, list)
    for _, w in ipairs(list) do
        if s:find("%f[%w]" .. w .. "%f[%W]") then return true end
    end
    return false
end
local function HasSub(s, list)
    for _, w in ipairs(list) do
        if s:find(w, 1, true) then return true end
    end
    return false
end

-- "chest/chests" also with typos ("chersts", "chesst"): ch + 1-2 letters + st(s), as a whole word
local function ChestLike(s)
    return s:find("%f[%a]ch%a%a?st%f[%A]") ~= nil or s:find("%f[%a]ch%a%a?sts%f[%A]") ~= nil
end

-- An explicit skill number next to a lockpicking word: "lockpick 175", "175 lockpicking", "skill 150+", "schlossknacken 200".
-- Returns the highest such number (skill range 20-300; smaller numbers are usually amounts like "3 chests").
local SKILL_PATTERNS = {
    "%f[%a]lockpick%a*%s*:?%s*(%d+)", "(%d+)%+?%s*lockpick",
    "%f[%a]skill%s*:?%s*(%d+)", "(%d+)%+?%s*skill",
    "schlossknack%a*%s*:?%s*(%d+)", "(%d+)%+?%s*schlossknack",
    "%f[%a]knacken%s*:?%s*(%d+)", "(%d+)%+?%s*knacken",
}
local function ExplicitSkill(s)
    local best
    for _, pat in ipairs(SKILL_PATTERNS) do
        for num in s:gmatch(pat) do
            local n = tonumber(num)
            if n and n >= 20 and n <= 300 and (not best or n > best) then best = n end
        end
    end
    return best
end

-- Analyze message -> ok, required skill, box name
local function Analyze(msg, isWhisper)
    local ids = {}
    -- Strip color codes (old format |cffRRGGBB and new |cnIQ1:), then read item links, then reduce all remaining links to their text
    local plain = msg:gsub("|cn[^:|]*:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local clean = plain:gsub("|Hitem:(%d+)[^|]*|h(%[?[^|]*%]?)|h", function(id, name)
        ids[#ids + 1] = tonumber(id)
        return name
    end)
    clean = clean:gsub("|H[^|]*|h([^|]*)|h", "%1")
    clean = clean:gsub("{%a+%d*}", "")
    local s = clean:lower()

    local req, label
    for _, id in ipairs(ids) do
        local b = LP.BOXES[id]
        if b and (not req or b[1] > req) then req, label = b[1], LP.BoxName(id) end
    end
    local linked = req ~= nil   -- an item link of the box is a reliable hint
    -- Keywords ("bronze", "iron" ...) only as an estimate when no item link gives the exact value
    local hint = HasTok(s, LOCKTOK) or HasSub(s, LOCKSUB) or ChestLike(s)
    if not req and hint then
        for _, k in ipairs(LP.BOXKEYS) do
            if s:find(k[1], 1, true) and (not req or k[2] > req) then req, label = k[2], k[3] end
        end
    end

    -- an explicit number ("lockpick 175") wins when it is higher than the estimate
    if hint or HasTok(s, ROGUE) then
        local n = ExplicitSkill(s)
        if n and (not req or n > req) then req = n end
    end

    local lock = linked or hint
    local verb = HasTok(s, VERB)
    local rogue = HasTok(s, ROGUE) or s:find("schurk", 1, true) ~= nil
    local seek = HasTok(s, SEEK)
    local excl = HasTok(s, EXCL)

    local ok
    if isWhisper then
        -- whispered directly: a box/lock is enough, or "open/unlock" + request
        ok = lock or (verb and (rogue or seek)) or (rogue and seek)
    else
        -- public chat is stricter: box/lock (or open/unlock + rogue) AND a request, no sale/group search
        ok = (lock or (verb and rogue)) and (rogue or seek) and not excl
    end
    return ok, req, label, { lock = lock, verb = verb, rogue = rogue, seek = seek, excl = excl }
end
LP.Analyze = Analyze

-- Manage requests -------------------------------------------------------------------
function LP.FindRequest(name)
    for _, r in ipairs(LP.requests) do
        if LP.SameName(r.name, name) then return r end
    end
end

local function Touch()
    if LP.RefreshAll then LP.RefreshAll() end
end

-- Notify all displays (toast, sound, taskbar, mini list ...): see State.lua
local function Notify(req)
    LP.Notice("request", req)
end

function LP.TryInvite(req)
    if not req then return end
    if LP.GroupCount() >= 5 then
        req.status = "queued"
        LP.Debug("invite", "group is full, %s stays queued", req.name)
        Touch()
        return
    end
    LP.Debug("invite", "inviting %s", req.name)
    LP.Invite(req.name)
    LP.Feed("invite", L["%s invited"]:format(req.name))
    req.status = "invited"
    local myInvite = GetTime()
    req.invitedAt = myInvite   -- a repeated invite starts a new 60 s window; the old timer must not fire for it
    LP.pending = req
    if not LP.IsDry() then LP.db.stats.invited = LP.db.stats.invited + 1 end
    Touch()
    if LP.IsDry() then return end   -- dry run: never a real join, so no "not joined" timeout either
    LP.After(60, function()
        if req.status == "invited" and req.invitedAt == myInvite then
            req.status = "timeout"
            LP.Debug("invite", "%s did not join within 60s", req.name)
            LP.Feed("warn", L["%s did not join"]:format(req.name))
            if LP.pending == req then LP.pending = nil end
            Touch()
            LP.TryNext()
        end
    end)
end

function LP.TryNext()
    local f = LP.db.finder
    if not f.enabled or LP.InGroup() or LP.pending then return end
    local now = GetTime()
    for i = #LP.requests, 1, -1 do   -- oldest first
        local r = LP.requests[i]
        if r.status == "queued" then
            if now - r.time <= f.maxAge then
                LP.TryInvite(r)
                return
            else
                r.status = "timeout"
            end
        end
    end
    Touch()
end

-- Decision for a new request: invite, queue, manual, or not because the skill is too low
function LP.Decide(req)
    local f = LP.db.finder
    local skill = LP.Skill()
    if req.req and req.req > skill then
        req.status = "toohigh"   -- skill is not enough: do not invite, but do not message anyone either
        LP.Debug("invite", "%s needs skill %d, you have %d -> not invited", req.name, req.req, skill)
        return
    end
    if not req.req and not f.inviteUnknown then
        req.status = "manual"
        LP.Debug("invite", "%s: box unknown and 'invite unknown' is off -> manual", req.name)
        return
    end
    if not f.autoInvite then
        req.status = "new"
        LP.Debug("invite", "auto invite is off -> %s waits for a click", req.name)
        return
    end
    if (LP.InGroup() or LP.pending) and f.onlyWhenFree then   -- group is busy OR someone has already been invited
        req.status = "queued"
        LP.Debug("invite", "you are in a group or waiting for an invite -> %s queued", req.name)
        return
    end
    LP.TryInvite(req)
end

local simCount = 0
-- Process a chat message. sim = true: simulation (bypasses "Finder on" and "Rogue", name is not checked against you)
function LP.OnChat(event, msg, sender, sim)
    local db = LP.db
    if not db or not msg or not sender then return end
    if not sim and (not db.finder.enabled or not LP.IsRogue()) then return end
    local name = LP.Short(sender)
    if name and not sim and LP.SameName(name, UnitName("player")) then
        -- own message: if it contains the spell link (e.g. from your macro), it counts as an announcement
        if msg:find("|Hspell:" .. LP.PICK_SPELL_ID, 1, true) then LP.lastAdSeen = GetTime() LP.Debug("chat", "own announcement seen") end
        return
    end
    if not name then return end
    if LP.IsIgnored(name) then
        LP.Debug("chat", "ignored sender %s", name)
        return
    end

    local ok, req, label, why = Analyze(msg, event == "CHAT_MSG_WHISPER")
    if not ok then
        -- only log "near misses", otherwise every trade-chat sentence would end up in the log
        if why and (why.lock or why.verb or why.rogue) then
            LP.Debug("chat", "no request from %s (lock=%s verb=%s rogue=%s seek=%s excl=%s): %s",
                name, why.lock, why.verb, why.rogue, why.seek, why.excl, msg)
        end
        return
    end

    local now = GetTime()
    local existing = LP.FindRequest(name)
    if existing and existing.status ~= "done" and now - existing.time < db.finder.cooldown then   -- a finished order does not count: whoever writes again after the end has a new one
        existing.time, existing.msg = now, msg
        if req then existing.req, existing.label = req, label end
        LP.Debug("chat", "%s asked again within the cooldown, updated the existing request", name)
        -- someone who is already in my group writes (they invited me earlier): treat as customer
        if not LP.partner and LP.InGroup() and LP.InGroupWith(name) and existing.status ~= "grouped" and existing.status ~= "done" then
            LP.Debug("group", "%s writes and is already in your group -> customer", name)
            LP.HandleJoin(existing)
        end
        if existing.status == "timeout" or existing.status == "toohigh" then
            existing.status = "new"   -- repeated request after expiry / skill too low: re-evaluate
            LP.Decide(existing)
        end
        Touch()
        return
    end

    -- sender = full name (with realm for players from other realms): so the whisper really arrives
    -- stamp = timestamp (epoch) for display and storage; time = GetTime() only for wait times in this session
    local r = { name = name, sender = sender, msg = msg, time = now, stamp = time(), req = req, label = label, status = "new", sim = sim }
    table.insert(LP.requests, 1, r)
    while #LP.requests > 1000 do table.remove(LP.requests) end   -- safety limit, practically unlimited
    LP.Debug("chat", "request from %s (%s): need=%s box=%s | %s", name, event, req, label, msg)
    LP.Feed("request", label and L["Request from %s (%s)"]:format(name, label) or L["Request from %s"]:format(name))
    if not LP.partner and LP.InGroup() and LP.InGroupWith(name) then
        -- the customer already invited YOU before their message came: treat as customer immediately, not in the queue
        LP.Debug("group", "%s is already in your group -> customer, no invite needed", name)
        LP.HandleJoin(r)
    else
        LP.Decide(r)    -- decide first (invite/decline), then notify: the notification shows the real status
    end
    LP.Debug("chat", "status of %s: %s", name, r.status)
    if r.status == "toohigh" then
        LP.Feed("warn", L["%s: skill too low (needs %d)"]:format(name, req or 0))
    elseif r.status == "queued" then
        LP.Feed("queue", L["%s is waiting"]:format(name))
    end
    Notify(r)
    Touch()
    return r
end
for _, ev in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER" }) do
    LP.On(ev, function(event, msg, sender) LP.OnChat(event, msg, sender) end)
end

-- Accepting invites ------------------------------------------------------------------
-- Was an announcement made in the last 10 minutes? (via Picky OR your own message with the spell link, e.g. from a macro)
local AD_WINDOW = 600
function LP.AdRecent()
    local t = math.max(LP.lastAd or 0, LP.lastAdSeen or 0)
    return t > 0 and (GetTime() - t) < AD_WINDOW
end

-- Should a group invite be accepted automatically? -> yes/no + reason (for the log and the tests)
function LP.ShouldAcceptInvite(inviter)
    local f = LP.db and LP.db.finder
    if not f or not f.enabled or not f.autoAccept then return false, "auto accept is off or finder is off" end
    if LP.InGroup() then return false, "already in a group" end
    local short = LP.Short(inviter) or ""
    if LP.IsIgnored(short) then return false, "ignored player" end
    return true, "auto accept is on"   -- setting "Accept invites automatically" + Finder on: every invite, no ifs and buts
end

LP.On("PARTY_INVITE_REQUEST", function(_, inviter)
    local f = LP.db and LP.db.finder
    LP.Debug("group", "party invite from %s (finder %s, auto accept %s, already in group %s)", tostring(inviter), tostring(f and f.enabled), tostring(f and f.autoAccept), tostring(LP.InGroup()))
    LP.lastInviter = { name = inviter, t = GetTime() }   -- who invited me last (see CheckRoster)
    if LP.Toast then LP.Toast.DismissRequest(inviter) end   -- they invite me themselves: the request toast is obsolete
    local accept, why = LP.ShouldAcceptInvite(inviter)
    LP.lastInviter.auto = accept and true or false   -- did Picky accept it itself? (only then does an unknown person count as a customer)
    LP.Debug("group", "invite from %s: %s (%s)", tostring(inviter), accept and "accepting" or "not accepting", why)
    if not accept then return end
    if LP.IsDry() then LP.Debug("group", "[dry run] would accept the invite") return end
    pcall(AcceptGroup)
    LP.After(0.2, function() pcall(StaticPopup_Hide, "PARTY_INVITE") end)
end)

-- Blocked actions: WoW reports "Interface action failed because of an AddOn" without a name. This shows which function it was.
for _, ev in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    LP.On(ev, function(event, addon, func)
        if addon == "Picky" or addon == ADDON then
            if LP.db then
                LP.Debug("blocked", "%s: %s", event, tostring(func))
                LP.Print("|cffff5555" .. event .. "|r " .. tostring(func))
            end
        end
    end)
end

-- Group joined / left ------------------------------------------------------------------
-- Customer joined the group (real event or simulation)
function LP.HandleJoin(p)
    local f = LP.db.finder
    p.status = "grouped"
    p.joinedAt = GetTime()
    p.joinStamp = time()
    p.boxes, p.tipTotal = p.boxes or 0, p.tipTotal or 0
    LP.partner, LP.pickedForPartner = p.name, false
    if LP.pending == p then LP.pending = nil end
    LP.Debug("group", "%s joined the group (greeting whisper: %s)", p.name, f.welcome and "on" or "off")
    LP.Feed("join", L["%s joined the group"]:format(p.name))
    -- greeting first, then the notification: an error in the display must never prevent the whisper
    if f.welcome then LP.Whisper(p.sender or p.name, f.welcomeText) end
    if LP.Toast then LP.Toast.DismissRequest(p.name) end   -- the customer is in the group: the request toast is obsolete
    LP.Notice("joined", p)
    if f.autoLeave and f.idleLeave and f.idleLeave > 0 then
        local who = p.name
        LP.After(f.idleLeave, function()
            if LP.partner == who and not LP.pickedForPartner and (LP.IsDry() or LP.InGroup()) then
                LP.Debug("group", "no activity from %s for %ds -> leaving", who, f.idleLeave)
                LP.Print(L["No activity - leaving the group."])
                LP.DoLeave()
            end
        end)
    end
    Touch()
end

-- Customer is gone / the group is disbanded
function LP.HandleLeave()
    local r = LP.partner and LP.FindRequest(LP.partner)
    LP.SendThanks(r)   -- the customer left on their own: send the collected thanks now (if not already done)
    LP.leaveToken = (LP.leaveToken or 0) + 1   -- planned leave is done
    if r and r.status == "grouped" then r.status = "done" r.endStamp = time() end
    LP.leaveAt = nil
    if LP.Toast then LP.Toast.DismissKey("trade:") end   -- group ended (we left, they left, or we were removed)
    if LP.partner then LP.Feed("leave", L["Group with %s ended"]:format(LP.partner)) end
    LP.Debug("group", "group with %s ended", LP.partner)
    LP.partner, LP.pickedForPartner, LP.waitTradeClose, LP.partnerSim = nil, false, false, nil
    Touch()
    LP.After(1, LP.TryNext)
end

-- Leave the group; in dry run the leave is only simulated (state continues anyway)
-- ONE thank-you for all tips the customer gave in this session (only once)
function LP.SendThanks(r)
    local f = LP.db.finder
    if not r or r.thanked or not f.thanks or (r.tipTotal or 0) <= 0 then return end
    r.thanked = true
    LP.Debug("trade", "sending the thank-you to %s (total tip %s)", r.name, LP.Money(r.tipTotal))
    LP.Whisper(r.sender or r.name, f.thanksText)
    if not LP.IsDry() then LP.db.stats.thanked = LP.db.stats.thanked + 1 end
end

-- Leave after a wait; a new trade by the customer cancels it (several boxes in a row)
function LP.ScheduleLeave(delay)
    LP.leaveToken = (LP.leaveToken or 0) + 1
    local my = LP.leaveToken
    LP.leaveAt = GetTime() + delay   -- for the countdown on the requests page
    LP.Debug("group", "leaving in %ds unless another trade starts", delay)
    LP.After(delay, function()
        if LP.leaveToken == my and LP.partner and (LP.IsDry() or LP.InGroup()) then LP.DoLeave() end
    end)
end
function LP.CancelLeave()
    LP.leaveToken = (LP.leaveToken or 0) + 1
    LP.leaveAt = nil
    LP.Debug("group", "another trade started: not leaving yet")
end

function LP.DoLeave()
    LP.leaveToken = (LP.leaveToken or 0) + 1   -- a still-planned leave is thereby done
    LP.leaveAt = nil
    LP.SendThanks(LP.partner and LP.FindRequest(LP.partner))   -- thank first, then leave
    LP.Leave()
    if LP.IsDry() then LP.HandleLeave() end
end

-- Is anyone from the request list in my group? Two ways:
--  1. I invited them and they joined
--  2. they invited ME (announcement: "just invite me") or joined the group some other way
function LP.CheckRoster()
    local f = LP.db and LP.db.finder
    LP.Debug("group", "roster check: in group %s, customer %s, finder %s, pending %s", tostring(LP.InGroup()), tostring(LP.partner), tostring(f and f.enabled), tostring(LP.pending and LP.pending.name))
    if not f or LP.partner or not LP.InGroup() then return false end
    local p = LP.pending
    if p and p.status == "invited" and LP.InGroupWith(p.name) then
        LP.HandleJoin(p)
        return true
    end
    if f.enabled then
        for _, r in ipairs(LP.requests) do   -- newest first
            if r.status ~= "grouped" and r.status ~= "done" and r.status ~= "toohigh"
                and GetTime() - r.time < 900 and LP.InGroupWith(r.name) then
                LP.Debug("group", "%s is in your group (they invited you or joined on their own)", r.name)
                LP.HandleJoin(r)
                return true
            end
        end
    end
    -- Nobody from the request list: if a stranger invited me and I joined, they are my customer
    -- (they wrote nothing recognizable or invited right away). A request is created for that.
    local inv = LP.lastInviter
    if f.enabled and inv and GetTime() - inv.t < 180 and LP.InGroupWith(inv.name) then   -- Finder on: everyone who invites you is a customer
        LP.lastInviter = nil
        local r = { name = LP.Short(inv.name), sender = inv.name, msg = L["(invited you)"], time = GetTime(), stamp = time(), status = "new" }
        table.insert(LP.requests, 1, r)
        LP.Debug("group", "%s invited you without a recognized request -> treated as customer", r.name)
        LP.Feed("request", L["%s invited you"]:format(r.name))
        LP.HandleJoin(r)
        return true
    end
    return false
end

LP.On("GROUP_ROSTER_UPDATE", function()
    local f = LP.db and LP.db.finder
    if not f then return end
    if LP.partner and not LP.InGroup() then
        if LP.partnerSim then return end   -- the simulation controls its own state
        LP.HandleLeave()
    elseif LP.partner then
        -- Customer gone, but I am still in a group (more than 2 members)? Check after a short pause: names arrive delayed
        if not LP.partnerSim then
            LP.After(2, function()
                if LP.partner and not LP.partnerSim and LP.InGroup() and not LP.InGroupWith(LP.partner) then
                    LP.Debug("group", "%s is no longer in the group", LP.partner)
                    LP.HandleLeave()
                end
            end)
        end
    elseif LP.InGroup() then
        -- group member names are sometimes not there yet on the first event: check again later
        if not LP.CheckRoster() then
            LP.After(1, LP.CheckRoster)
            LP.After(3, LP.CheckRoster)
        end
    else
        LP.After(1, LP.TryNext)
    end
end)

-- Pick succeeded -> leave the group if applicable -----------------------------------------------------
function LP.OnPickSuccess(simulated)
    local f = LP.db.finder
    if not simulated then LP.db.stats.picked = LP.db.stats.picked + 1 end
    LP.Debug("pick", "pick success%s (customer: %s)", simulated and " (simulated)" or "", LP.partner)
    LP.Feed("pick", L["Box picked"])
    if LP.partner then
        LP.pickedForPartner = true
        local order = LP.FindRequest(LP.partner)
        if order then order.boxes = (order.boxes or 0) + 1 end   -- boxes per order
        if f.autoLeave then
            if TradeFrame and TradeFrame:IsShown() and not simulated then
                LP.waitTradeClose = true   -- finish the trade first (tip/thanks)
                LP.Debug("group", "trade window open: leaving after it closes")
            else
                LP.ScheduleLeave(f.leaveDelay or 10)
            end
        end
    end
    Touch()
end

-- Trade: detect tip + thanks ------------------------------------------------------------------
local tradeName, tradeTip, tradeStartMoney, tipHandled = nil, 0, 0, false
local closedName, closedAt   -- partner of the trade that just closed (the completion message can arrive after the window closed)
local lastTrade   -- last closed trade with a tip: waits for the money to arrive / the completion message
LP.On("TRADE_SHOW", function()
    tradeName = (UnitName("NPC")) or (TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText())
    tradeTip, tipHandled = 0, false
    tradeStartMoney = GetMoney and GetMoney() or 0
    LP.Debug("trade", "trade window opened with %s", tradeName)
    if LP.partner then LP.CancelLeave() end   -- the customer trades again (another box): do not leave
end)
local function UpdateTip()
    if GetTargetTradeMoney then
        local m = GetTargetTradeMoney() or 0
        if m ~= tradeTip then LP.Debug("trade", "partner offers %s", LP.Money(m)) end
        tradeTip = m
    end
end
LP.On("TRADE_MONEY_CHANGED", UpdateTip)
LP.On("TRADE_ACCEPT_UPDATE", UpdateTip)

-- Confirm the tip of the trade just closed as soon as the money has arrived
local function ResolveTip(why)
    local lt = lastTrade
    if not lt or lt.done then return end
    local nowMoney = GetMoney and GetMoney() or 0
    if nowMoney >= lt.start + lt.tip then
        lt.done = true
        LP.Debug("trade", "tip confirmed (%s): +%s", why, LP.Money(nowMoney - lt.start))
        LP.HandleTip(LP.Short(lt.name), lt.tip)
    end
end

LP.On("UI_INFO_MESSAGE", function(_, a, b)
    local msg = (type(b) == "string" and b) or (type(a) == "string" and a)
    if not msg then return end
    if msg == _G.ERR_TRADE_COMPLETE then
        LP.Debug("trade", "'trade complete' message (tip %s, partner %s)", LP.Money(tradeTip), tostring(tradeName))
        LP.HandleTradeComplete(tradeName or (closedAt and GetTime() - closedAt < 5 and closedName) or nil)
        if tradeTip > 0 and tradeName and not tipHandled then
            tipHandled = true   -- the message came before the window closed
            LP.HandleTip(LP.Short(tradeName), tradeTip)
        elseif lastTrade and not lastTrade.done and GetTime() - lastTrade.t < 5 then
            ResolveTip("complete message")   -- the message came AFTER the window closed (as in this client)
        end
    elseif LP.db and (LP.db.debug or LP.db.logLive) and msg:lower():find("trade", 1, true) then
        LP.Debug("trade", "info message: %s", msg)   -- helps if the completion message is worded differently in this client
    end
end)

-- A trade finished successfully. With the customer in the group: show the "trade complete" toast
-- (click = thank + leave) and make sure the group is left afterwards, whether or not there was a tip.
function LP.HandleTradeComplete(name)
    if not name or not LP.partner or not LP.SameName(name, LP.partner) then return end
    local f = LP.db.finder
    LP.Notice("trade", LP.Short(name), 0)
    if f.autoLeave and not (LP.leaveAt and LP.leaveAt > GetTime()) then   -- no live countdown yet
        LP.Debug("group", "trade with %s complete: leaving soon", name)
        LP.ScheduleLeave(f.leaveDelay or 10)
    end
end

-- Tip received (real trade or simulation)
function LP.HandleTip(name, tip, simulated)
    local f = LP.db.finder
    LP.Debug("trade", "tip %s from %s%s", LP.Money(tip), name, simulated and " (simulated)" or "")
    LP.Feed("tip", L["Tip from %s: |cffffd100%s|r"]:format(name, LP.Money(tip)))
    if not simulated then LP.db.stats.tips = LP.db.stats.tips + tip end
    local req = LP.FindRequest(name)
    local how   -- for the hint in the toast: "later" = thanks follows on leaving, "sent" = sent immediately
    if f.thanks then
        if req and LP.partner and LP.SameName(req.name, LP.partner) then
            -- customer is still in the group (maybe another box is coming): collect tips, ONE thank-you on leaving
            req.tipTotal = (req.tipTotal or 0) + tip
            req.thanked = false
            how = "later"
            LP.Debug("trade", "thank-you for %s deferred until the group ends (total tip %s)", name, LP.Money(req.tipTotal))
        else
            LP.Whisper((req and req.sender) or name, f.thanksText)   -- full name (realm), if known
            if not LP.IsDry() then LP.db.stats.thanked = LP.db.stats.thanked + 1 end
            if req then req.tipTotal = (req.tipTotal or 0) + tip req.thanked = true end   -- also count it on the order here
            how = "sent"
        end
    elseif req then
        req.tipTotal = (req.tipTotal or 0) + tip   -- thanks is off: still count the tip on the order
    end
    LP.Notice("tip", name, tip, how)
    Touch()
end

LP.On("TRADE_CLOSED", function()
    local name, tip, start, handled = tradeName, tradeTip, tradeStartMoney, tipHandled
    if tradeName then closedName, closedAt = tradeName, GetTime() end   -- TRADE_CLOSED can fire twice: do not overwrite with nil
    tradeName, tradeTip = nil, 0
    LP.Debug("trade", "trade window closed (tip offered %s, already handled: %s)", LP.Money(tip), tostring(handled))
    -- the money arrives shortly AFTER closing: check several times (up to 4 s), the completion message can trigger it too
    if tip > 0 and name and not handled then
        lastTrade = { name = name, tip = tip, start = start, t = GetTime() }
        for _, delay in ipairs({ 0.6, 1.5, 3, 4 }) do
            LP.After(delay, function() ResolveTip("money check") end)
        end
    end
    -- Schedule leaving: after picking (waitTradeClose) OR after every further trade by the customer (e.g. tip only),
    -- otherwise Picky would stay in the group permanently after a second trade
    local f = LP.db.finder
    if LP.partner and f.autoLeave and (LP.waitTradeClose or LP.pickedForPartner) then
        LP.waitTradeClose = false
        LP.Debug("group", "trade closed, leaving soon")
        LP.ScheduleLeave(f.leaveDelay or 10)
    end
end)
-- The customer puts a box in the trade window: if it is too high for you, say so immediately (otherwise you click into the void)
local warnedBox = {}
LP.On("TRADE_TARGET_ITEM_CHANGED", function()
    if not GetTradeTargetItemLink then return end
    local skill = LP.Skill()
    for slot = 1, 7 do
        local link = GetTradeTargetItemLink(slot)
        local id = link and tonumber(link:match("item:(%d+)"))
        local b = id and LP.BOXES[id]
        if b and b[1] > skill and (not warnedBox[link] or GetTime() - warnedBox[link] > 20) then
            warnedBox[link] = GetTime()
            local nm = link:match("%[(.-)%]") or LP.BoxName(id)
            local msg = L["%s needs lockpicking %d, you have %d"]:format(nm, b[1], skill)
            LP.Debug("trade", "box too high: %s", msg)
            LP.Feed("warn", msg)
            LP.Print("|cffff5959" .. msg .. "|r")
            if LP.Toast and LP.Toast.BoxTooHigh then LP.Toast.BoxTooHigh(link, msg, tradeName and LP.Short(tradeName), b[1], skill) end
        end
    end
end)
-- Announcement (trade chat) ---------------------------------------------------------------------------
-- Channels: key = name without suffix ("Trade - Stormwind" -> "trade"), so the choice applies in every city/zone
function LP.ChannelKey(name) return (tostring(name):gsub("%s*%-.*$", ""):lower()) end
function LP.ChannelList()
    local out, list = {}, { GetChannelList() }
    for i = 1, #list, 3 do
        if type(list[i]) == "number" and type(list[i + 1]) == "string" then
            out[#out + 1] = { id = list[i], name = list[i + 1], key = LP.ChannelKey(list[i + 1]) }
        end
    end
    return out
end
-- Without own choice the name filter from the settings applies (Trade)
function LP.AdChannelOn(ch)
    local ad = LP.db.ad
    if type(ad.channels) == "table" then return ad.channels[ch.key] == true end
    local l = ch.name:lower()
    for m in (ad.channelMatch or ""):gmatch("[^,%s]+") do
        if l:find(m:lower(), 1, true) then return true end
    end
    return false
end
function LP.SetAdChannel(key, on)
    local ad = LP.db.ad
    if type(ad.channels) ~= "table" then   -- first choice: start with the previous filter
        ad.channels = {}
        for _, ch in ipairs(LP.ChannelList()) do
            if LP.AdChannelOn(ch) then ad.channels[ch.key] = true end
        end
    end
    ad.channels[key] = on and true or nil
    -- Name parts of the old filter stay noted even if the channel is currently missing (e.g. trade outside the city)
    if not ad.channelsSeeded then
        ad.channelsSeeded = true
        for m in (ad.channelMatch or ""):gmatch("[^,%s]+") do
            if ad.channels[m:lower()] == nil and m:lower() ~= key then ad.channels[m:lower()] = true end
        end
    end
end
function LP.PostAd(manual)
    local ad = LP.db.ad
    local now = GetTime()
    if LP.lastAd and now - LP.lastAd < 60 then
        if manual then LP.Print(L["Please wait (at least 60 seconds between announcements)."]) end
        return
    end
    local text = LP.ExpandAd(ad.text)
    local sent = 0
    for _, ch in ipairs(LP.ChannelList()) do
        if LP.AdChannelOn(ch) and LP.SendChannel(text, ch.id) then sent = sent + 1 end   -- only successful sends count
    end
    if sent > 0 then
        if LP.IsDry() then
            -- dry run: nothing was really sent, the message must say so too
            LP.Feed("warn", L["Test mode: announcement not sent"])
            if manual then
                LP.Print(L["Test mode: would have announced in %d channel(s) - nothing was sent. Turn off the test mode in the Test tab (/picky debug)."]:format(sent))
            end
        else
            LP.lastAd = now
            LP.Feed("ad", L["Announcement posted"])
            if manual then LP.Print(L["Announced in %d channel(s)."]:format(sent)) end
        end
    elseif manual then
        LP.Print(L["No matching channel found (trade only works in cities). Pick channels with the Channels button."])
    end
end

local adToken = 0
function LP.StartAdLoop()
    adToken = adToken + 1
    local my = adToken
    local function wait() return math.max(180, tonumber(LP.db.ad.interval) or 300) end
    local function tick()
        if my ~= adToken then return end
        local ad = LP.db.ad
        if ad.auto and LP.db.finder.enabled and not LP.InGroup() then LP.PostAd(false) end
        LP.nextAdAt = GetTime() + wait()   -- for the countdown on the requests page
        LP.After(wait(), tick)
    end
    LP.nextAdAt = GetTime() + wait()
    LP.After(wait(), tick)
end

-- Cancel the automatic announcement (the x on the requests page); re-enable: settings, announcement
function LP.CancelAutoAd()
    LP.db.ad.auto = false
    LP.nextAdAt = nil
    LP.Debug("chat", "automatic announcement cancelled")
    if LP.RefreshAll then LP.RefreshAll() end
end

-- Simulations (debug page) ------------------------------------------------------------
-- All run as dry run: nothing is really invited, whispered or left.
local function Dry(fn)
    local old = LP.forceDry
    LP.forceDry = true
    local ok, a = pcall(fn)
    LP.forceDry = old
    if not ok then LP.Debug("sim", "simulation error: %s", a) end
    return a
end

-- Send a chat message of an invented player through the real detection
function LP.SimulateChat(msg, whisper)
    simCount = simCount + 1
    local name = "Testplayer" .. simCount
    LP.Debug("sim", "simulating %s from %s: %s", whisper and "a whisper" or "public chat", name, msg)
    return Dry(function()
        return LP.OnChat(whisper and "CHAT_MSG_WHISPER" or "CHAT_MSG_CHANNEL", msg, name, true)
    end)
end

-- The invited (or next waiting) player joins the group
function LP.SimulateJoin()
    Dry(function()
        local p = LP.pending
        if not (p and p.status == "invited") then
            p = LP.NextInvitable()
            if p then LP.TryInvite(p) end
        end
        if p and p.status == "invited" then
            LP.partnerSim = true
            LP.HandleJoin(p)
        else
            LP.Debug("sim", "nobody to join: simulate a request first")
        end
    end)
end

function LP.SimulateTip(copper)
    Dry(function()
        if not LP.partner then LP.Debug("sim", "no customer in the group: simulate 'customer joins' first") return end
        LP.HandleTip(LP.partner, copper or 12500, true)
    end)
end

function LP.SimulatePick()
    Dry(function() LP.OnPickSuccess(true) end)
end

function LP.SimulateLeave()
    Dry(function()
        if not LP.partner then LP.Debug("sim", "no customer in the group") return end
        LP.HandleLeave()
    end)
end


-- Orders: store permanently, load, expire, delete -----------------------------------------------
-- LP.requests is LP.db.orders after loading: everything survives /reload and restart until YOU delete it.
-- r.time is a GetTime() time and only valid in this session: recompute from the stored timestamp (epoch).
local OPEN_EXPIRE = 900   -- open requests older than 15 minutes become "no reply"
function LP.LoadOrders()
    local orders = LP.db.orders
    if type(orders) ~= "table" then orders = {} LP.db.orders = orders end
    local nowE, nowT = time(), GetTime()
    for i = #orders, 1, -1 do
        local r = orders[i]
        if type(r) ~= "table" or r.sim or not r.name then
            table.remove(orders, i)
        else
            r.stamp = r.stamp or nowE
            local age = math.max(0, nowE - r.stamp)
            r.time = nowT - age
            if r.joinStamp then r.joinedAt = nowT - math.max(0, nowE - r.joinStamp) end
            if r.status == "invited" then
                r.status = "timeout"   -- the invite from back then is no longer valid
            elseif (r.status == "new" or r.status == "manual" or r.status == "queued") and age > OPEN_EXPIRE then
                r.status = "timeout"
            end
        end
    end
    LP.requests = orders
end

-- Open requests that are too old (new/manual/waiting) expire and move to "Done"
function LP.ExpireOpen()
    local now = GetTime()
    local changed = false
    for _, r in ipairs(LP.requests) do
        if (r.status == "new" or r.status == "manual" or r.status == "queued") and now - r.time > OPEN_EXPIRE then
            r.status = "timeout"
            if LP.Toast then LP.Toast.DismissRequest(r.name) end
            changed = true
        end
    end
    if changed then Touch() end
end

-- Delete order / delete all finished (only on your click)
function LP.RemoveOrder(r)
    for i, v in ipairs(LP.requests) do
        if v == r then table.remove(LP.requests, i) break end
    end
    Touch()
end
function LP.ClearDone()
    local n = 0
    for i = #LP.requests, 1, -1 do
        if not LP.OPEN_STATUS[LP.requests[i].status] then table.remove(LP.requests, i) n = n + 1 end
    end
    LP.Debug("ui", "cleared %d finished orders", n)
    Touch()
    return n
end

-- Leave the group immediately (the "Leave" button in the history field): thank first (if there was a tip), then leave
function LP.LeaveNow()
    if not LP.partner then return end
    LP.Debug("group", "manual leave requested")
    LP.DoLeave()
end

-- After /reload in the middle of a customer: recognize the group again, otherwise close the order as done
local restored = false
LP.On("PLAYER_ENTERING_WORLD", function()
    if restored then return end
    restored = true
    C_Timer.NewTicker(60, function() LP.ExpireOpen() end)
    LP.After(3, function()
        for _, r in ipairs(LP.requests) do
            if r.status == "grouped" then
                if not LP.partner and LP.InGroup() and LP.InGroupWith(r.name) then
                    LP.partner, LP.pickedForPartner = r.name, (r.boxes or 0) > 0
                    LP.Debug("group", "restored the customer %s after the reload", r.name)
                else
                    r.status, r.endStamp = "done", time()
                end
            end
        end
        Touch()
    end)
end)