-- https://github.com/yongsxyz
--[[
    Metaplex SDK - Base58 helper (self contained)
    Each MTA:SA resource has its own Lua state, so we keep a private copy
    of the encoder/decoder instead of depending on solana-sdk globals.
]]

local floor = math.floor

local ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
local MAP = {}
for i = 1, #ALPHABET do
    MAP[ALPHABET:sub(i, i)] = i - 1
end

MetaplexBase58 = {}

function MetaplexBase58.encode(bytes)
    if type(bytes) == "string" then
        local t = {}
        for i = 1, #bytes do t[i] = string.byte(bytes, i) end
        bytes = t
    end

    local leadingZeros = 0
    for i = 1, #bytes do
        if bytes[i] == 0 then leadingZeros = leadingZeros + 1 else break end
    end

    local digits = {0}
    for i = 1, #bytes do
        local carry = bytes[i]
        for j = 1, #digits do
            carry = carry + digits[j] * 256
            digits[j] = carry % 58
            carry = floor(carry / 58)
        end
        while carry > 0 do
            digits[#digits + 1] = carry % 58
            carry = floor(carry / 58)
        end
    end

    local result = {}
    for i = 1, leadingZeros do result[i] = "1" end
    for i = #digits, 1, -1 do
        result[#result + 1] = ALPHABET:sub(digits[i] + 1, digits[i] + 1)
    end
    return table.concat(result)
end

function MetaplexBase58.decode(str)
    if type(str) ~= "string" or #str == 0 then return nil, "Empty string" end

    local leadingOnes = 0
    for i = 1, #str do
        if str:sub(i, i) == "1" then leadingOnes = leadingOnes + 1 else break end
    end

    local bytes = {}
    for i = 1, #str do
        local char = str:sub(i, i)
        local value = MAP[char]
        if not value then return nil, "Invalid base58 character: " .. char end

        local carry = value
        for j = 1, #bytes do
            carry = carry + bytes[j] * 58
            bytes[j] = carry % 256
            carry = floor(carry / 256)
        end
        while carry > 0 do
            bytes[#bytes + 1] = carry % 256
            carry = floor(carry / 256)
        end
    end

    local result = {}
    for i = 1, leadingOnes do result[i] = 0 end
    for i = #bytes, 1, -1 do result[#result + 1] = bytes[i] end
    return result
end

-- Decode and pad/truncate to exactly 32 bytes (standard Solana pubkey size)
function MetaplexBase58.decodePubkey(addr)
    if not addr then return nil end
    local bytes, err = MetaplexBase58.decode(addr)
    if not bytes then return nil, err end
    if #bytes > 32 then return nil, "Address decodes to more than 32 bytes" end
    local out = {}
    local pad = 32 - #bytes
    for i = 1, pad do out[i] = 0 end
    for i = 1, #bytes do out[pad + i] = bytes[i] end
    return out
end

function MetaplexBase58.isValid(str)
    if type(str) ~= "string" or #str == 0 then return false end
    for i = 1, #str do
        if not MAP[str:sub(i, i)] then return false end
    end
    return true
end
