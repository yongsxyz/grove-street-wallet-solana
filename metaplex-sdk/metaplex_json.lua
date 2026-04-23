-- https://github.com/yongsxyz
--[[
    Metaplex SDK - JSON encoder.

    MTA's built-in `toJSON` wraps root tables in a literal `[ ... ]` array
    — a long-standing quirk. For endpoints that expect a clean JSON object
    (Pinata `pinJSONToIPFS`, ERC-8004 registration documents, etc.), the
    wrapper corrupts the payload: Pinata stores an array, not an object.

    This module is a small, strict JSON encoder we fully control:
      * Tables with sequential integer keys starting at 1 → JSON array
      * Tables with any string keys (or empty)             → JSON object
      * Empty tables default to JSON array `[]` (matches how Lua usage
        tends to mean "empty list"). To force an empty object, pass
        `MetaplexJson.emptyObject` instead of `{}`.
      * Strings are UTF-8 passed through with basic control-char escaping.
]]

local floor = math.floor

MetaplexJson = {}

-- Sentinel a caller can return from opts fields that should be an EMPTY
-- OBJECT (rather than our default, which serialises {} to []).
MetaplexJson.emptyObject = setmetatable({}, { __metatable = "MetaplexJson.emptyObject" })

local function isEmptyObjectSentinel(t)
    return getmetatable(t) == "MetaplexJson.emptyObject"
end

local function isArrayLike(t)
    if isEmptyObjectSentinel(t) then return false end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    if n == 0 then return true end  -- empty table → []
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true
end

local function escape(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    s = s:gsub("\b", "\\b")
    s = s:gsub("\f", "\\f")
    -- Strip or escape remaining control chars (< 0x20)
    s = s:gsub("[%z\1-\31]", function(c)
        return string.format("\\u%04x", string.byte(c))
    end)
    return s
end

local function encodeValue(v)
    local t = type(v)
    if t == "nil" then return "null" end
    if t == "boolean" then return v and "true" or "false" end
    if t == "number" then
        if v ~= v then return "null" end          -- NaN
        if v == math.huge or v == -math.huge then return "null" end
        -- Integer-ish? Print without trailing `.0`.
        if v == floor(v) and v > -1e15 and v < 1e15 then
            return tostring(floor(v))
        end
        return tostring(v)
    end
    if t == "string" then return '"' .. escape(v) .. '"' end
    if t == "table" then
        if isEmptyObjectSentinel(v) then return "{}" end
        if isArrayLike(v) then
            local parts = {}
            for i = 1, #v do parts[#parts + 1] = encodeValue(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local parts = {}
        for k, val in pairs(v) do
            parts[#parts + 1] = '"' .. escape(k) .. '":' .. encodeValue(val)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

function MetaplexJson.encode(value)
    return encodeValue(value)
end

-- Ordered object encoder. Accepts a list of {key, value} pairs and emits
-- them in the order given. Useful when you want predictable field order
-- in the output (e.g. matching the ERC-8004 spec example).
function MetaplexJson.encodeOrdered(pairs_)
    local parts = {}
    for _, kv in ipairs(pairs_) do
        parts[#parts + 1] = '"' .. escape(kv[1]) .. '":' .. encodeValue(kv[2])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end
