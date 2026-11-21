-- Picky / State.lua : EIN Zustand und EIN Ereignispunkt für alle Anzeigen
-- (Hauptfenster, Mini-Liste, Toast, Minimap-Button). Die Logik (Finder.lua) meldet hierher,
-- die Anzeigen lesen von hier. So bleibt alles gleich, auch wenn das Fenster geschlossen ist.
local ADDON, LP = ...
local L = LP.L

-- Anfragen, die noch "offen" sind (alles andere ist erledigt oder abgelehnt)
LP.OPEN_STATUS = { new = true, manual = true, queued = true, invited = true, grouped = true }

-- Verlauf: kurze, lesbare Ereignisse für das Verlauf-Feld (Feed.lua). kind bestimmt die Farbe.
LP.feed = {}
local FEED_MAX = 50
function LP.Feed(kind, text)
    local f = LP.feed
    f[#f + 1] = { t = GetTime(), clock = date("%H:%M"), kind = kind, text = text }
    while #f > FEED_MAX do table.remove(f, 1) end
    LP.Debug("ui", "feed [%s] %s", kind, text)
end

function LP.Mmss(sec)
    sec = math.max(0, math.floor(sec or 0))
    return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

-- Aktueller Zustand: { on, phase = "idle"|"invited"|"grouped", current, waiting, waitingNames, open, picked, tips }
function LP.GetState()
    local db = LP.db
    local st = { on = db and db.finder.enabled or false, phase = "idle", waiting = 0, waitingNames = {}, open = 0 }
    for i = #LP.requests, 1, -1 do   -- älteste zuerst
        local r = LP.requests[i]
        if r.status == "queued" then
            st.waiting = st.waiting + 1
            st.waitingNames[#st.waitingNames + 1] = r.name
        end
        if LP.OPEN_STATUS[r.status] then st.open = st.open + 1 end
    end
    local cur = LP.partner and LP.FindRequest(LP.partner)
    if cur and cur.status == "grouped" then
        st.phase, st.current = "grouped", cur
    elseif LP.pending and LP.pending.status == "invited" then
        st.phase, st.current = "invited", LP.pending
    end
    if db then st.picked, st.tips = db.stats.picked, db.stats.tips end
    return st
end

-- Die älteste Anfrage, die noch auf eine Einladung wartet (neu / manuell / in der Warteschlange).
-- Zu hohe Skill-Anforderung, schon eingeladene oder erledigte Anfragen zählen nicht.
local INVITABLE = { new = true, manual = true, queued = true }
function LP.NextInvitable()
    for i = #LP.requests, 1, -1 do   -- älteste zuerst
        local r = LP.requests[i]
        if INVITABLE[r.status] then return r end
    end
end

-- Alle Anzeigen auffrischen (jede prüft selbst, ob sie überhaupt sichtbar ist)
function LP.RefreshAll()
    if LP.RefreshUI then pcall(LP.RefreshUI) end
    if LP.UpdateMinimapState then pcall(LP.UpdateMinimapState) end
end

function LP.SetFinder(on, silent)
    LP.db.finder.enabled = on and true or false
    LP.Feed("finder", LP.db.finder.enabled and L["On duty"] or L["Off duty"])
    if not silent then
        LP.Print(L["Duty: "] .. (LP.db.finder.enabled and ("|cff4de88a" .. L["ON"] .. "|r") or ("|cffff5959" .. L["OFF"] .. "|r")))
    end
    if LP.db.finder.enabled and LP.TryNext then LP.TryNext() end
    LP.RefreshAll()
end

local function PlayAlert()
    local snd = SOUNDKIT and SOUNDKIT.TELL_MESSAGE
    pcall(PlaySound, snd or "TellMessage")
end

-- Ereignisse: "request" (neue Anfrage), "joined" (Kunde in der Gruppe), "tip" (Trinkgeld)
function LP.Notice(kind, a, b, c)
    local db = LP.db
    if not db then return end
    LP.Debug("ui", "notice: %s %s", kind, a and (type(a) == "table" and a.name or a) or "")
    local ui, f = db.ui, db.finder
    if kind == "request" then
        local req = a
        if f.sound then PlayAlert() end
        if ui.flash and FlashClientIcon then pcall(FlashClientIcon) end
        if ui.chatLine then
            LP.Print(L["New request from |cffffd100%s|r"]:format(req.name) .. (req.label and (" [" .. req.label .. "]") or ""))
        end
        if ui.toast and LP.Toast then LP.Toast.Request(req) end
    elseif kind == "joined" then
        if ui.toast and LP.Toast then LP.Toast.Joined(a) end
    elseif kind == "tip" then
        if ui.toast and LP.Toast then LP.Toast.Tip(a, b, c) end
        -- ohne Toast bleibt wenigstens eine Chatzeile als Beleg
        if (ui.chatLine or not ui.toast) and not LP.forceDry then   -- bei Simulationen/Tests keine Chatzeile
            LP.Print(L["Tip from %s: |cffffd100%s|r"]:format(tostring(a), LP.Money(b)))
        end
    end
    LP.RefreshAll()
end

LP.On("PLAYER_ENTERING_WORLD", function() LP.RefreshAll() end)
