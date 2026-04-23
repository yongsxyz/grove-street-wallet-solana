-- https://github.com/yongsxyz
--[[
    Metaplex SDK - Borsh-style writers used for Token Metadata instructions.

    All multi-byte integers are little-endian.
    string / option / vec follow Umi's @metaplex-foundation/umi/serializers
    defaults:
        string  -> u32 LE byte length + UTF-8 bytes
        option  -> u8 tag (0 = none, 1 = some) + value if some
        vec     -> u32 LE element count + items
]]

local floor = math.floor

MetaplexBorsh = {}

-- A "writer" is just a table of bytes that we keep appending to.
function MetaplexBorsh.newWriter()
    return { bytes = {} }
end

local function pushByte(w, b)
    w.bytes[#w.bytes + 1] = b
end

local function pushBytes(w, src)
    local n = #w.bytes
    for i = 1, #src do w.bytes[n + i] = src[i] end
end

function MetaplexBorsh.writeU8(w, value)
    pushByte(w, floor(value) % 256)
end

function MetaplexBorsh.writeU16(w, value)
    value = floor(value)
    pushByte(w, value % 256)
    pushByte(w, floor(value / 256) % 256)
end

function MetaplexBorsh.writeU32(w, value)
    value = floor(value)
    for _ = 1, 4 do
        pushByte(w, value % 256)
        value = floor(value / 256)
    end
end

-- Divide a non-negative decimal-string by `divisor`.
-- Returns (quotient_string, integer_remainder).
local function strDivMod(s, divisor)
    local q, rem = {}, 0
    for i = 1, #s do
        local d = string.byte(s, i) - 48
        if d < 0 or d > 9 then return nil, nil, "invalid digit '" .. s:sub(i,i) .. "'" end
        local cur = rem * 10 + d
        q[#q + 1] = string.char(48 + floor(cur / divisor))
        rem = cur % divisor
    end
    local qs = table.concat(q):gsub("^0+", "")
    if qs == "" then qs = "0" end
    return qs, rem
end

-- Write an unsigned integer as `byteCount` little-endian bytes.
-- Accepts a Lua number (will use `floor`) OR a decimal digit string
-- (so values > 2^53 are supported safely).
function MetaplexBorsh.writeUintLE(w, value, byteCount)
    if type(value) == "string" then
        local s = value:gsub("^%+", ""):gsub("^0+", "")
        if s == "" then s = "0" end
        local rem
        for _ = 1, byteCount do
            if s == "0" then
                pushByte(w, 0)
            else
                s, rem = strDivMod(s, 256)
                if not s then error("writeUintLE: " .. tostring(rem)) end
                pushByte(w, rem)
            end
        end
        if s ~= "0" then
            error("writeUintLE: value '" .. tostring(value) ..
                "' overflows " .. tostring(byteCount * 8) .. "-bit integer")
        end
        return
    end

    local n = floor(tonumber(value) or 0)
    for _ = 1, byteCount do
        pushByte(w, n % 256)
        n = floor(n / 256)
    end
end

function MetaplexBorsh.writeU64(w, value)
    MetaplexBorsh.writeUintLE(w, value, 8)
end

-- Multiply a decimal string by 10^zeros (i.e. append `zeros` zero digits).
-- Used to convert "1000000" + 9 decimals -> "1000000000000000".
function MetaplexBorsh.humanToRawString(supplyValue, decimals)
    local s
    if type(supplyValue) == "string" then
        s = supplyValue:gsub("^%+", "")
        if not s:match("^%d+$") then
            return nil, "supply must be a non-negative integer string"
        end
    else
        local n = tonumber(supplyValue)
        if not n or n < 0 then return nil, "supply must be a positive number" end
        s = string.format("%.0f", floor(n))
    end
    s = s:gsub("^0+", "")
    if s == "" then s = "0" end
    decimals = floor(tonumber(decimals) or 0)
    if decimals < 0 then return nil, "decimals must be >= 0" end
    if decimals > 0 then s = s .. string.rep("0", decimals) end
    return s
end

function MetaplexBorsh.writeBool(w, value)
    pushByte(w, value and 1 or 0)
end

function MetaplexBorsh.writeBytes(w, bytes)
    pushBytes(w, bytes)
end

function MetaplexBorsh.writeString(w, str)
    str = str or ""
    MetaplexBorsh.writeU32(w, #str)
    for i = 1, #str do
        pushByte(w, string.byte(str, i))
    end
end

-- Pubkey (32 bytes). Accepts a base58 string or a 32-byte array.
function MetaplexBorsh.writePubkey(w, addr)
    if type(addr) == "string" then
        local bytes, err = MetaplexBase58.decodePubkey(addr)
        if not bytes then
            error("Invalid pubkey: " .. tostring(err))
        end
        addr = bytes
    end
    if #addr ~= 32 then
        error("Pubkey must be 32 bytes, got " .. #addr)
    end
    pushBytes(w, addr)
end

-- Option wrapper: writeOption(w, value, function(w, v) ... end)
function MetaplexBorsh.writeOption(w, value, writeFn)
    if value == nil then
        pushByte(w, 0)
        return
    end
    pushByte(w, 1)
    writeFn(w, value)
end

-- Vec wrapper: writeVec(w, items, function(w, item) ... end)
function MetaplexBorsh.writeVec(w, items, writeFn)
    items = items or {}
    MetaplexBorsh.writeU32(w, #items)
    for _, item in ipairs(items) do
        writeFn(w, item)
    end
end

function MetaplexBorsh.toBytes(w)
    local out = {}
    for i = 1, #w.bytes do out[i] = w.bytes[i] end
    return out
end

-- ---
-- Readers
-- A "reader" wraps a byte array with a cursor so nested structs can parse
-- without tracking the offset manually. Used to decode on-chain accounts.
-- ---

local Reader = {}
Reader.__index = Reader

function MetaplexBorsh.newReader(bytes)
    return setmetatable({ bytes = bytes, pos = 1 }, Reader)
end

function Reader:remaining() return #self.bytes - self.pos + 1 end
function Reader:eof()       return self.pos > #self.bytes end

function Reader:readByte()
    if self:eof() then error("Reader: unexpected EOF") end
    local b = self.bytes[self.pos]
    self.pos = self.pos + 1
    return b
end

function Reader:readBytes(n)
    if self:remaining() < n then error("Reader: not enough bytes (need " .. n .. ")") end
    local out = {}
    for i = 1, n do out[i] = self.bytes[self.pos + i - 1] end
    self.pos = self.pos + n
    return out
end

function Reader:readU8() return self:readByte() end

function Reader:readU16()
    local lo, hi = self:readByte(), self:readByte()
    return lo + hi * 256
end

function Reader:readU32()
    local b1 = self:readByte()
    local b2 = self:readByte()
    local b3 = self:readByte()
    local b4 = self:readByte()
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

-- u64 kept as digit string so values > 2^53 stay lossless.
function Reader:readU64String()
    local bytes = self:readBytes(8)
    -- Convert 8-byte little-endian to decimal string via repeated /10
    -- Simpler: reconstruct as base-256 big-num then divmod to decimal.
    local digits = {0}
    for i = 8, 1, -1 do
        local carry = bytes[i]
        for j = 1, #digits do
            carry = carry + digits[j] * 256
            digits[j] = carry % 10
            carry = floor(carry / 10)
        end
        while carry > 0 do
            digits[#digits + 1] = carry % 10
            carry = floor(carry / 10)
        end
    end
    local chars = {}
    for i = #digits, 1, -1 do chars[#chars + 1] = tostring(digits[i]) end
    local s = table.concat(chars):gsub("^0+", "")
    if s == "" then s = "0" end
    return s
end

function Reader:readBool() return self:readByte() ~= 0 end

function Reader:readPubkey()
    return MetaplexBase58.encode(self:readBytes(32))
end

-- Borsh string: u32 length + UTF-8 bytes. Metaplex on-chain pads strings
-- with trailing \0 up to MAX_* sizes; `stripNul` default true removes them.
function Reader:readString(stripNul)
    if stripNul == nil then stripNul = true end
    local len = self:readU32()
    if len == 0 then return "" end
    local bytes = self:readBytes(len)
    local chars = {}
    for i = 1, len do chars[i] = string.char(bytes[i]) end
    local s = table.concat(chars)
    if stripNul then s = s:gsub("%z+$", "") end
    return s
end

-- Option wrapper for a custom reader function.
function Reader:readOption(readFn)
    local tag = self:readByte()
    if tag == 0 then return nil end
    if tag ~= 1 then error("Reader: invalid option tag " .. tag) end
    return readFn(self)
end

function Reader:readVec(readFn)
    local n = self:readU32()
    local out = {}
    for i = 1, n do out[i] = readFn(self) end
    return out
end

-- ---
-- Base64 decoder to raw byte array.
-- MTA provides decodeString("base64", ...) but only returns a Lua string;
-- we convert to a byte array so the Reader can consume it directly.
-- ---
function MetaplexBorsh.base64ToBytes(b64)
    if type(b64) ~= "string" then return nil, "base64: not a string" end
    local raw = decodeString("base64", b64)
    if not raw then return nil, "base64: decode failed" end
    local bytes = {}
    for i = 1, #raw do bytes[i] = string.byte(raw, i) end
    return bytes
end
