-- Load the real minimap-library dependency chain in TOC order, with no other addon preloading it.
strmatch = string.match
CreateFrame = function()
    return { SetScript = function() end, RegisterEvent = function() end }
end
local required = {
    ["Libs/LibStub/LibStub.lua"] = true,
    ["Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua"] = true,
    ["Libs/libdatabroker-1-1/LibDataBroker-1.1.lua"] = true,
    ["Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua"] = true,
}
local count = 0
for line in io.lines("MultiBot.toc") do
    local path = string.gsub(line, "\\", "/")
    path = string.gsub(path, "\r$", "")
    if required[path] then
        assert(loadfile(path))()
        count = count + 1
    end
end
assert(count == 4, "Missing minimap library in TOC")
assert(LibStub("LibDataBroker-1.1"))
assert(LibStub("LibDBIcon-1.0"))
print("PASS: real minimap libraries load in TOC order without other addons")
