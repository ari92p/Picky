#!/usr/bin/env python3
"""Mutation test for Picky: puts one deliberate bug at a time into a COPY of the addon and checks that the self tests catch it.

    python3 tools/mutate.py            run every mutation
    python3 tools/mutate.py -v         also show which test caught each one
    python3 tools/mutate.py NAME ...   run only mutations whose name contains one of the words

A mutation that is not caught ("SURVIVED") means: the tests do not notice this bug. Add a test (or, if the change does not change
the behaviour at all, remove or rephrase the mutation). A mutation whose text is no longer in the source ("STALE") must be updated.
Needs luajit (brew install luajit). The real files are never touched.
"""
import os, re, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = [f for f in os.listdir(ROOT) if f.endswith(".lua") or f == "Picky.toc"]

# (name, file, old text (must exist exactly once), new text)
M = [
    # --- chat detection: the decision itself
    ("public: an advertisement is no request", "Finder.lua", "and not excl and not isAd", "and not excl"),
    ("public: a sale / group search is no request", "Finder.lua", "and not excl and not isAd", "and not isAd"),
    ("public: asking needs an open/pick word", "Finder.lua", "(rogue or (seek and act))", "(rogue or seek)"),
    ("public: a box or an open word is needed", "Finder.lua", "(lock or (verb and rogue)) and", "(lock or verb or rogue) and"),
    ("whisper: a box is enough", "Finder.lua", "ok = lock or (verb and (rogue or seek)) or (rogue and seek)", "ok = (verb and (rogue or seek)) or (rogue and seek)"),
    ("whisper: open + request", "Finder.lua", "(verb and (rogue or seek)) or (rogue and seek)", "(verb and rogue) or (rogue and seek)"),
    ("explicit skill: lower bound", "Finder.lua", "n >= 20 and n <= 300", "n >= 1 and n <= 300"),
    ("explicit skill: upper bound", "Finder.lua", "n >= 20 and n <= 300", "n >= 20 and n <= 9999"),
    ("explicit skill: higher number wins", "Finder.lua", "(not best or n > best)", "(not best or n < best)"),
    ("ad: spell link", "Finder.lua", 'msg:find("|Hspell:" .. tostring(LP.PICK_SPELL_ID), 1, true) ~= nil or ', ""),
    ("ad: unconditional offer words", "Finder.lua", "or HasTok(s, AD_TOK) or HasSub(s, AD_SUB)", "or HasSub(s, AD_SUB)"),
    ("ad: phrases", "Finder.lua", "or HasTok(s, AD_TOK) or HasSub(s, AD_SUB)", "or HasTok(s, AD_TOK)"),
    ("ad: contact phrases need 'nobody asked'", "Finder.lua", "(not seek and (HasSub(s, CONTACT_SUB)", "((HasSub(s, CONTACT_SUB)"),
    ("ad: soft words only when nobody asked", "Finder.lua", "or HasTok(s, AD_SOFT_TOK) or HasSub(s, AD_SOFT_SUB)))", "))"),
    ("ad: soft words count when somebody asks", "Finder.lua", "(not seek and (HasSub(s, CONTACT_SUB) or HasSub(s, AD_NOSEEK) or HasTok(s, AD_SOFT_TOK)", "((HasSub(s, CONTACT_SUB) or HasSub(s, AD_NOSEEK) or HasTok(s, AD_SOFT_TOK)"),
    ("ad: a rogue naming his own skill", "Finder.lua", "or (not seek and rogue and ExplicitSkill(s) ~= nil)", ""),
    ("ad: his own skill needs 'nobody asked'", "Finder.lua", "(not seek and rogue and ExplicitSkill(s) ~= nil)", "(rogue and ExplicitSkill(s) ~= nil)"),
    ("ad word: lfw", "Finder.lua", '"anbieten", "lfw" }', '"anbieten" }'),
    ("ad word: umsonst", "Finder.lua", '"kostenlos", "gratis", "umsonst" }', '"kostenlos", "gratis" }'),
    ("ad word: free", "Finder.lua", '{ "free", "available", "service", "services", "hire" }', '{ "available", "service", "services", "hire" }'),
    ("ad phrase: tips welcome", "Finder.lua", '"tips welcome", ', ""),
    ("ad phrase: rogue here", "Finder.lua", '"rogue here", ', ""),
    ("ad phrase: pm me", "Finder.lua", '"pm me", ', ""),
    ("ad phrase: looking for work", "Finder.lua", '"looking for work", "for hire"', '"for hire"'),
    ("seek word: any", "Finder.lua", '"wanted", "any" }', '"wanted" }'),
    ("seek word: jemand", "Finder.lua", '"wer", "jemand",', '"wer",'),
    ("exclude word: wts", "Finder.lua", '"wts", ', ""),
    ("exclude word: where", "Finder.lua", '"where", "wo",', '"wo",'),
    ("keyword hint: chest typos", "Finder.lua", "or ChestLike(s)", ""),
    ("keyword estimates are used", "Finder.lua", "if not req and hint then", "if false then"),
    ("item links give the exact value", "Finder.lua", "if b and (not req or b[1] > req) then req, label = b[1], LP.BoxName(id) end", "if b and not req then req, label = b[1], LP.BoxName(id) end"),
    ("several item links: the highest", "Finder.lua", "(not req or b[1] > req)", "(not req or b[1] < req)"),
    ("keywords: the highest estimate", "Finder.lua", "(not req or k[2] > req)", "(not req or k[2] < req)"),
    # --- a request split into several messages
    ("split: window too long", "Finder.lua", "local MSG_WINDOW = 5", "local MSG_WINDOW = 60"),
    ("split: window too short", "Finder.lua", "local MSG_WINDOW = 5", "local MSG_WINDOW = 1"),
    ("split: too few parts are kept", "Finder.lua", "local MSG_MAX = 4", "local MSG_MAX = 1"),
    ("split: too many parts are kept", "Finder.lua", "local MSG_MAX = 4", "local MSG_MAX = 100"),
    ("split: parts are used up by the request", "Finder.lua", "                kept = {}\n                LP.Debug", "                LP.Debug"),
    ("split: only the same player", "Finder.lua", "local k = (LP.Short(name) or name):lower()\n        local t0", 'local k = "everyone"\n        local t0'),
    ("split: the combination uses the strict rules", "Finder.lua", "Analyze(table.concat(parts, \" \"), false)", "Analyze(table.concat(parts, \" \"), true)"),
    ("split: sale and advertisement words are kept as vetoes", "Finder.lua", "why.seek or why.excl or why.ad) then\n            -- keep fragments", "why.seek) then\n            -- keep fragments"),
    ("split: chatter is not stored", "Finder.lua", "if not ok and (why.lock or why.verb or why.rogue or why.seek or why.excl or why.ad) then", "if not ok then"),
    ("split: old players are forgotten", "Finder.lua", "if t0 - list[#list].t > MSG_WINDOW then LP.recentMsgs[key] = nil end", ""),
    ("split: old parts are dropped", "Finder.lua", "if t0 - e.t <= MSG_WINDOW then kept[#kept + 1] = e end", "kept[#kept + 1] = e"),
    # (not listed: the order of the parts does not matter, the rules look at the words, so a different order is not a different behaviour)
    # --- reading and advertising channels
    ("channels: new channels are read by default", "Finder.lua", "return not (off and off[key])", "return off ~= nil and off[key] == nil"),
    ("channels: a switched-off channel stays off", "Finder.lua", "f.readOff[key] = (not on) and true or nil", "f.readOff[key] = nil"),
    # (not listed: the early "whispers are always read" return in ChatAllowed is a second safeguard; without it a whisper has no key and is read anyway)
    ("channels: say key", "Finder.lua", 'if event == "CHAT_MSG_SAY" then return "say" end', ""),
    ("channels: guild key", "Finder.lua", 'if event == "CHAT_MSG_GUILD" then return "guild" end', ""),
    ("channels: the local trade channel is not a default", "Finder.lua", 'if l:find("lokal", 1, true) or l:find("local", 1, true) then return false end', ""),
    ("channels: key without the zone part", "Finder.lua", '"%s*%-.*$"', '"%s*X.*$"'),
    ("announce: 60 second pause", "Finder.lua", "now - LP.lastAd < 60", "now - LP.lastAd < 0"),
    ("announce: guild is opt-in", "Finder.lua", 'return type(ad.channels) == "table" and ad.channels.guild == true', "return true"),
    ("menus: the guild only inside a guild", "Finder.lua", "if LP.InGuild() then list[#list + 1] = { key = \"guild\", label = L[\"Guild\"] } end\n    for _, ch in ipairs(LP.ChannelList()) do list[#list + 1] = { key = ch.key, label = ch.id", "list[#list + 1] = { key = \"guild\", label = L[\"Guild\"] }\n    for _, ch in ipairs(LP.ChannelList()) do list[#list + 1] = { key = ch.key, label = ch.id"),
    # --- decisions about a request
    ("decide: too high a skill is refused", "Finder.lua", "if req.req and req.req > skill then", "if false then"),
    ("decide: exactly enough skill is fine", "Finder.lua", "if req.req and req.req > skill then", "if req.req and req.req >= skill then"),
    ("decide: unknown box waits", "Finder.lua", "if not req.req and not f.inviteUnknown then", "if false then"),
    ("decide: auto invite off waits for a click", "Finder.lua", "if not f.autoInvite then", "if false then"),
    ("decide: busy group queues", "Finder.lua", "if (LP.InGroup() or LP.pending) and f.onlyWhenFree then", "if false then"),
    ("invite: a full group queues", "Finder.lua", "if LP.GroupCount() >= 5 then", "if LP.GroupCount() >= 50 then"),
    ("orders: open requests expire", "Finder.lua", "local OPEN_EXPIRE = 900", "local OPEN_EXPIRE = 900000"),
    ("pick: grace period", "Pick.lua", "local PICK_GRACE = 3", "local PICK_GRACE = 0"),
    # --- state, invites, thanks, orders
    ("state: oldest waiting request first", "State.lua", "function LP.NextInvitable()\n    for i = #LP.requests, 1, -1 do   -- oldest first", "function LP.NextInvitable()\n    for i = 1, #LP.requests do   -- oldest first"),
    ("state: only waiting requests can be invited", "State.lua", "local INVITABLE = { new = true, manual = true, queued = true }", "local INVITABLE = { new = true, manual = true, queued = true, toohigh = true }"),
    ("auto accept: needs the setting", "Finder.lua", "if not f or not f.enabled or not f.autoAccept then return false", "if not f or not f.enabled then return false"),
    ("auto accept: duty has to be on", "Finder.lua", "if not f or not f.enabled or not f.autoAccept then return false", "if not f or not f.autoAccept then return false"),
    ("auto accept: not while in a group", "Finder.lua", "if LP.InGroup() then return false, \"already in a group\" end", ""),
    ("auto accept: ignored players are refused", "Finder.lua", "if LP.IsIgnored(short) then return false, \"ignored player\" end", ""),
    ("thanks: only once", "Finder.lua", "if not r or r.thanked or not f.thanks or (r.tipTotal or 0) <= 0 then return end", "if not r or not f.thanks or (r.tipTotal or 0) <= 0 then return end"),
    ("thanks: only with a tip", "Finder.lua", "if not r or r.thanked or not f.thanks or (r.tipTotal or 0) <= 0 then return end", "if not r or r.thanked or not f.thanks then return end"),
    ("thanks: only when switched on", "Finder.lua", "if not r or r.thanked or not f.thanks or (r.tipTotal or 0) <= 0 then return end", "if not r or r.thanked or (r.tipTotal or 0) <= 0 then return end"),
    ("thanks: thanked count", "Finder.lua", "if not LP.IsDry() then LP.db.stats.thanked = LP.db.stats.thanked + 1 end\nend", "end"),
    ("tips: counted in the statistics", "Finder.lua", "if not simulated then LP.db.stats.tips = LP.db.stats.tips + tip end", ""),
    ("tips: a tip in the group is collected, not thanked at once", "Finder.lua", "req.tipTotal = (req.tipTotal or 0) + tip\n            req.thanked = false", "req.tipTotal = (req.tipTotal or 0)\n            req.thanked = false"),
    ("tips: still counted on the order when thanks is off", "Finder.lua", "req.tipTotal = (req.tipTotal or 0) + tip   -- thanks is off: still count the tip on the order", ""),
    ("orders: open requests that are old move to done", "Finder.lua", 'if (r.status == "new" or r.status == "manual" or r.status == "queued") and now - r.time > OPEN_EXPIRE then', 'if false then'),
    ("orders: a trade without joining is accepted", "Finder.lua", 'r.status = "done"\n    r.endStamp = time()\n    r.tradedWithoutGroup = true', 'r.endStamp = time()\n    r.tradedWithoutGroup = true'),
    ("invites: counted in the statistics", "Finder.lua", "if not LP.IsDry() then LP.db.stats.invited = LP.db.stats.invited + 1 end", ""),
    ("picked: counted in the statistics", "Finder.lua", "if not simulated then LP.db.stats.picked = LP.db.stats.picked + 1 end", ""),
    # --- helpers
    ("money: gold part", "Core.lua", 'if g > 0 then t[#t + 1] = g .. "g" end', ""),
    ("money: nothing is 0g", "Core.lua", 't[1] = "0g"', 't[1] = "0k"'),
    ("names: two part names must match", "Core.lua", "if ra ~= \"\" and rb ~= \"\" then return ra == rb end", ""),
    ("names: first names must match", "Core.lua", 'if fa == "" or fa ~= fb then return false end', ""),
    ("skill: estimate from the level", "Core.lua", 'math.min(300, LP.Game.UnitLevel() * 5)', 'math.min(300, LP.Game.UnitLevel() * 4)'),
    ("skill: stored skill not for a character without Pick Lock", "Core.lua", "and LP.PickLockKnown() ~= false then", "then"),
    ("skill: not learned means 0", "Core.lua", "if LP.PickLockKnown() == false then", "if false then"),
    ("merge: stats are summed", "Core.lua", "(tonumber(db.stats[name]) or 0) + (tonumber(c.stats[name]) or 0)", "(tonumber(c.stats[name]) or 0)"),
    ("merge: orders newest first", "Core.lua", "if sx ~= sy then return sx > sy end", "if sx ~= sy then return sx < sy end"),
    ("merge: the per-character table is removed", "Core.lua", "db.chars = nil\n", "\n"),
    ("merge: the highest skill", "Core.lua", "if (tonumber(c.skillBase) or 0) > (tonumber(db.skillBase) or 0) then db.skillBase = c.skillBase end", ""),
    ("defaults: wait before leaving", "Core.lua", "leaveDelay = 5,", "leaveDelay = 10,"),
    ("defaults: auto invite is off", "Core.lua", "autoInvite = false,", "autoInvite = true,"),
    ("defaults: invite unknown is off", "Core.lua", "inviteUnknown = false,", "inviteUnknown = true,"),
    # --- data
    ("data: thorium lockbox", "Data.lua", '[5759]  = { 225,', '[5759]  = { 250,'),
    ("data: battered chest has no requirement", "Data.lua", '[6356]  = { 1, ', '[6356]  = { 70,'),
    ("data: ornate bronze lockbox", "Data.lua", '[4632]  = { 1, ', '[4632]  = { 25,'),
    ("data: iron keyword is a whole word", "Data.lua", '{ "%f[%a]iron%f[%A]", 125, L["Iron box"], true }', '{ "iron", 125, L["Iron box"] }'),
    ("data: thorium keyword", "Data.lua", '{ "thorium", 225,', '{ "thorium", 250,'),
    ("data: stage 2 level requirement", "Data.lua", "from = 100, to = 150, title = \"100 - 150\", levelReq = 30", "from = 100, to = 150, title = \"100 - 150\", levelReq = 25"),
    ("data: Alliance start spot", "Data.lua", 'faction = "A", best = true, where = L["Alther\'s Mill"]', 'faction = "H", best = true, where = L["Alther\'s Mill"]'),
    ("data: level cap advice threshold", "Data.lua", "if skill >= level * 5 then", "if skill > level * 5 then"),
    ("data: level cap advice next level", "Data.lua", "math.ceil((skill + 1) / 5)", "math.ceil(skill / 5)"),
    ("data: reach uses 5 x level", "Data.lua", "(tonumber(level) or 1) * 5)", "(tonumber(level) or 1) * 4)"),
    ("data: reach is limited by the rank", "Data.lua", "math.min(rank, cap)", "cap"),
    ("data: guide stage borders", "Data.lua", "from = 100, to = 150", "from = 100, to = 160"),
]


def run(tmp, verbose):
    p = subprocess.run(["luajit", "tools/run_tests.lua"], cwd=tmp, capture_output=True, text=True, timeout=120)
    out = (p.stdout or "") + (p.stderr or "")
    return p.returncode, out


def main():
    verbose = "-v" in sys.argv
    words = [a for a in sys.argv[1:] if not a.startswith("-")]
    if shutil.which("luajit") is None:
        print("luajit is missing: brew install luajit")
        return 2
    code, out = run(ROOT, verbose)
    if code != 0:
        print("The unchanged addon does not pass its own tests. Fix that first:\n" + out[:1500])
        return 2
    sources = {f: open(os.path.join(ROOT, f), encoding="utf-8").read() for f in FILES}
    survived, stale, killed = [], [], 0
    todo = [m for m in M if not words or any(w.lower() in m[0].lower() for w in words)]
    for name, fname, old, new in todo:
        src = sources.get(fname)
        n = src.count(old) if src is not None else 0
        if n != 1:
            stale.append((name, fname, n))
            continue
        tmp = tempfile.mkdtemp(prefix="picky-mut-")
        try:
            for f in FILES:
                shutil.copy(os.path.join(ROOT, f), tmp)
            shutil.copytree(os.path.join(ROOT, "tools"), os.path.join(tmp, "tools"))
            with open(os.path.join(tmp, fname), "w", encoding="utf-8") as fh:
                fh.write(src.replace(old, new, 1))
            code, out = run(tmp, verbose)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        if code == 0:
            survived.append(name)
            print("SURVIVED  " + name)
        else:
            killed += 1
            if verbose:
                first = next((l for l in out.splitlines() if l.startswith(("FAIL", "ERROR", "SYNTAX"))), out.splitlines()[0] if out else "")
                print("killed    %s  <- %s" % (name, first[:110]))
    for name, fname, n in stale:
        print("STALE     %s  (%s: text found %d times, must be exactly once)" % (name, fname, n))
    print("\n%d mutations: %d caught, %d survived, %d stale" % (len(todo), killed, len(survived), len(stale)))
    return 0 if not survived and not stale else 1


if __name__ == "__main__":
    sys.exit(main())
