-- https://github.com/yongsxyz
--[[
    BIP39 Mnemonic + SLIP-0010 Derivation for MTA:SA
    Kompatibel: Phantom, Solflare, Solana CLI

    Derivation path: m/44'/501'/0'/0' (Solana standard)
    PBKDF2: 2048 iterations (~1-2s in MTA)
]]

BIP39 = {}

local floor = math.floor

-- ---
-- PBKDF2-HMAC-SHA512
-- ---

local function pbkdf2_sha512(password, salt, iterations, keylen)
    if type(password) == "string" then password = Crypto.stringToBytes(password) end
    if type(salt) == "string" then salt = Crypto.stringToBytes(salt) end

    local dk = {}
    local block_count = math.ceil(keylen / 64)

    for block = 1, block_count do
        -- U1 = HMAC(password, salt || INT32BE(block))
        local s = {}
        for i = 1, #salt do s[i] = salt[i] end
        s[#s + 1] = floor(block / 16777216) % 256
        s[#s + 1] = floor(block / 65536) % 256
        s[#s + 1] = floor(block / 256) % 256
        s[#s + 1] = block % 256

        local u = Crypto.hmacSha512(password, s)
        local t = {}
        for i = 1, 64 do t[i] = u[i] end

        for iter = 2, iterations do
            u = Crypto.hmacSha512(password, u)
            for i = 1, 64 do
                t[i] = Crypto.bxor(t[i], u[i])
            end
        end

        for i = 1, 64 do
            if #dk < keylen then
                dk[#dk + 1] = t[i]
            end
        end
    end

    return dk
end

-- ---
-- SLIP-0010 Ed25519 Key Derivation
-- Path: m/44'/501'/0'/0' (Solana)
-- ---

local function slip0010_derive(seed_bytes)
    -- Master key
    local I = Crypto.hmacSha512(
        Crypto.stringToBytes("ed25519 seed"),
        seed_bytes
    )
    local key = {}
    local chain = {}
    for i = 1, 32 do key[i] = I[i] end
    for i = 1, 32 do chain[i] = I[32 + i] end

    -- Derivation path: 44', 501', 0', 0'
    local path = {
        44 + 2147483648,   -- 44'
        501 + 2147483648,  -- 501'
        0 + 2147483648,    -- 0'
        0 + 2147483648,    -- 0'
    }

    for _, index in ipairs(path) do
        -- Child: HMAC-SHA512(chain, 0x00 || key || index_BE)
        local data = {0}
        for i = 1, 32 do data[1 + i] = key[i] end
        -- index as 4 bytes big-endian
        data[34] = floor(index / 16777216) % 256
        data[35] = floor(index / 65536) % 256
        data[36] = floor(index / 256) % 256
        data[37] = index % 256

        I = Crypto.hmacSha512(chain, data)
        for i = 1, 32 do key[i] = I[i] end
        for i = 1, 32 do chain[i] = I[32 + i] end
    end

    return key -- 32-byte seed for Ed25519
end

-- ---
-- BIP39 Mnemonic Generation
-- ---

-- Generate mnemonic (12 or 24 words)
function BIP39.generateMnemonic(wordCount)
    wordCount = wordCount or 12
    local entropyBits = (wordCount == 24) and 256 or 128
    local entropyBytes = entropyBits / 8

    -- Generate entropy
    local entropy = Ed25519.randomBytes(entropyBytes)

    -- SHA-256 checksum
    local cs = Crypto.sha256(entropy)
    local checksumBits = entropyBits / 32

    -- Convert entropy to bit string
    local bits = {}
    for i = 1, #entropy do
        local b = entropy[i]
        for j = 7, 0, -1 do
            bits[#bits + 1] = floor(b / (2 ^ j)) % 2
        end
    end
    -- Append checksum bits
    local csb = cs[1]
    for j = 7, 8 - checksumBits, -1 do
        bits[#bits + 1] = floor(csb / (2 ^ j)) % 2
    end

    -- Split into 11-bit groups -> word indices
    local words = {}
    for i = 0, wordCount - 1 do
        local idx = 0
        for j = 0, 10 do
            idx = idx + bits[i * 11 + j + 1] * (2 ^ (10 - j))
        end
        words[#words + 1] = BIP39_WORDS[idx + 1]
    end

    return table.concat(words, " ")
end

-- ---
-- Mnemonic -> Solana Keypair
-- ---

function BIP39.mnemonicToSeed(mnemonic, passphrase)
    passphrase = passphrase or ""
    local salt = "mnemonic" .. passphrase
    outputDebugString("[solana-sdk] PBKDF2 deriving seed (2048 iterations)...")
    local seed = pbkdf2_sha512(mnemonic, salt, 2048, 64)
    outputDebugString("[solana-sdk] PBKDF2 complete")
    return seed
end

function BIP39.mnemonicToKeypair(mnemonic, passphrase)
    local seed = BIP39.mnemonicToSeed(mnemonic, passphrase)
    local derivedKey = slip0010_derive(seed)
    return Ed25519.keypairFromSeed(derivedKey)
end

-- ---
-- Validate mnemonic
-- ---

function BIP39.isValidMnemonic(mnemonic)
    local words = {}
    for w in mnemonic:gmatch("%S+") do
        words[#words + 1] = w
    end
    if #words ~= 12 and #words ~= 24 then
        return false, "Must be 12 or 24 words"
    end
    -- Check all words exist in wordlist
    local wordSet = {}
    for _, w in ipairs(BIP39_WORDS) do wordSet[w] = true end
    for _, w in ipairs(words) do
        if not wordSet[w:lower()] then
            return false, "Unknown word: " .. w
        end
    end
    return true
end
