-- https://github.com/yongsxyz
--[[
    Base58 Encoding/Decoding for Solana addresses
    Used by Grove Street Wallet SDK
]]

local BASE58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
local BASE58_MAP = {}

for i = 1, #BASE58_ALPHABET do
    BASE58_MAP[BASE58_ALPHABET:sub(i, i)] = i - 1
end

Base58 = {}

function Base58.encode(bytes)
    if type(bytes) == "string" then
        local t = {}
        for i = 1, #bytes do
            t[i] = string.byte(bytes, i)
        end
        bytes = t
    end

    local leadingZeros = 0
    for i = 1, #bytes do
        if bytes[i] == 0 then
            leadingZeros = leadingZeros + 1
        else
            break
        end
    end

    -- convert byte array to big integer then to base58
    local digits = {0}
    for i = 1, #bytes do
        local carry = bytes[i]
        for j = 1, #digits do
            carry = carry + digits[j] * 256
            digits[j] = carry % 58
            carry = math.floor(carry / 58)
        end
        while carry > 0 do
            digits[#digits + 1] = carry % 58
            carry = math.floor(carry / 58)
        end
    end

    local result = {}
    for i = 1, leadingZeros do
        result[i] = "1"
    end
    for i = #digits, 1, -1 do
        result[#result + 1] = BASE58_ALPHABET:sub(digits[i] + 1, digits[i] + 1)
    end

    return table.concat(result)
end

function Base58.decode(str)
    local leadingOnes = 0
    for i = 1, #str do
        if str:sub(i, i) == "1" then
            leadingOnes = leadingOnes + 1
        else
            break
        end
    end

    local bytes = {}
    for i = 1, #str do
        local char = str:sub(i, i)
        local value = BASE58_MAP[char]
        if not value then
            return nil, "Invalid base58 character: " .. char
        end

        local carry = value
        for j = 1, #bytes do
            carry = carry + bytes[j] * 58
            bytes[j] = carry % 256
            carry = math.floor(carry / 256)
        end
        while carry > 0 do
            bytes[#bytes + 1] = carry % 256
            carry = math.floor(carry / 256)
        end
    end

    local result = {}
    for i = 1, leadingOnes do
        result[i] = 0
    end
    for i = #bytes, 1, -1 do
        result[#result + 1] = bytes[i]
    end

    return result
end

function Base58.decodeToString(str)
    local bytes, err = Base58.decode(str)
    if not bytes then return nil, err end
    local chars = {}
    for i = 1, #bytes do
        chars[i] = string.char(bytes[i])
    end
    return table.concat(chars)
end

function Base58.isValid(str)
    if type(str) ~= "string" or #str == 0 then return false end
    for i = 1, #str do
        if not BASE58_MAP[str:sub(i, i)] then
            return false
        end
    end
    return true
end

-- Validate Solana address (32 bytes = 32-44 chars base58)
function Base58.isValidSolanaAddress(addr)
    if not Base58.isValid(addr) then return false end
    if #addr < 32 or #addr > 44 then return false end
    local decoded = Base58.decode(addr)
    return decoded and #decoded == 32
end
