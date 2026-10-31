-- Online directory is independent of roster identity/lifecycle state.
local MultiBot = _G.MultiBot
if not MultiBot then return end
local D = { sequence = 0 }
MultiBot.RandomBotDirectory = D
local function split(value)
    local fields = {}
    for field in string.gmatch((value or "") .. "~", "(.-)~") do fields[#fields + 1] = field end
    return fields
end
local function integer(value, low, high)
    if type(value) ~= "string" or not string.match(value, "^%d+$") then return nil end
    local number = tonumber(value)
    if not number or number < low or number > high then return nil end
    return number
end
local function encode(value)
    return (string.gsub(value, "([^%w%-_%.])", function(c) return string.format("%%%02X", string.byte(c)) end))
end
local function decode(value, maxLength, allowEmpty)
    if not value or string.find(string.gsub(value, "%%[0-9a-fA-F][0-9a-fA-F]", ""), "%%") then return nil end
    value = string.gsub(value, "%%([0-9a-fA-F][0-9a-fA-F])", function(hex) return string.char(tonumber(hex, 16)) end)
    if (not allowEmpty and #value < 1) or #value > (maxLength or 48) or string.find(value, "[%c|~]") then return nil end
    return value
end
local function finish(result, reason)
    local pending = D.pending
    D.pending = nil
    if pending and pending.callback then pending.callback(result, reason) end
end
function D.Cancel(reason)
    if reason then finish(nil, reason) else D.pending = nil end
end
function D.Request(query, callback)
    if not MultiBot.bridge or not MultiBot.bridge.connected or not MultiBot.bridge.randomBotDirectoryCapable then
        callback(nil, "UNAVAILABLE")
        return false
    end
    if D.pending then callback(nil, "BUSY"); return false end
    local now = GetTime()
    if D.lastSent and now - D.lastSent < 3 then callback(nil, "RATE_LIMIT"); return false end
    D.sequence = D.sequence + 1
    local token = "rbd" .. math.floor(now * 1000) .. "_" .. D.sequence
    local fields = { "RANDOMBOT_DIRECTORY", token, encode(query.name or ""), query.class or 0,
        query.minLevel or 1, query.maxLevel or 80, query.faction or 0, query.status or 0,
        query.invite or 0, query.page or 0, query.sort or "NAME", query.descending and 1 or 0, "ANY" }
    local payload = table.concat(fields, "~")
    if #(MultiBot.Comm.prefix .. "\tGET~" .. payload) > 255 then callback(nil, "TOO_LARGE"); return false end
    D.pending = { token = token, callback = callback, page = query.page or 0,
        generation = MultiBot.bridge.connectionGeneration, rows = {}, seen = {} }
    D.lastSent = now
    if not MultiBot.Comm.Send("GET", payload) then finish(nil, "DISCONNECTED"); return false end
    MultiBot.TimerAfter(12, function()
        if D.pending and D.pending.token == token then finish(nil, "TIMEOUT") end
    end)
    return true
end
function D.HandlePacket(opcode, payload)
    if opcode ~= "RBD_BEGIN" and opcode ~= "RBD_ENTRY" and opcode ~= "RBD_END" and opcode ~= "ERR" then return false end
    local f = split(payload)
    local p = D.pending
    if opcode == "ERR" then
        if f[2] ~= "RANDOMBOT_DIRECTORY" then return false end
        if p and f[3] == p.token then finish(nil, f[4] or "BAD_RESPONSE") end
        return true
    end
    if not p or f[1] ~= p.token then return true end
    if p.generation ~= MultiBot.bridge.connectionGeneration then finish(nil, "DISCONNECTED"); return true end
    if #(payload or "") > 255 then finish(nil, "BAD_RESPONSE"); return true end
    if opcode == "RBD_BEGIN" or opcode == "RBD_END" then
        local page, total, count = integer(f[2], 0, 100000), integer(f[3], 0, 1000000), integer(f[4], 0, 25)
        if #f ~= 5 or page ~= p.page or not total or not count or f[5] ~= "ONLINE_ONLY"
            or count ~= math.min(25, math.max(0, total - page * 25)) then
            finish(nil, "BAD_RESPONSE"); return true
        end
        if opcode == "RBD_BEGIN" then
            if p.total then finish(nil, "BAD_RESPONSE"); return true end
            p.total, p.count, p.framing = total, count, payload
        elseif p.framing ~= payload or #p.rows ~= count then
            finish(nil, "BAD_RESPONSE")
        else
            finish({ rows = p.rows, total = total, page = page })
        end
        return true
    end
    local guid = integer(f[2], 1, 4294967295)
    local name = decode(f[3])
    local class, level, race = integer(f[4], 1, 11), integer(f[5], 1, 80), integer(f[6], 1, 11)
    local faction, zone = integer(f[7], 1, 2), integer(f[10], 0, 4294967295)
    local grouped, controlled = integer(f[11], 0, 1), integer(f[12], 0, 1)
    local zoneName = decode(f[14], 128, true)
    if #f ~= 14 or zoneName == nil or not p.count or #p.rows >= p.count or not guid or p.seen[guid] or not name
        or not class or class == 10 or not level or not race or not faction or not zone
        or not grouped or not controlled or f[8] ~= "UNKNOWN" or f[9] ~= "ONLINE"
        or not string.match(f[13] or "", "^[A-Z_]+$") or #f[13] > 32 then
        finish(nil, "BAD_RESPONSE"); return true
    end
    p.seen[guid] = true
    p.rows[#p.rows + 1] = { guid = guid, name = name, class = class, level = level, race = race,
        faction = faction, zone = zone, zoneName = zoneName ~= "" and zoneName or nil, grouped = grouped == 1, controlled = controlled == 1, reason = f[13] }
    return true
end
