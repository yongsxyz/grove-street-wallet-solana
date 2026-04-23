-- https://github.com/yongsxyz
--[[
    Metaplex SDK - Program Derived Address derivation.

    Solana PDA algorithm:
        for bump in 255 .. 0:
            hash = SHA256(seed1 || seed2 || ... || [bump] || programId || "ProgramDerivedAddress")
            if hash is NOT on the Ed25519 curve: return (hash, bump)

    Returns the canonical PDA (highest bump that lands off-curve).
]]

MetaplexPDA = {}

local PDA_SUFFIX = {80,114,111,103,114,97,109,68,101,114,105,118,101,100,65,100,100,114,101,115,115}
-- "ProgramDerivedAddress"

local function sha256_bytes(byteArray)
    local chars = {}
    for i = 1, #byteArray do chars[i] = string.char(byteArray[i]) end
    local hex = hash("sha256", table.concat(chars))
    local out = {}
    for i = 1, 64, 2 do
        out[#out + 1] = tonumber(hex:sub(i, i + 1), 16)
    end
    return out
end

local function appendBytes(dst, src)
    local n = #dst
    for i = 1, #src do dst[n + i] = src[i] end
end

local function seedToBytes(seed)
    if type(seed) == "string" then
        local out = {}
        for i = 1, #seed do out[i] = string.byte(seed, i) end
        return out
    end
    -- Already a byte array
    local out = {}
    for i = 1, #seed do out[i] = seed[i] end
    return out
end

-- Derive PDA from seeds.
-- seeds: array of strings or byte arrays
-- programIdBytes: 32-byte array (decoded program id)
-- Returns: { addressBytes, bump } or nil if no off-curve hash exists (extremely unlikely)
function MetaplexPDA.findProgramAddressBytes(seeds, programIdBytes)
    -- Pre-flatten seed bytes (they don't change between bump iterations)
    local prefix = {}
    for _, seed in ipairs(seeds) do
        appendBytes(prefix, seedToBytes(seed))
    end
    local prefixLen = #prefix

    for bump = 255, 0, -1 do
        local data = {}
        for i = 1, prefixLen do data[i] = prefix[i] end
        data[prefixLen + 1] = bump
        appendBytes(data, programIdBytes)
        appendBytes(data, PDA_SUFFIX)

        local h = sha256_bytes(data)
        if not MetaplexField.isOnCurve(h) then
            return h, bump
        end
    end
    return nil, nil
end

-- Convenience: returns base58 string + bump
function MetaplexPDA.findProgramAddress(seeds, programIdBase58)
    local pidBytes, err = MetaplexBase58.decodePubkey(programIdBase58)
    if not pidBytes then return nil, nil, err end

    local addrBytes, bump = MetaplexPDA.findProgramAddressBytes(seeds, pidBytes)
    if not addrBytes then return nil, nil, "No off-curve PDA found (impossible)" end

    return MetaplexBase58.encode(addrBytes), bump
end
