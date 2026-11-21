-- Picky / Finder.lua : Chat-Erkennung, Auto-Einladen, Ankündigung, Danke, Auto-Verlassen
local ADDON, LP = ...
local L = LP.L

LP.requests = {}   -- neueste zuerst; nach dem Laden ist das LP.db.orders (dauerhaft gespeichert), siehe LoadOrders
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

-- Schlüsselwörter (de + en) ---------------------------------------------------------
local ROGUE = { "rogue", "rogues", "rouge", "rog", "schurke", "schurken", "schurkin" }
local LOCKTOK = { "lockpick", "lockpicker", "lockpicking", "picklock", "lockbox", "lockboxes", "junkbox", "junkboxes", "lock", "locked",
    "chest", "chests", "box", "boxes", "kiste", "kisten", "truhe", "truhen", "footlocker", "schloss", "schlösser", "schlüssel" }
-- "open / unlock" allein: reicht für Flüstern und zusammen mit "rogue"
local VERB = { "open", "opening", "unlock", "unlocking" }
local LOCKSUB = { "lockpick", "pick lock", "schlossknack", "schlösser", "knack", "aufschlie", "schließkass", "schliesskass", "öffnen", "aufmachen", "aufbrechen",
    "kiste", "truhe", "kassette", "plunder" }   -- deutsche Zusammensetzungen: "Eisenkiste", "Holztruhe", "Stahlschließkassette", "Plunderkiste"
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

-- "chest/chests" auch mit Tippfehlern ("chersts", "chesst"): ch + 1-2 Buchstaben + st(s), als ganzes Wort
local function ChestLike(s)
    return s:find("%f[%a]ch%a%a?st%f[%A]") ~= nil or s:find("%f[%a]ch%a%a?sts%f[%A]") ~= nil
end

-- Nachricht analysieren -> ok, benötigter Skill, Kisten-Bezeichnung
local function Analyze(msg, isWhisper)
    local ids = {}
    -- Farbcodes entfernen (altes Format |cffRRGGBB und neues |cnIQ1:), dann Item-Links lesen, dann alle übrigen Links auf ihren Text kürzen
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
    local linked = req ~= nil   -- ein Item-Link der Kiste ist ein sicherer Hinweis
    -- Stichwörter ("bronze", "iron" ...) nur als Schätzung, wenn kein Item-Link den genauen Wert liefert
    local hint = HasTok(s, LOCKTOK) or HasSub(s, LOCKSUB) or ChestLike(s)
    if not req and hint then
        for _, k in ipairs(LP.BOXKEYS) do
            if s:find(k[1], 1, true) and (not req or k[2] > req) then req, label = k[2], k[3] end
        end
    end

    local lock = linked or hint
    local verb = HasTok(s, VERB)
    local rogue = HasTok(s, ROGUE) or s:find("schurk", 1, true) ~= nil
    local seek = HasTok(s, SEEK)
    local excl = HasTok(s, EXCL)

    local ok
    if isWhisper then
        -- direkt angeflüstert: eine Kiste/ein Schloss genügt, oder "open/unlock" + Bitte
        ok = lock or (verb and (rogue or seek)) or (rogue and seek)
    else
        -- öffentlicher Chat strenger: Kiste/Schloss (oder open/unlock + rogue) UND eine Bitte, kein Verkauf/Gruppensuche
        ok = (lock or (verb and rogue)) and (rogue or seek) and not excl
    end
    return ok, req, label, { lock = lock, verb = verb, rogue = rogue, seek = seek, excl = excl }
end
LP.Analyze = Analyze

-- Anfragen verwalten -------------------------------------------------------------------
function LP.FindRequest(name)
    for _, r in ipairs(LP.requests) do
        if LP.SameName(r.name, name) then return r end
    end
end

local function Touch()
    if LP.RefreshAll then LP.RefreshAll() end
end

-- Meldung an alle Anzeigen (Toast, Ton, Taskleiste, Mini-Liste ...): siehe State.lua
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
    LP.pending = req
    if not LP.IsDry() then LP.db.stats.invited = LP.db.stats.invited + 1 end
    Touch()
    if LP.IsDry() then return end   -- Trockenlauf: nie ein echter Beitritt, also auch kein "nicht beigetreten"-Timeout
    LP.After(60, function()
        if req.status == "invited" then
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
    for i = #LP.requests, 1, -1 do   -- ältestes zuerst
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

-- Entscheidung für eine neue Anfrage: einladen, in die Warteschlange, manuell oder wegen zu niedrigem Skill nicht
function LP.Decide(req)
    local f = LP.db.finder
    local skill = LP.Skill()
    if req.req and req.req > skill then
        req.status = "toohigh"   -- Skill reicht nicht: nicht einladen, aber auch niemanden anschreiben
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
    if (LP.InGroup() or LP.pending) and f.onlyWhenFree then   -- Gruppe belegt ODER schon jemand eingeladen
        req.status = "queued"
        LP.Debug("invite", "you are in a group or waiting for an invite -> %s queued", req.name)
        return
    end
    LP.TryInvite(req)
end

local simCount = 0
-- Chat-Nachricht verarbeiten. sim = true: Simulation (umgeht "Finder an" und "Schurke", Name wird nicht gegen dich geprüft)
function LP.OnChat(event, msg, sender, sim)
    local db = LP.db
    if not db or not msg or not sender then return end
    if not sim and (not db.finder.enabled or not LP.IsRogue()) then return end
    local name = LP.Short(sender)
    if name and not sim and LP.SameName(name, UnitName("player")) then
        -- eigene Nachricht: enthält sie den Zauber-Link (z.B. aus deinem Makro), gilt das als Ankündigung
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
        -- nur "knappe Fehlschläge" protokollieren, sonst würde jeder Handelschat-Satz im Log landen
        if why and (why.lock or why.verb or why.rogue) then
            LP.Debug("chat", "no request from %s (lock=%s verb=%s rogue=%s seek=%s excl=%s): %s",
                name, why.lock, why.verb, why.rogue, why.seek, why.excl, msg)
        end
        return
    end

    local now = GetTime()
    local existing = LP.FindRequest(name)
    if existing and existing.status ~= "done" and now - existing.time < db.finder.cooldown then   -- ein abgeschlossener Auftrag zählt nicht: wer nach dem Ende wieder schreibt, hat einen neuen
        existing.time, existing.msg = now, msg
        if req then existing.req, existing.label = req, label end
        LP.Debug("chat", "%s asked again within the cooldown, updated the existing request", name)
        -- schreibt jemand, der schon in meiner Gruppe ist (er hat mich vorher eingeladen): als Kunde behandeln
        if not LP.partner and LP.InGroup() and LP.InGroupWith(name) and existing.status ~= "grouped" and existing.status ~= "done" then
            LP.Debug("group", "%s writes and is already in your group -> customer", name)
            LP.HandleJoin(existing)
        end
        if existing.status == "timeout" or existing.status == "toohigh" then
            existing.status = "new"   -- erneute Anfrage nach Ablauf / zu niedrigem Skill: neu bewerten
            LP.Decide(existing)
        end
        Touch()
        return
    end

    -- sender = voller Name (mit Realm bei Spielern anderer Realms): damit das Flüstern wirklich ankommt
    -- stamp = Zeitstempel (Epoche) für die Anzeige und das Speichern; time = GetTime() nur für Wartezeiten in dieser Sitzung
    local r = { name = name, sender = sender, msg = msg, time = now, stamp = time(), req = req, label = label, status = "new", sim = sim }
    table.insert(LP.requests, 1, r)
    while #LP.requests > 1000 do table.remove(LP.requests) end   -- Sicherheitsgrenze, praktisch unbegrenzt
    LP.Debug("chat", "request from %s (%s): need=%s box=%s | %s", name, event, req, label, msg)
    LP.Feed("request", label and L["Request from %s (%s)"]:format(name, label) or L["Request from %s"]:format(name))
    if not LP.partner and LP.InGroup() and LP.InGroupWith(name) then
        -- der Kunde hat DICH schon eingeladen, bevor seine Nachricht kam: sofort als Kunde behandeln, nicht in die Warteschlange
        LP.Debug("group", "%s is already in your group -> customer, no invite needed", name)
        LP.HandleJoin(r)
    else
        LP.Decide(r)    -- erst entscheiden (einladen/absagen), dann melden: die Meldung zeigt den echten Status
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

-- Einladungen annehmen -------------------------------------------------------------------
-- Wurde in den letzten 10 Minuten angekündigt? (über Picky ODER eine eigene Nachricht mit dem Zauber-Link, z.B. aus einem Makro)
local AD_WINDOW = 600
function LP.AdRecent()
    local t = math.max(LP.lastAd or 0, LP.lastAdSeen or 0)
    return t > 0 and (GetTime() - t) < AD_WINDOW
end

-- Soll eine Gruppeneinladung automatisch angenommen werden? -> ja/nein + Grund (für das Protokoll und die Tests)
function LP.ShouldAcceptInvite(inviter)
    local f = LP.db and LP.db.finder
    if not f or not f.enabled or not f.autoAccept then return false, "auto accept is off or finder is off" end
    if LP.InGroup() then return false, "already in a group" end
    local short = LP.Short(inviter) or ""
    if LP.IsIgnored(short) then return false, "ignored player" end
    return true, "auto accept is on"   -- Einstellung "Einladungen automatisch annehmen" + Finder an: jede Einladung, ohne Wenn und Aber
end

LP.On("PARTY_INVITE_REQUEST", function(_, inviter)
    local f = LP.db and LP.db.finder
    LP.Debug("group", "party invite from %s (finder %s, auto accept %s, already in group %s)", tostring(inviter), tostring(f and f.enabled), tostring(f and f.autoAccept), tostring(LP.InGroup()))
    LP.lastInviter = { name = inviter, t = GetTime() }   -- wer mich zuletzt eingeladen hat (siehe CheckRoster)
    local accept, why = LP.ShouldAcceptInvite(inviter)
    LP.lastInviter.auto = accept and true or false   -- hat Picky selbst angenommen? (nur dann zählt ein Unbekannter als Kunde)
    LP.Debug("group", "invite from %s: %s (%s)", tostring(inviter), accept and "accepting" or "not accepting", why)
    if not accept then return end
    if LP.IsDry() then LP.Debug("group", "[dry run] would accept the invite") return end
    pcall(AcceptGroup)
    LP.After(0.2, function() pcall(StaticPopup_Hide, "PARTY_INVITE") end)
end)

-- Blockierte Aktionen: WoW meldet "Interface-Aktion auf Grund eines Addons fehlgeschlagen" ohne Namen. Hier steht, welche Funktion es war.
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

-- Gruppe beigetreten / verlassen ------------------------------------------------------------------
-- Kunde ist der Gruppe beigetreten (echtes Ereignis oder Simulation)
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
    -- erst die Begrüßung, dann die Meldung: ein Fehler in der Anzeige darf das Flüstern nie verhindern
    if f.welcome then LP.Whisper(p.sender or p.name, f.welcomeText) end
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

-- Kunde ist weg / die Gruppe ist aufgelöst
function LP.HandleLeave()
    local r = LP.partner and LP.FindRequest(LP.partner)
    LP.SendThanks(r)   -- ging der Kunde von selbst: das gesammelte Danke jetzt senden (falls noch nicht geschehen)
    LP.leaveToken = (LP.leaveToken or 0) + 1   -- geplantes Verlassen ist erledigt
    if r and r.status == "grouped" then r.status = "done" r.endStamp = time() end
    LP.leaveAt = nil
    if LP.partner then LP.Feed("leave", L["Group with %s ended"]:format(LP.partner)) end
    LP.Debug("group", "group with %s ended", LP.partner)
    LP.partner, LP.pickedForPartner, LP.waitTradeClose, LP.partnerSim = nil, false, false, nil
    Touch()
    LP.After(1, LP.TryNext)
end

-- Gruppe verlassen; im Trockenlauf wird das Verlassen nur simuliert (Zustand läuft trotzdem weiter)
-- EIN Danke für alles Trinkgeld, das der Kunde in dieser Sitzung gegeben hat (nur einmal)
function LP.SendThanks(r)
    local f = LP.db.finder
    if not r or r.thanked or not f.thanks or (r.tipTotal or 0) <= 0 then return end
    r.thanked = true
    LP.Debug("trade", "sending the thank-you to %s (total tip %s)", r.name, LP.Money(r.tipTotal))
    LP.Whisper(r.sender or r.name, f.thanksText)
    if not LP.IsDry() then LP.db.stats.thanked = LP.db.stats.thanked + 1 end
end

-- Verlassen nach einer Wartezeit; ein neuer Handel des Kunden bricht es ab (mehrere Kisten nacheinander)
function LP.ScheduleLeave(delay)
    LP.leaveToken = (LP.leaveToken or 0) + 1
    local my = LP.leaveToken
    LP.leaveAt = GetTime() + delay   -- für den Countdown im Verlauf-Feld
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
    LP.leaveToken = (LP.leaveToken or 0) + 1   -- ein noch geplantes Verlassen ist damit erledigt
    LP.leaveAt = nil
    LP.SendThanks(LP.partner and LP.FindRequest(LP.partner))   -- erst bedanken, dann gehen
    LP.Leave()
    if LP.IsDry() then LP.HandleLeave() end
end

-- Ist jemand aus der Anfrageliste in meiner Gruppe? Zwei Wege:
--  1. ich habe ihn eingeladen und er ist beigetreten
--  2. er hat MICH eingeladen (Ankündigung: "ladet mich einfach ein") oder ist anders in die Gruppe gekommen
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
        for _, r in ipairs(LP.requests) do   -- neueste zuerst
            if r.status ~= "grouped" and r.status ~= "done" and r.status ~= "toohigh"
                and GetTime() - r.time < 900 and LP.InGroupWith(r.name) then
                LP.Debug("group", "%s is in your group (they invited you or joined on their own)", r.name)
                LP.HandleJoin(r)
                return true
            end
        end
    end
    -- Niemand aus der Anfrageliste: hat mich ein Unbekannter eingeladen und ich bin beigetreten, ist er mein Kunde
    -- (er hat nichts Erkennbares geschrieben oder gleich eingeladen). Dafür wird eine Anfrage angelegt.
    local inv = LP.lastInviter
    if f.enabled and inv and GetTime() - inv.t < 180 and LP.InGroupWith(inv.name) then   -- Finder an: jeder, der dich einlädt, ist ein Kunde
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
        if LP.partnerSim then return end   -- die Simulation steuert ihren Zustand selbst
        LP.HandleLeave()
    elseif LP.partner then
        -- Kunde weg, ich bin aber noch in einer Gruppe (mehr als 2 Mitglieder)? Nach kurzer Pause prüfen: die Namen kommen verzögert
        if not LP.partnerSim then
            LP.After(2, function()
                if LP.partner and not LP.partnerSim and LP.InGroup() and not LP.InGroupWith(LP.partner) then
                    LP.Debug("group", "%s is no longer in the group", LP.partner)
                    LP.HandleLeave()
                end
            end)
        end
    elseif LP.InGroup() then
        -- die Namen der Gruppenmitglieder sind beim ersten Ereignis manchmal noch nicht da: später nochmal prüfen
        if not LP.CheckRoster() then
            LP.After(1, LP.CheckRoster)
            LP.After(3, LP.CheckRoster)
        end
    else
        LP.After(1, LP.TryNext)
    end
end)

-- Knacken erfolgreich -> ggf. Gruppe verlassen -----------------------------------------------------
function LP.OnPickSuccess(simulated)
    local f = LP.db.finder
    if not simulated then LP.db.stats.picked = LP.db.stats.picked + 1 end
    LP.Debug("pick", "pick success%s (customer: %s)", simulated and " (simulated)" or "", LP.partner)
    LP.Feed("pick", L["Box picked"])
    if LP.partner then
        LP.pickedForPartner = true
        local order = LP.FindRequest(LP.partner)
        if order then order.boxes = (order.boxes or 0) + 1 end   -- Kisten pro Auftrag
        if f.autoLeave then
            if TradeFrame and TradeFrame:IsShown() and not simulated then
                LP.waitTradeClose = true   -- erst Handel abschließen (Trinkgeld/Danke)
                LP.Debug("group", "trade window open: leaving after it closes")
            else
                LP.ScheduleLeave(f.leaveDelay or 10)
            end
        end
    end
    Touch()
end

-- Handel: Trinkgeld erkennen + Danke ------------------------------------------------------------------
local tradeName, tradeTip, tradeStartMoney, tipHandled = nil, 0, 0, false
local lastTrade   -- letzter geschlossener Handel mit Trinkgeld: wartet auf den Geldeingang / die Abschluss-Meldung
LP.On("TRADE_SHOW", function()
    tradeName = (UnitName("NPC")) or (TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText())
    tradeTip, tipHandled = 0, false
    tradeStartMoney = GetMoney and GetMoney() or 0
    LP.Debug("trade", "trade window opened with %s", tradeName)
    if LP.partner then LP.CancelLeave() end   -- der Kunde handelt nochmal (weitere Kiste): nicht gehen
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

-- Trinkgeld des gerade geschlossenen Handels bestätigen, sobald das Geld eingegangen ist
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
        if tradeTip > 0 and tradeName and not tipHandled then
            tipHandled = true   -- die Meldung kam vor dem Schließen des Fensters
            LP.HandleTip(LP.Short(tradeName), tradeTip)
        elseif lastTrade and not lastTrade.done and GetTime() - lastTrade.t < 5 then
            ResolveTip("complete message")   -- die Meldung kam NACH dem Schließen (so in diesem Client)
        end
    elseif LP.db and (LP.db.debug or LP.db.logLive) and msg:lower():find("trade", 1, true) then
        LP.Debug("trade", "info message: %s", msg)   -- hilft, wenn die Abschluss-Meldung in diesem Client anders heißt
    end
end)

-- Trinkgeld erhalten (echter Handel oder Simulation)
function LP.HandleTip(name, tip, simulated)
    local f = LP.db.finder
    LP.Debug("trade", "tip %s from %s%s", LP.Money(tip), name, simulated and " (simulated)" or "")
    LP.Feed("tip", L["Tip from %s: |cffffd100%s|r"]:format(name, LP.Money(tip)))
    if not simulated then LP.db.stats.tips = LP.db.stats.tips + tip end
    local req = LP.FindRequest(name)
    local how   -- für den Hinweis im Toast: "later" = Danke folgt beim Verlassen, "sent" = sofort gesendet
    if f.thanks then
        if req and LP.partner and LP.SameName(req.name, LP.partner) then
            -- Kunde ist noch in der Gruppe (vielleicht kommt noch eine Kiste): Trinkgeld sammeln, EIN Danke beim Verlassen
            req.tipTotal = (req.tipTotal or 0) + tip
            req.thanked = false
            how = "later"
            LP.Debug("trade", "thank-you for %s deferred until the group ends (total tip %s)", name, LP.Money(req.tipTotal))
        else
            LP.Whisper((req and req.sender) or name, f.thanksText)   -- voller Name (Realm), falls bekannt
            if not LP.IsDry() then LP.db.stats.thanked = LP.db.stats.thanked + 1 end
            if req then req.tipTotal = (req.tipTotal or 0) + tip req.thanked = true end   -- auch hier beim Auftrag mitzählen
            how = "sent"
        end
    elseif req then
        req.tipTotal = (req.tipTotal or 0) + tip   -- Danke ist aus: Trinkgeld trotzdem beim Auftrag mitzählen
    end
    LP.Notice("tip", name, tip, how)
    Touch()
end

LP.On("TRADE_CLOSED", function()
    local name, tip, start, handled = tradeName, tradeTip, tradeStartMoney, tipHandled
    tradeName, tradeTip = nil, 0
    LP.Debug("trade", "trade window closed (tip offered %s, already handled: %s)", LP.Money(tip), tostring(handled))
    -- das Geld kommt kurz NACH dem Schließen: mehrfach prüfen (bis 4 s), die Abschluss-Meldung kann es auch auslösen
    if tip > 0 and name and not handled then
        lastTrade = { name = name, tip = tip, start = start, t = GetTime() }
        for _, delay in ipairs({ 0.6, 1.5, 3, 4 }) do
            LP.After(delay, function() ResolveTip("money check") end)
        end
    end
    -- Verlassen planen: nach dem Knacken (waitTradeClose) ODER nach jedem weiteren Handel des Kunden (z.B. nur Trinkgeld),
    -- sonst bliebe Picky nach einem zweiten Handel dauerhaft in der Gruppe
    local f = LP.db.finder
    if LP.partner and f.autoLeave and (LP.waitTradeClose or LP.pickedForPartner) then
        LP.waitTradeClose = false
        LP.Debug("group", "trade closed, leaving soon")
        LP.ScheduleLeave(f.leaveDelay or 10)
    end
end)
-- Der Kunde legt eine Kiste ins Handelsfenster: ist sie zu hoch für dich, sofort sagen (sonst klickst du ins Leere)
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
            if LP.Toast and LP.Toast.Push then LP.Toast.Push({ title = L["Box too high"], line = msg, icon = "Interface\\Icons\\INV_Misc_Key_03" }) end
        end
    end
end)
-- Ankündigung (Handelschat) ---------------------------------------------------------------------------
-- Kanäle: Schlüssel = Name ohne Zusatz ("Handel - Sturmwind" -> "handel"), damit die Wahl in jeder Stadt/Zone gilt
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
-- Ohne eigene Wahl gilt der Namensfilter aus den Einstellungen (Handel/Trade)
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
    if type(ad.channels) ~= "table" then   -- erste Wahl: mit dem bisherigen Filter starten
        ad.channels = {}
        for _, ch in ipairs(LP.ChannelList()) do
            if LP.AdChannelOn(ch) then ad.channels[ch.key] = true end
        end
    end
    ad.channels[key] = on and true or nil
    -- Namensteile des alten Filters bleiben vorgemerkt, auch wenn der Kanal gerade fehlt (z.B. Handel außerhalb der Stadt)
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
        if LP.AdChannelOn(ch) and LP.SendChannel(text, ch.id) then sent = sent + 1 end   -- nur gelungene Sendungen zählen
    end
    if sent > 0 then
        if LP.IsDry() then
            -- Trockenlauf: nichts wurde wirklich gesendet, das muss die Meldung auch sagen
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
        LP.nextAdAt = GetTime() + wait()   -- für den Countdown auf der Anfragen-Seite
        LP.After(wait(), tick)
    end
    LP.nextAdAt = GetTime() + wait()
    LP.After(wait(), tick)
end

-- Automatische Ankündigung abbrechen (das x auf der Anfragen-Seite); wieder einschalten: Einstellungen, Ankündigung
function LP.CancelAutoAd()
    LP.db.ad.auto = false
    LP.nextAdAt = nil
    LP.Debug("chat", "automatic announcement cancelled")
    if LP.RefreshAll then LP.RefreshAll() end
end

-- Simulationen (Debug-Seite) ------------------------------------------------------------------------
-- Alle laufen als Trockenlauf: es wird nichts wirklich eingeladen, geflüstert oder verlassen.
local function Dry(fn)
    local old = LP.forceDry
    LP.forceDry = true
    local ok, a = pcall(fn)
    LP.forceDry = old
    if not ok then LP.Debug("sim", "simulation error: %s", a) end
    return a
end

-- Chat-Nachricht eines erfundenen Spielers durch die echte Erkennung schicken
function LP.SimulateChat(msg, whisper)
    simCount = simCount + 1
    local name = "Testplayer" .. simCount
    LP.Debug("sim", "simulating %s from %s: %s", whisper and "a whisper" or "public chat", name, msg)
    return Dry(function()
        return LP.OnChat(whisper and "CHAT_MSG_WHISPER" or "CHAT_MSG_CHANNEL", msg, name, true)
    end)
end

-- Der eingeladene (oder nächste wartende) Spieler tritt der Gruppe bei
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


-- Aufträge: dauerhaft speichern, laden, ablaufen lassen, löschen -----------------------------------------------
-- LP.requests ist nach dem Laden LP.db.orders: alles bleibt über /reload und Neustart erhalten, bis DU es löschst.
-- r.time ist eine GetTime()-Zeit und gilt nur in dieser Sitzung: aus dem gespeicherten Zeitstempel (Epoche) neu berechnen.
local OPEN_EXPIRE = 900   -- offene Anfragen, die älter als 15 Minuten sind, werden zu "keine Antwort"
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
                r.status = "timeout"   -- die Einladung von damals ist nicht mehr gültig
            elseif (r.status == "new" or r.status == "manual" or r.status == "queued") and age > OPEN_EXPIRE then
                r.status = "timeout"
            end
        end
    end
    LP.requests = orders
end

-- Zu alte offene Anfragen (neu/manuell/wartend) laufen ab und wandern nach "Erledigt"
function LP.ExpireOpen()
    local now = GetTime()
    local changed = false
    for _, r in ipairs(LP.requests) do
        if (r.status == "new" or r.status == "manual" or r.status == "queued") and now - r.time > OPEN_EXPIRE then
            r.status = "timeout"
            changed = true
        end
    end
    if changed then Touch() end
end

-- Auftrag löschen / alle erledigten löschen (nur auf deinen Klick)
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

-- Gruppe sofort verlassen (Knopf "Gehen" im Verlauf-Feld): erst bedanken (falls Trinkgeld da war), dann gehen
function LP.LeaveNow()
    if not LP.partner then return end
    LP.Debug("group", "manual leave requested")
    LP.DoLeave()
end

-- Nach /reload mitten in einem Kunden: Gruppe wiedererkennen, sonst den Auftrag als erledigt abschließen
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