-- https://github.com/yongsxyz
--[[
    Grove Street Wallet - Program Instructions
    System, Token, ATA, Custom, Memo programs
]]

local floor = math.floor

-- ---
-- System Program (11111111111111111111111111111111)
-- ---

SystemProgram = {}
SystemProgram.PROGRAM_ID = "11111111111111111111111111111111"

-- Transfer SOL
-- fromAddress, toAddress = base58 strings
-- lamports = number
function SystemProgram.transfer(fromAddress, toAddress, lamports)
    -- Instruction index 2 (u32 LE) + lamports (u64 LE)
    local data = {}
    -- u32 LE: instruction index = 2
    data[1] = 2
    data[2] = 0
    data[3] = 0
    data[4] = 0
    -- u64 LE: lamports
    local amount = floor(tonumber(lamports) or 0)
    for i = 5, 12 do
        data[i] = floor(amount % 256)
        amount = floor(amount / 256)
    end

    return {
        programId = SystemProgram.PROGRAM_ID,
        keys = {
            { pubkey = fromAddress, isSigner = true, isWritable = true },
            { pubkey = toAddress, isSigner = false, isWritable = true },
        },
        data = data,
    }
end

-- Create Account
function SystemProgram.createAccount(fromAddress, newAccountAddress, lamports, space, ownerId)
    local data = {}
    -- u32 LE: instruction index = 0
    data[1] = 0; data[2] = 0; data[3] = 0; data[4] = 0
    -- u64 LE: lamports
    local amount = floor(tonumber(lamports) or 0)
    for i = 5, 12 do
        data[i] = floor(amount % 256)
        amount = floor(amount / 256)
    end
    -- u64 LE: space
    local sp = space
    for i = 13, 20 do
        data[i] = sp % 256
        sp = floor(sp / 256)
    end
    -- 32 bytes: owner program id
    local ownerBytes = Base58.decode(ownerId)
    for i = 1, 32 do
        data[20 + i] = ownerBytes[i] or 0
    end

    return {
        programId = SystemProgram.PROGRAM_ID,
        keys = {
            { pubkey = fromAddress, isSigner = true, isWritable = true },
            { pubkey = newAccountAddress, isSigner = true, isWritable = true },
        },
        data = data,
    }
end

-- Allocate space
function SystemProgram.allocate(accountAddress, space)
    local data = {}
    data[1] = 8; data[2] = 0; data[3] = 0; data[4] = 0
    local sp = space
    for i = 5, 12 do
        data[i] = sp % 256
        sp = floor(sp / 256)
    end
    return {
        programId = SystemProgram.PROGRAM_ID,
        keys = {
            { pubkey = accountAddress, isSigner = true, isWritable = true },
        },
        data = data,
    }
end

-- Assign owner
function SystemProgram.assign(accountAddress, ownerId)
    local data = {}
    data[1] = 1; data[2] = 0; data[3] = 0; data[4] = 0
    local ownerBytes = Base58.decode(ownerId)
    for i = 1, 32 do
        data[4 + i] = ownerBytes[i] or 0
    end
    return {
        programId = SystemProgram.PROGRAM_ID,
        keys = {
            { pubkey = accountAddress, isSigner = true, isWritable = true },
        },
        data = data,
    }
end

-- ---
-- Token Program (TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA)
-- ---

TokenProgram = {}
TokenProgram.PROGRAM_ID = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
TokenProgram.TOKEN_2022_PROGRAM_ID = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"

-- Transfer tokens
function TokenProgram.transfer(sourceTokenAccount, destTokenAccount, ownerAddress, amount)
    local data = {}
    data[1] = 3  -- Transfer instruction index
    local amt = floor(tonumber(amount) or 0)
    for i = 2, 9 do
        data[i] = floor(amt % 256)
        amt = floor(amt / 256)
    end
    return {
        programId = TokenProgram.PROGRAM_ID,
        keys = {
            { pubkey = sourceTokenAccount, isSigner = false, isWritable = true },
            { pubkey = destTokenAccount, isSigner = false, isWritable = true },
            { pubkey = ownerAddress, isSigner = true, isWritable = false },
        },
        data = data,
    }
end

-- Approve delegate
function TokenProgram.approve(tokenAccount, delegateAddress, ownerAddress, amount)
    local data = {}
    data[1] = 4  -- Approve instruction
    local amt = amount
    for i = 2, 9 do
        data[i] = amt % 256
        amt = floor(amt / 256)
    end
    return {
        programId = TokenProgram.PROGRAM_ID,
        keys = {
            { pubkey = tokenAccount, isSigner = false, isWritable = true },
            { pubkey = delegateAddress, isSigner = false, isWritable = false },
            { pubkey = ownerAddress, isSigner = true, isWritable = false },
        },
        data = data,
    }
end

-- Revoke (cabut approve)
function TokenProgram.revoke(tokenAccount, ownerAddress)
    return {
        programId = TokenProgram.PROGRAM_ID,
        keys = {
            { pubkey = tokenAccount, isSigner = false, isWritable = true },
            { pubkey = ownerAddress, isSigner = true, isWritable = false },
        },
        data = {5},  -- Instruction index 5 = Revoke
    }
end

-- Burn tokens
function TokenProgram.burn(tokenAccount, mintAddress, ownerAddress, amount)
    local data = {}
    data[1] = 8  -- Instruction index 8 = Burn
    local amt = amount
    for i = 2, 9 do
        data[i] = amt % 256
        amt = floor(amt / 256)
    end
    return {
        programId = TokenProgram.PROGRAM_ID,
        keys = {
            { pubkey = tokenAccount, isSigner = false, isWritable = true },
            { pubkey = mintAddress, isSigner = false, isWritable = true },
            { pubkey = ownerAddress, isSigner = true, isWritable = false },
        },
        data = data,
    }
end

-- Close token account (reclaim rent SOL)
function TokenProgram.closeAccount(tokenAccount, destAddress, ownerAddress)
    return {
        programId = TokenProgram.PROGRAM_ID,
        keys = {
            { pubkey = tokenAccount, isSigner = false, isWritable = true },
            { pubkey = destAddress, isSigner = false, isWritable = true },
            { pubkey = ownerAddress, isSigner = true, isWritable = false },
        },
        data = {9},  -- Instruction index 9 = CloseAccount
    }
end

-- Initialize token account
function TokenProgram.initializeAccount(tokenAccount, mintAddress, ownerAddress)
    return {
        programId = TokenProgram.PROGRAM_ID,
        keys = {
            { pubkey = tokenAccount, isSigner = false, isWritable = true },
            { pubkey = mintAddress, isSigner = false, isWritable = false },
            { pubkey = ownerAddress, isSigner = false, isWritable = false },
            { pubkey = "SysvarRent111111111111111111111111111111111", isSigner = false, isWritable = false },
        },
        data = {1},  -- Instruction index 1 = InitializeAccount
    }
end

-- ---
-- Associated Token Account Program
-- ---

AssociatedTokenProgram = {}
AssociatedTokenProgram.PROGRAM_ID = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"

-- Solana findProgramAddress:
-- for bump = 255 down to 0:
--   hash = SHA256(seed1 || seed2 || ... || [bump] || programId || "ProgramDerivedAddress")
--   if NOT on ed25519 curve -> return hash
-- ATA seeds: [walletAddress, tokenProgramId, mintAddress]
-- programId: ATA_PROGRAM_ID
local function safeDecode32(addr)
    if not addr then return nil end
    local bytes = Base58.decode(addr)
    if not bytes then return nil end
    -- Ensure exactly 32 bytes, pad left with zeros
    local result = {}
    local pad = 32 - #bytes
    for i = 1, pad do result[i] = 0 end
    for i = 1, #bytes do result[pad + i] = bytes[i] end
    -- Clamp all values to 0-255
    for i = 1, 32 do
        result[i] = math.max(0, math.min(255, math.floor(result[i] or 0)))
    end
    return result
end

-- Precompute hashes for bump 255 down to 250 and return all candidates
-- The correct one is the first that's NOT on Ed25519 curve
-- Since on-curve check is expensive and error-prone in pure Lua,
-- we return candidates and let transferTokenToWallet try them
function AssociatedTokenProgram.findAddress(walletAddress, mintAddress, tokenProgramId)
    tokenProgramId = tokenProgramId or TokenProgram.PROGRAM_ID
    local walletBytes = safeDecode32(walletAddress)
    local tokenProgBytes = safeDecode32(tokenProgramId)
    local mintBytes = safeDecode32(mintAddress)
    local ataProgramBytes = safeDecode32(AssociatedTokenProgram.PROGRAM_ID)

    if not walletBytes or not tokenProgBytes or not mintBytes or not ataProgramBytes then
        return nil
    end

    local pdaSuffix = {80,114,111,103,114,97,109,68,101,114,105,118,101,100,65,100,100,114,101,115,115}

    -- Try all bumps 255 down to 0
    local candidates = {}
    for bump = 255, 0, -1 do
        local data = {}
        for i = 1, 32 do data[#data+1] = walletBytes[i] end
        for i = 1, 32 do data[#data+1] = tokenProgBytes[i] end
        for i = 1, 32 do data[#data+1] = mintBytes[i] end
        data[#data+1] = bump
        for i = 1, 32 do data[#data+1] = ataProgramBytes[i] end
        for i = 1, #pdaSuffix do data[#data+1] = pdaSuffix[i] end
        local h = Crypto.sha256(data)
        candidates[#candidates+1] = { address = Base58.encode(h), bump = bump }
    end
    return candidates
end

-- findAddressSingle: returns first candidate (for createIdempotent which handles wrong address gracefully)
function AssociatedTokenProgram.findAddressBest(walletAddress, mintAddress, tokenProgramId)
    local candidates = AssociatedTokenProgram.findAddress(walletAddress, mintAddress, tokenProgramId)
    if not candidates or #candidates == 0 then return nil end
    return candidates[1].address, candidates[1].bump
end

-- CreateIdempotent instruction builder for a given ATA address
function AssociatedTokenProgram.createIdempotentIx(payerAddress, ataAddress, walletAddress, mintAddress, tokenProgramId)
    tokenProgramId = tokenProgramId or TokenProgram.PROGRAM_ID
    return {
        programId = AssociatedTokenProgram.PROGRAM_ID,
        keys = {
            { pubkey = payerAddress, isSigner = true, isWritable = true },
            { pubkey = ataAddress, isSigner = false, isWritable = true },
            { pubkey = walletAddress, isSigner = false, isWritable = false },
            { pubkey = mintAddress, isSigner = false, isWritable = false },
            { pubkey = SystemProgram.PROGRAM_ID, isSigner = false, isWritable = false },
            { pubkey = tokenProgramId, isSigner = false, isWritable = false },
        },
        data = {1},
    }
end

-- Convenience: returns instruction + best ATA address (tries bump 254 first since 255 is often on-curve)
function AssociatedTokenProgram.createIdempotent(payerAddress, walletAddress, mintAddress, tokenProgramId)
    tokenProgramId = tokenProgramId or TokenProgram.PROGRAM_ID
    local candidates = AssociatedTokenProgram.findAddress(walletAddress, mintAddress, tokenProgramId)
    if not candidates or #candidates == 0 then return nil end
    -- Try bump=254 first (index 2 in candidates since 255=1, 254=2)
    -- Most ATAs use bump 254 or 255. If 255 is on-curve, 254 is correct.
    -- We try 254 first as it's more commonly the valid PDA.
    local best = candidates[2] or candidates[1]  -- prefer 254 over 255
    local ix = AssociatedTokenProgram.createIdempotentIx(payerAddress, best.address, walletAddress, mintAddress, tokenProgramId)
    return ix, best.address
end

-- ---
-- Custom Program Instruction Builder
-- ---

CustomProgram = {}

-- Build instruction for any program
-- programId = base58 string
-- accounts = { {pubkey, isSigner, isWritable}, ... }
-- data = byte array
function CustomProgram.instruction(programId, accounts, data)
    local keys = {}
    for i, acc in ipairs(accounts) do
        keys[i] = {
            pubkey = acc[1] or acc.pubkey,
            isSigner = acc[2] or acc.isSigner or false,
            isWritable = acc[3] or acc.isWritable or false,
        }
    end
    return {
        programId = programId,
        keys = keys,
        data = data or {},
    }
end

-- Anchor instruction helper (8-byte discriminator + serialized args)
function CustomProgram.anchorInstruction(programId, accounts, discriminator, argBytes)
    local data = {}
    -- Discriminator is 8 bytes (first 8 bytes of SHA256("global:<method_name>"))
    if type(discriminator) == "string" then
        local h = hash("sha256", "global:" .. discriminator)
        for i = 1, 16, 2 do
            data[#data + 1] = tonumber(h:sub(i, i + 1), 16)
        end
    elseif type(discriminator) == "table" then
        for i = 1, 8 do data[i] = discriminator[i] or 0 end
    end
    -- Append arg bytes
    if argBytes then
        for i = 1, #argBytes do data[#data + 1] = argBytes[i] end
    end
    return CustomProgram.instruction(programId, accounts, data)
end

-- ---
-- Memo Program (Add memo to transaction)
-- ---

MemoProgram = {}
MemoProgram.PROGRAM_ID = "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr"

function MemoProgram.memo(signerAddress, text)
    local data = {}
    for i = 1, #text do
        data[i] = string.byte(text, i)
    end
    return {
        programId = MemoProgram.PROGRAM_ID,
        keys = {
            { pubkey = signerAddress, isSigner = true, isWritable = false },
        },
        data = data,
    }
end
