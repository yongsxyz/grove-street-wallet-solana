-- https://github.com/yongsxyz
--[[
    Grove Street Wallet - Wallet Manager
    Stores keypairs in memory
    Other resources only see the public address
]]

-- Internal storage: address → keypair
local _wallets = {}

-- ---
-- Wallet Functions (exported)
-- ---

-- Create wallet with random seed
-- WARNING: random is NOT cryptographically secure
-- For real funds, use importWallet() with a key from an external wallet
function createWallet()
    local seed = Ed25519.randomBytes(32)
    local keypair = Ed25519.keypairFromSeed(seed)
    local address = Base58.encode(keypair.publicKey)
    _wallets[address] = keypair
    outputDebugString("[solana-sdk] Wallet created: " .. address)
    return address
end

-- Import wallet from private key
-- Supports: hex string, base58 string, byte array
-- IMPORTANT: For 64-byte keys, use the embedded public key
--          Uses embedded key instead of re-deriving
function importWallet(privateKey)
    local seed
    local trustedPubkey  -- trusted public key from source (Phantom/Solflare)

    if type(privateKey) == "string" then
        if #privateKey == 64 and privateKey:match("^%x+$") then
            -- Hex string (32 bytes seed only)
            seed = Ed25519.hexToBytes(privateKey)
        elseif #privateKey == 128 and privateKey:match("^%x+$") then
            -- Hex string (64 bytes = seed + pubkey)
            seed = Ed25519.hexToBytes(privateKey:sub(1, 64))
            trustedPubkey = Ed25519.hexToBytes(privateKey:sub(65, 128))
        else
            -- Try base58 decode
            local decoded = Base58.decode(privateKey)
            if decoded then
                if #decoded == 64 then
                    -- 64 bytes: first 32 = seed, last 32 = public key (from Phantom/Solflare)
                    seed = {}
                    trustedPubkey = {}
                    for i = 1, 32 do seed[i] = decoded[i] end
                    for i = 1, 32 do trustedPubkey[i] = decoded[32 + i] end
                elseif #decoded == 32 then
                    seed = decoded
                else
                    return nil, "Invalid key length: " .. #decoded .. " bytes"
                end
            else
                return nil, "Invalid key format"
            end
        end
    elseif type(privateKey) == "table" then
        if #privateKey == 64 then
            seed = {}
            trustedPubkey = {}
            for i = 1, 32 do seed[i] = privateKey[i] end
            for i = 1, 32 do trustedPubkey[i] = privateKey[32 + i] end
        elseif #privateKey == 32 then
            seed = privateKey
        else
            return nil, "Invalid byte array length: " .. #privateKey
        end
    else
        return nil, "Invalid key type"
    end

    -- Derive scalar + prefix from seed (SHA-512 based, ini BENAR)
    local h = Crypto.sha512(seed)
    local scalar = {}
    for i = 1, 32 do scalar[i] = h[i] end
    -- Clamp
    scalar[1] = scalar[1] - (scalar[1] % 8)
    scalar[32] = (scalar[32] % 64) + 64

    local prefix = {}
    for i = 33, 64 do prefix[i - 32] = h[i] end

    -- Use trusted public key if available, otherwise derive
    local publicKey
    if trustedPubkey then
        publicKey = trustedPubkey
        outputDebugString("[solana-sdk] Using embedded public key (trusted)")
    else
        local kp = Ed25519.keypairFromSeed(seed)
        publicKey = kp.publicKey
        outputDebugString("[solana-sdk] WARNING: Derived public key (may differ from Phantom)")
    end

    local keypair = {
        seed = seed,
        scalar = scalar,
        prefix = prefix,
        publicKey = publicKey,
    }

    local address = Base58.encode(publicKey)
    _wallets[address] = keypair
    outputDebugString("[solana-sdk] Wallet imported: " .. address)
    return address
end

-- Import from Solana CLI JSON array format: [byte1, byte2, ..., byte64]
function importWalletJSON(jsonString)
    local decoded = fromJSON(jsonString)
    if not decoded or type(decoded) ~= "table" then
        return nil, "Invalid JSON"
    end
    return importWallet(decoded)
end

-- Export private key (seed) sebagai hex string (32 bytes = 64 hex chars)
function exportWalletHex(address)
    local kp = _wallets[address]
    if not kp then return nil, "Wallet not found" end
    return Ed25519.bytesToHex(kp.seed)
end

-- Export sebagai Base58 (Phantom / Solflare / Solana CLI compatible)
-- Format: 64 bytes (seed + pubkey) encoded as base58
-- Used by Phantom/Solflare to import
function exportWalletPhantom(address)
    local kp = _wallets[address]
    if not kp then return nil, "Wallet not found" end
    local bytes = {}
    for i = 1, 32 do bytes[i] = kp.seed[i] end
    for i = 1, 32 do bytes[32 + i] = kp.publicKey[i] end
    return Base58.encode(bytes)
end

-- Export sebagai Solana CLI format (JSON array of 64 bytes)
-- Can be pasted into id.json for solana-keygen
function exportWalletJSON(address)
    local kp = _wallets[address]
    if not kp then return nil, "Wallet not found" end
    local bytes = {}
    for i = 1, 32 do bytes[i] = kp.seed[i] end
    for i = 1, 32 do bytes[32 + i] = kp.publicKey[i] end
    return toJSON(bytes)
end

-- Get public key bytes
function getPublicKey(address)
    local kp = _wallets[address]
    if not kp then return nil, "Wallet not found" end
    return kp.publicKey
end

-- List all wallet addresses
function listWallets()
    local list = {}
    for addr, _ in pairs(_wallets) do
        list[#list + 1] = addr
    end
    return list
end

-- Remove wallet from memory
function removeWallet(address)
    if _wallets[address] then
        _wallets[address] = nil
        outputDebugString("[solana-sdk] Wallet removed: " .. address)
        return true
    end
    return false
end

-- Check if wallet exists
function hasWallet(address)
    return _wallets[address] ~= nil
end

-- Internal: get keypair (used by transaction.lua)
function _getKeypair(address)
    return _wallets[address]
end

-- Sign arbitrary message bytes with wallet
function signMessage(address, messageBytes)
    local kp = _wallets[address]
    if not kp then return nil, "Wallet not found" end

    if type(messageBytes) == "string" then
        local bytes = {}
        for i = 1, #messageBytes do
            bytes[i] = string.byte(messageBytes, i)
        end
        messageBytes = bytes
    end

    local signature = Ed25519.sign(messageBytes, kp)
    return signature
end

-- ---
-- MNEMONIC (BIP39) Functions
-- ---

-- Generate new mnemonic phrase (12 or 24 words)
-- Returns: mnemonic string, address
function generateMnemonic(wordCount)
    wordCount = wordCount or 12
    local mnemonic = BIP39.generateMnemonic(wordCount)
    local keypair = BIP39.mnemonicToKeypair(mnemonic)
    local address = Base58.encode(keypair.publicKey)
    -- Store with mnemonic reference
    keypair.mnemonic = mnemonic
    _wallets[address] = keypair
    outputDebugString("[solana-sdk] Mnemonic wallet created: " .. address)
    return mnemonic, address
end

-- Import wallet from mnemonic phrase
-- Compatible with: Phantom, Solflare, Solana CLI
function importFromMnemonic(mnemonic, passphrase)
    local valid, err = BIP39.isValidMnemonic(mnemonic)
    if not valid then
        return nil, nil, "Invalid mnemonic: " .. tostring(err)
    end

    local keypair = BIP39.mnemonicToKeypair(mnemonic, passphrase)
    local address = Base58.encode(keypair.publicKey)
    keypair.mnemonic = mnemonic
    _wallets[address] = keypair
    outputDebugString("[solana-sdk] Mnemonic wallet imported: " .. address)
    return address, mnemonic
end

-- Export mnemonic phrase (if wallet was created/imported with mnemonic)
function exportMnemonic(address)
    local kp = _wallets[address]
    if not kp then return nil, "Wallet not found" end
    if not kp.mnemonic then return nil, "Wallet has no mnemonic (was imported from key)" end
    return kp.mnemonic
end

-- ---
-- MULTI-FORMAT EXPORT (Phantom, Solflare, Solana CLI)
-- ---

-- Export for Phantom/Solflare: Base58 encoded 64 bytes (seed+pubkey)
function exportWalletPhantom(address)
    local kp = _wallets[address]
    if not kp then return nil, "Wallet not found" end
    local bytes = {}
    for i = 1, 32 do bytes[i] = kp.seed[i] end
    for i = 1, 32 do bytes[32 + i] = kp.publicKey[i] end
    return Base58.encode(bytes)
end

-- Export for Solana CLI: JSON byte array [n1,n2,...,n64]
function exportWalletCLI(address)
    local kp = _wallets[address]
    if not kp then return nil, "Wallet not found" end
    local bytes = {}
    for i = 1, 32 do bytes[i] = kp.seed[i] end
    for i = 1, 32 do bytes[32 + i] = kp.publicKey[i] end
    -- Format as JSON array string: [1,2,3,...,64]
    local parts = {}
    for i = 1, 64 do parts[i] = tostring(bytes[i]) end
    return "[" .. table.concat(parts, ",") .. "]"
end
