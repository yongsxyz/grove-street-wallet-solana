-- https://github.com/yongsxyz
--[[
    Grove Street Wallet - Transaction Builder
    Supports legacy transactions (version 0)

    Wire format:
    compact_u16(num_signatures) || signatures || message
    Message: header || account_keys || recent_blockhash || instructions
]]

SolTransaction = {}
SolTransaction.__index = SolTransaction

local floor = math.floor

-- ---
-- Compact-u16 encoding (Solana's variable-length integer)
-- ---

local function encode_compact_u16(value)
    if value < 0x80 then
        return {value}
    elseif value < 0x4000 then
        return {
            (value % 128) + 128,    -- low 7 bits + continuation
            floor(value / 128)
        }
    else
        return {
            (value % 128) + 128,
            (floor(value / 128) % 128) + 128,
            floor(value / 16384)
        }
    end
end

-- ---
-- Write little-endian u64
-- ---

local function encode_u64_le(value)
    local bytes = {}
    for i = 1, 8 do
        bytes[i] = value % 256
        value = floor(value / 256)
    end
    return bytes
end

-- ---
-- Write little-endian u32
-- ---

local function encode_u32_le(value)
    local bytes = {}
    for i = 1, 4 do
        bytes[i] = value % 256
        value = floor(value / 256)
    end
    return bytes
end

-- ---
-- Transaction Builder
-- ---

function SolTransaction.new()
    local self = setmetatable({}, SolTransaction)
    self.instructions = {}
    self.signers = {}          -- {address_string → keypair}
    self.recentBlockhash = nil -- 32-byte array
    self.feePayer = nil        -- address string
    return self
end

function SolTransaction:setRecentBlockhash(blockhash)
    if type(blockhash) == "string" then
        self.recentBlockhash = Base58.decode(blockhash)
    else
        self.recentBlockhash = blockhash
    end
    -- Pad to 32 bytes
    while #self.recentBlockhash < 32 do
        table.insert(self.recentBlockhash, 1, 0)
    end
    return self
end

function SolTransaction:setFeePayer(address)
    self.feePayer = address
    return self
end

-- Add instruction
-- instruction = {
--   programId = "base58 string",
--   keys = {
--     { pubkey = "base58", isSigner = bool, isWritable = bool },
--     ...
--   },
--   data = {byte1, byte2, ...}  (byte array)
-- }
function SolTransaction:addInstruction(instruction)
    self.instructions[#self.instructions + 1] = instruction
    return self
end

-- Add signer (wallet address already imported)
function SolTransaction:addSigner(address)
    local kp = _getKeypair(address)
    if not kp then
        return nil, "Wallet not found for address: " .. tostring(address)
    end
    self.signers[address] = kp
    return self
end

-- Compile: collect accounts, build message, sign
function SolTransaction:compile()
    if not self.recentBlockhash then
        return nil, "Recent blockhash not set"
    end
    if not self.feePayer then
        return nil, "Fee payer not set"
    end

    -- Collect all unique accounts
    local accountMap = {}  -- address → {index, isSigner, isWritable}
    local accountOrder = {}

    local function addAccount(addr, isSigner, isWritable)
        if accountMap[addr] then
            local existing = accountMap[addr]
            if isSigner then existing.isSigner = true end
            if isWritable then existing.isWritable = true end
        else
            accountMap[addr] = {
                isSigner = isSigner,
                isWritable = isWritable,
            }
            accountOrder[#accountOrder + 1] = addr
        end
    end

    -- Fee payer is always first, always signer + writable
    addAccount(self.feePayer, true, true)

    -- Process instructions
    for _, ix in ipairs(self.instructions) do
        for _, key in ipairs(ix.keys) do
            addAccount(key.pubkey, key.isSigner, key.isWritable)
        end
        addAccount(ix.programId, false, false)
    end

    -- Sort accounts: signers+writable, signers+readonly, non-signers+writable, non-signers+readonly
    -- Fee payer always stays at index 0
    local signerWritable = {}
    local signerReadonly = {}
    local nonsignerWritable = {}
    local nonsignerReadonly = {}

    for _, addr in ipairs(accountOrder) do
        local acc = accountMap[addr]
        if addr == self.feePayer then
            -- skip, already first
        elseif acc.isSigner and acc.isWritable then
            signerWritable[#signerWritable + 1] = addr
        elseif acc.isSigner then
            signerReadonly[#signerReadonly + 1] = addr
        elseif acc.isWritable then
            nonsignerWritable[#nonsignerWritable + 1] = addr
        else
            nonsignerReadonly[#nonsignerReadonly + 1] = addr
        end
    end

    local sortedAccounts = {self.feePayer}
    for _, a in ipairs(signerWritable) do sortedAccounts[#sortedAccounts + 1] = a end
    for _, a in ipairs(signerReadonly) do sortedAccounts[#sortedAccounts + 1] = a end
    for _, a in ipairs(nonsignerWritable) do sortedAccounts[#sortedAccounts + 1] = a end
    for _, a in ipairs(nonsignerReadonly) do sortedAccounts[#sortedAccounts + 1] = a end

    -- Build index map
    local indexMap = {}
    for i, addr in ipairs(sortedAccounts) do
        indexMap[addr] = i - 1  -- 0-indexed
    end

    -- Header
    local numRequiredSignatures = 1 + #signerWritable + #signerReadonly
    local numReadonlySignedAccounts = #signerReadonly
    local numReadonlyUnsignedAccounts = #nonsignerReadonly

    -- Build message bytes
    local msg = {}
    local function append(bytes)
        for _, b in ipairs(bytes) do msg[#msg + 1] = b end
    end
    local function appendByte(b)
        msg[#msg + 1] = b
    end

    -- Header (3 bytes)
    appendByte(numRequiredSignatures)
    appendByte(numReadonlySignedAccounts)
    appendByte(numReadonlyUnsignedAccounts)

    -- Account keys
    append(encode_compact_u16(#sortedAccounts))
    for _, addr in ipairs(sortedAccounts) do
        local pubkeyBytes = Base58.decode(addr)
        if not pubkeyBytes then
            return nil, "Invalid account address: " .. tostring(addr)
        end
        -- Pad to 32 bytes (left-pad with zeros for short addresses like System Program)
        while #pubkeyBytes < 32 do
            table.insert(pubkeyBytes, 1, 0)
        end
        append(pubkeyBytes)
    end

    -- Recent blockhash (32 bytes)
    append(self.recentBlockhash)

    -- Instructions
    append(encode_compact_u16(#self.instructions))
    for _, ix in ipairs(self.instructions) do
        -- Program ID index
        appendByte(indexMap[ix.programId])
        -- Account indices
        append(encode_compact_u16(#ix.keys))
        for _, key in ipairs(ix.keys) do
            appendByte(indexMap[key.pubkey])
        end
        -- Instruction data
        local data = ix.data or {}
        append(encode_compact_u16(#data))
        append(data)
    end

    return {
        message = msg,
        numSignatures = numRequiredSignatures,
        sortedAccounts = sortedAccounts,
        indexMap = indexMap,
    }
end

-- Sign and serialize transaction
function SolTransaction:signAndSerialize()
    local compiled, err = self:compile()
    if not compiled then
        return nil, err
    end

    -- Sign message
    local signatures = {}
    for i = 1, compiled.numSignatures do
        local addr = compiled.sortedAccounts[i]
        local kp = self.signers[addr]
        if not kp then
            return nil, "Missing signer for account: " .. tostring(addr)
        end
        local sig = Ed25519.sign(compiled.message, kp)
        -- Ensure signature is exactly 64 bytes
        while #sig < 64 do sig[#sig + 1] = 0 end
        signatures[i] = sig
    end

    -- Build wire format
    local wire = {}
    local function append(bytes)
        for _, b in ipairs(bytes) do wire[#wire + 1] = b end
    end

    -- Compact array of signatures
    append(encode_compact_u16(#signatures))
    for _, sig in ipairs(signatures) do
        append(sig)
    end

    -- Message
    append(compiled.message)

    return wire
end

-- Sign, serialize, and base64 encode (ready for sendTransaction RPC)
function SolTransaction:signAndEncode()
    local wire, err = self:signAndSerialize()
    if not wire then return nil, err end

    -- Convert to base64 (use table.concat for binary safety)
    local chars = {}
    for i = 1, #wire do
        local b = wire[i]
        if type(b) ~= "number" or b < 0 or b > 255 then
            return nil, "Invalid byte at position " .. i .. ": " .. tostring(b)
        end
        chars[i] = string.char(b)
    end
    local str = table.concat(chars)
    outputDebugString("[solana-sdk] TX wire size: " .. #wire .. " bytes")
    return encodeString("base64", str)
end

-- ---
-- Helper: build + sign + send SOL transfer in one call
-- ---

function buildAndSignTransfer(fromAddress, toAddress, lamports, recentBlockhash)
    local tx = SolTransaction.new()
    tx:setFeePayer(fromAddress)
    tx:setRecentBlockhash(recentBlockhash)
    tx:addSigner(fromAddress)

    -- System Program transfer instruction
    tx:addInstruction(SystemProgram.transfer(fromAddress, toAddress, lamports))

    return tx:signAndEncode()
end
