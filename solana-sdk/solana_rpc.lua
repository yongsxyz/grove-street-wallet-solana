-- https://github.com/yongsxyz
--[[
    Grove Street Wallet - JSON-RPC Client
    Uses fetchRemote (async, callback-based)

    All methods return via callback: function(result, error)
    result = parsed JSON
    error = error string on failure
]]

SolanaRPC = {}
SolanaRPC.__index = SolanaRPC

local CLUSTER_ENDPOINTS = {
    ["mainnet"]      = "https://api.mainnet-beta.solana.com",
    ["mainnet-beta"] = "https://api.mainnet-beta.solana.com",
    ["devnet"]       = "https://api.devnet.solana.com",
    ["testnet"]      = "https://api.testnet.solana.com",
    ["localnet"]     = "http://127.0.0.1:8899",
}

-- ---
-- Constructor
-- ---

function SolanaRPC.new(endpointOrCluster, options)
    local self = setmetatable({}, SolanaRPC)
    self.endpoint = CLUSTER_ENDPOINTS[endpointOrCluster] or endpointOrCluster
    self.commitment = (options and options.commitment) or "confirmed"
    self.requestId = 0
    self.timeout = (options and options.timeout) or 10000
    return self
end

-- ---
-- Internal: JSON-RPC call via fetchRemote
-- ---

function SolanaRPC:_call(method, params, callback)
    self.requestId = self.requestId + 1

    local payload = toJSON({
        jsonrpc = "2.0",
        id = self.requestId,
        method = method,
        params = params or {},
    })

    fetchRemote(self.endpoint, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
        },
        postData = payload,
        connectionAttempts = 3,
        connectTimeout = self.timeout,
    }, function(responseData, responseInfo)
        if responseInfo.statusCode ~= 200 then
            if callback then
                callback(nil, "HTTP " .. tostring(responseInfo.statusCode) .. ": " .. tostring(responseData))
            end
            return
        end

        local decoded = fromJSON(responseData)
        if not decoded then
            if callback then
                callback(nil, "Failed to parse JSON response")
            end
            return
        end

        if decoded.error then
            if callback then
                callback(nil, "RPC Error [" .. tostring(decoded.error.code) .. "]: " .. tostring(decoded.error.message))
            end
            return
        end

        if callback then
            callback(decoded.result)
        end
    end)
end

-- ---
-- Account Methods
-- ---

function SolanaRPC:getBalance(address, callback, commitment)
    self:_call("getBalance", {
        address,
        { commitment = commitment or self.commitment },
    }, callback)
end

function SolanaRPC:getAccountInfo(address, callback, options)
    options = options or {}
    self:_call("getAccountInfo", {
        address,
        {
            commitment = options.commitment or self.commitment,
            encoding = options.encoding or "base64",
        },
    }, callback)
end

function SolanaRPC:getMultipleAccounts(addresses, callback, options)
    options = options or {}
    self:_call("getMultipleAccounts", {
        addresses,
        {
            commitment = options.commitment or self.commitment,
            encoding = options.encoding or "base64",
        },
    }, callback)
end

-- ---
-- Token Methods (SPL Token)
-- ---

function SolanaRPC:getTokenAccountBalance(tokenAccount, callback, commitment)
    self:_call("getTokenAccountBalance", {
        tokenAccount,
        { commitment = commitment or self.commitment },
    }, callback)
end

function SolanaRPC:getTokenAccountsByOwner(owner, filter, callback, options)
    options = options or {}
    -- filter = { mint = "..." } or { programId = "..." }
    self:_call("getTokenAccountsByOwner", {
        owner,
        filter,
        {
            commitment = options.commitment or self.commitment,
            encoding = options.encoding or "jsonParsed",
        },
    }, callback)
end

function SolanaRPC:getTokenSupply(mint, callback, commitment)
    self:_call("getTokenSupply", {
        mint,
        { commitment = commitment or self.commitment },
    }, callback)
end

-- ---
-- Transaction Methods
-- ---

function SolanaRPC:getTransaction(signature, callback, options)
    options = options or {}
    self:_call("getTransaction", {
        signature,
        {
            commitment = options.commitment or self.commitment,
            encoding = options.encoding or "jsonParsed",
            maxSupportedTransactionVersion = options.maxSupportedTransactionVersion or 0,
        },
    }, callback)
end

function SolanaRPC:getSignaturesForAddress(address, callback, options)
    options = options or {}
    local params = {
        commitment = options.commitment or self.commitment,
    }
    if options.limit then params.limit = options.limit end
    if options.before then params.before = options.before end
    if options.until_ then params["until"] = options.until_ end

    self:_call("getSignaturesForAddress", { address, params }, callback)
end

function SolanaRPC:getSignatureStatuses(signatures, callback, options)
    options = options or {}
    self:_call("getSignatureStatuses", {
        signatures,
        { searchTransactionHistory = options.searchTransactionHistory or false },
    }, callback)
end

function SolanaRPC:sendTransaction(signedTxBase64, callback, options)
    options = options or {}
    self:_call("sendTransaction", {
        signedTxBase64,
        {
            encoding = "base64",
            preflightCommitment = options.preflightCommitment or self.commitment,
            skipPreflight = options.skipPreflight or false,
            maxRetries = options.maxRetries,
        },
    }, callback)
end

function SolanaRPC:simulateTransaction(txBase64, callback, options)
    options = options or {}
    self:_call("simulateTransaction", {
        txBase64,
        {
            commitment = options.commitment or self.commitment,
            encoding = "base64",
            sigVerify = options.sigVerify or false,
            replaceRecentBlockhash = options.replaceRecentBlockhash or true,
        },
    }, callback)
end

-- ---
-- Block & Slot Methods
-- ---

function SolanaRPC:getLatestBlockhash(callback, commitment)
    self:_call("getLatestBlockhash", {
        { commitment = commitment or self.commitment },
    }, callback)
end

function SolanaRPC:getBlockHeight(callback, commitment)
    self:_call("getBlockHeight", {
        { commitment = commitment or self.commitment },
    }, callback)
end

function SolanaRPC:getSlot(callback, commitment)
    self:_call("getSlot", {
        { commitment = commitment or self.commitment },
    }, callback)
end

function SolanaRPC:getBlock(slot, callback, options)
    options = options or {}
    self:_call("getBlock", {
        slot,
        {
            commitment = options.commitment or self.commitment,
            encoding = options.encoding or "jsonParsed",
            maxSupportedTransactionVersion = options.maxSupportedTransactionVersion or 0,
            transactionDetails = options.transactionDetails or "full",
        },
    }, callback)
end

function SolanaRPC:getBlockTime(slot, callback)
    self:_call("getBlockTime", { slot }, callback)
end

-- ---
-- Network / Cluster Info
-- ---

function SolanaRPC:getHealth(callback)
    self:_call("getHealth", {}, callback)
end

function SolanaRPC:getVersion(callback)
    self:_call("getVersion", {}, callback)
end

function SolanaRPC:getEpochInfo(callback, commitment)
    self:_call("getEpochInfo", {
        { commitment = commitment or self.commitment },
    }, callback)
end

function SolanaRPC:getSupply(callback, commitment)
    self:_call("getSupply", {
        { commitment = commitment or self.commitment },
    }, callback)
end

function SolanaRPC:getMinimumBalanceForRentExemption(dataLength, callback, commitment)
    self:_call("getMinimumBalanceForRentExemption", {
        dataLength,
        { commitment = commitment or self.commitment },
    }, callback)
end

function SolanaRPC:getRecentPrioritizationFees(addresses, callback)
    self:_call("getRecentPrioritizationFees", { addresses or {} }, callback)
end

-- ---
-- Airdrop (devnet/testnet only)
-- ---

function SolanaRPC:requestAirdrop(address, lamports, callback, commitment)
    self:_call("requestAirdrop", {
        address,
        lamports,
        { commitment = commitment or self.commitment },
    }, callback)
end

-- ---
-- Program Methods
-- ---

function SolanaRPC:getProgramAccounts(programId, callback, options)
    options = options or {}
    local config = {
        commitment = options.commitment or self.commitment,
        encoding = options.encoding or "base64",
    }
    if options.filters then
        config.filters = options.filters
    end
    if options.dataSlice then
        config.dataSlice = options.dataSlice
    end

    self:_call("getProgramAccounts", { programId, config }, callback)
end

-- ---
-- Lookup Table
-- ---

function SolanaRPC:getAddressLookupTable(address, callback, commitment)
    self:getAccountInfo(address, function(result, err)
        if err then
            if callback then callback(nil, err) end
            return
        end
        if callback then callback(result) end
    end, { commitment = commitment, encoding = "jsonParsed" })
end

-- ---
-- Utility
-- ---

function SolanaRPC:isBlockhashValid(blockhash, callback, commitment)
    self:_call("isBlockhashValid", {
        blockhash,
        { commitment = commitment or self.commitment },
    }, callback)
end

function SolanaRPC:getFeeForMessage(message, callback, commitment)
    self:_call("getFeeForMessage", {
        message,
        { commitment = commitment or self.commitment },
    }, callback)
end

-- Helper: lamports to SOL
function SolanaRPC.lamportsToSol(lamports)
    return lamports / 1000000000
end

-- Helper: SOL to lamports
function SolanaRPC.solToLamports(sol)
    return math.floor(sol * 1000000000)
end
