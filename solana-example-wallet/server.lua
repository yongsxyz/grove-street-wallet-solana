-- https://github.com/yongsxyz
--[[
    Solana Dapps - Server Side
    Grove Street Wallet - Server (SQLite + encrypted keys)
]]

local sol = exports["solana-sdk"]
local db = nil

-- Track current network per player
local playerNetwork = {}

-- ---
-- PRICE FEED (CoinGecko)
-- ---
local prices = {
    sol_usd = 0,
    sol_idr = 0,
    usdc_usd = 1,
    usdc_idr = 16200,
}

local function fetchPrices()
    -- SOL/USD
    fetchRemote("https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=usd", {
        method = "GET", connectionAttempts = 2, connectTimeout = 8000,
    }, function(data, info)
        if info.statusCode == 200 then
            local j = fromJSON(data)
            if j and j.solana and j.solana.usd then
                prices.sol_usd = j.solana.usd
                outputDebugString("[solana-example-wallet] SOL/USD: $" .. tostring(prices.sol_usd))
            end
        end
    end)
    -- SOL/IDR
    fetchRemote("https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=idr", {
        method = "GET", connectionAttempts = 2, connectTimeout = 8000,
    }, function(data, info)
        if info.statusCode == 200 then
            local j = fromJSON(data)
            if j and j.solana and j.solana.idr then
                prices.sol_idr = j.solana.idr
                outputDebugString("[solana-example-wallet] SOL/IDR: Rp" .. tostring(prices.sol_idr))
            end
        end
    end)
    -- USDC/USD
    fetchRemote("https://api.coingecko.com/api/v3/simple/price?ids=usd-coin&vs_currencies=usd", {
        method = "GET", connectionAttempts = 2, connectTimeout = 8000,
    }, function(data, info)
        if info.statusCode == 200 then
            local j = fromJSON(data)
            if j and j["usd-coin"] and j["usd-coin"].usd then
                prices.usdc_usd = j["usd-coin"].usd
            end
        end
    end)
    -- USDC/IDR
    fetchRemote("https://api.coingecko.com/api/v3/simple/price?ids=usd-coin&vs_currencies=idr", {
        method = "GET", connectionAttempts = 2, connectTimeout = 8000,
    }, function(data, info)
        if info.statusCode == 200 then
            local j = fromJSON(data)
            if j and j["usd-coin"] and j["usd-coin"].idr then
                prices.usdc_idr = j["usd-coin"].idr
                outputDebugString("[solana-example-wallet] USDC/IDR: Rp" .. tostring(prices.usdc_idr))
            end
        end
    end)
end

-- Client request prices
addEvent("sol:getPrices", true)
addEventHandler("sol:getPrices", root, function()
    triggerClientEvent(client, "sol:pricesData", resourceRoot, prices)
end)

-- ---
-- DATABASE
-- ---

addEventHandler("onResourceStart", resourceRoot, function()
    db = dbConnect("sqlite", "wallets.db")
    dbExec(db, [[CREATE TABLE IF NOT EXISTS wallets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dbid INTEGER NOT NULL,
        name TEXT DEFAULT 'My Wallet',
        address TEXT NOT NULL,
        encrypted_key TEXT NOT NULL,
        network TEXT DEFAULT 'devnet',
        is_default INTEGER DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )]])
    dbExec(db, "CREATE INDEX IF NOT EXISTS idx_dbid ON wallets(dbid)")
    outputDebugString("[solana-example-wallet] Database ready")
    -- Fetch prices on start + every 60 seconds
    fetchPrices()
    setTimer(fetchPrices, 60000, 0)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    if db then destroyElement(db) end
end)

-- ---
-- ENCRYPTION
-- ---

local function getEncryptionKey(player)
    local serial = getPlayerSerial(player)
    local dbid = getElementData(player, "dbid") or getPlayerSerial(player)
    local full = hash("sha256", tostring(serial) .. tostring(dbid) .. "solana-mta-salt-2024")
    return full:sub(1, 16), full:sub(17, 32)
end

local function encryptKey(player, privateKeyBase58)
    local key, iv = getEncryptionKey(player)
    local encrypted = encodeString("aes128", privateKeyBase58, { key = key, iv = iv })
    if not encrypted then return nil end
    return encodeString("base64", encrypted)
end

local function decryptKey(player, storedData)
    if not storedData or #storedData < 4 then return nil end
    local key, iv = getEncryptionKey(player)
    local encrypted = decodeString("base64", storedData)
    if not encrypted then return nil end
    return decodeString("aes128", encrypted, { key = key, iv = iv })
end

local function getDBID(player)
    return getElementData(player, "dbid") or getPlayerSerial(player)
end

-- ---
-- INIT CLIENT per request (ensures correct network)
-- ---

local function initForPlayer(player, network)
    network = network or playerNetwork[player] or "devnet"
    playerNetwork[player] = network
    sol:initClient({ cluster = network })
end

-- ---
-- WALLET CRUD
-- ---

local function getPlayerWallets(player, callback)
    dbQuery(function(qh)
        callback(dbPoll(qh, 0) or {})
    end, db, "SELECT id, name, address, network, is_default, created_at FROM wallets WHERE dbid=? ORDER BY is_default DESC, id ASC", getDBID(player))
end

local function saveWallet(player, name, address, encKey, network)
    dbExec(db, "INSERT INTO wallets (dbid, name, address, encrypted_key, network) VALUES (?, ?, ?, ?, ?)",
        getDBID(player), name, address, encKey, network)
end

-- Get wallet list
addEvent("sol:getWallets", true)
addEventHandler("sol:getWallets", root, function()
    local player = client
    getPlayerWallets(player, function(wallets)
        triggerClientEvent(player, "sol:walletsData", resourceRoot, wallets)
    end)
end)

-- Create wallet
addEvent("sol:createWallet", true)
addEventHandler("sol:createWallet", root, function(name, network)
    local player = client
    initForPlayer(player, network)
    local address = sol:createWallet()
    if not address then
        triggerClientEvent(player, "sol:notify", resourceRoot, "Failed to create wallet", "error")
        return
    end
    -- Export key - try phantom format, fallback to hex
    local keyToStore = sol:exportWalletPhantom(address)
    if not keyToStore or #keyToStore < 20 then
        keyToStore = sol:exportWalletHex(address)
        outputDebugString("[solana-example-wallet] Using hex key format for " .. address:sub(1, 8))
    end
    if not keyToStore then
        triggerClientEvent(player, "sol:notify", resourceRoot, "Failed to export key", "error")
        return
    end
    local encrypted = encryptKey(player, keyToStore)
    saveWallet(player, name or "My Wallet", address, encrypted, network or "devnet")
    triggerClientEvent(player, "sol:notify", resourceRoot, "Wallet created!", "success")
    triggerClientEvent(player, "sol:walletCreated", resourceRoot, address, keyToStore)
    getPlayerWallets(player, function(w) triggerClientEvent(player, "sol:walletsData", resourceRoot, w) end)
end)

-- Create from mnemonic
addEvent("sol:createMnemonic", true)
addEventHandler("sol:createMnemonic", root, function(name, network)
    local player = client
    initForPlayer(player, network)
    local mnemonic, address = sol:generateMnemonic(12)
    if not mnemonic or not address then
        triggerClientEvent(player, "sol:notify", resourceRoot, "Failed to generate mnemonic", "error")
        return
    end
    local keyToStore = sol:exportWalletPhantom(address)
    if not keyToStore or #keyToStore < 20 then keyToStore = sol:exportWalletHex(address) end
    if not keyToStore then
        triggerClientEvent(player, "sol:notify", resourceRoot, "Failed to export key", "error")
        return
    end
    local encrypted = encryptKey(player, keyToStore)
    saveWallet(player, name or "My Wallet", address, encrypted, network or "devnet")
    triggerClientEvent(player, "sol:mnemonicResult", resourceRoot, mnemonic, address)
    getPlayerWallets(player, function(w) triggerClientEvent(player, "sol:walletsData", resourceRoot, w) end)
end)

-- Import wallet
addEvent("sol:importWallet", true)
addEventHandler("sol:importWallet", root, function(privateKey, name, network)
    local player = client
    initForPlayer(player, network)
    local address = sol:importWallet(privateKey)
    if not address then
        triggerClientEvent(player, "sol:notify", resourceRoot, "Import failed: invalid format", "error")
        return
    end
    local keyToStore = sol:exportWalletPhantom(address)
    if not keyToStore or #keyToStore < 20 then
        keyToStore = sol:exportWalletHex(address)
    end
    if not keyToStore then
        triggerClientEvent(player, "sol:notify", resourceRoot, "Failed to export key", "error")
        return
    end
    local encrypted = encryptKey(player, keyToStore)
    saveWallet(player, name or "Imported", address, encrypted, network or "devnet")
    triggerClientEvent(player, "sol:notify", resourceRoot, "Imported: " .. address:sub(1, 8) .. "...", "success")
    getPlayerWallets(player, function(w) triggerClientEvent(player, "sol:walletsData", resourceRoot, w) end)
end)

-- Delete wallet
addEvent("sol:deleteWallet", true)
addEventHandler("sol:deleteWallet", root, function(walletId)
    local player = client
    dbExec(db, "DELETE FROM wallets WHERE id=? AND dbid=?", walletId, getDBID(player))
    triggerClientEvent(player, "sol:notify", resourceRoot, "Wallet deleted", "success")
    getPlayerWallets(player, function(w) triggerClientEvent(player, "sol:walletsData", resourceRoot, w) end)
end)

-- ---
-- FETCH DATA (per-player targeting)
-- ---

-- Balance
addEvent("sol:fetchBalance", true)
addEventHandler("sol:fetchBalance", root, function(address, network)
    local player = client
    initForPlayer(player, network)
    sol:fetchBalance(address, "sol:onBalance_" .. getPlayerSerial(player), resourceRoot)
end)

-- Dynamic balance handler per player
addEventHandler("onResourceStart", resourceRoot, function()
    -- Register a catch-all pattern isn't possible, so we use a generic handler
end)

-- Generic balance callback - we use a shared event and track requesting player
local _balanceRequester = nil
addEvent("sol:fetchBalanceDirect", true)
addEventHandler("sol:fetchBalanceDirect", root, function(address, network)
    local player = client
    _balanceRequester = player
    initForPlayer(player, network)
    sol:fetchBalance(address, "sol:onBalanceCB", resourceRoot)
end)

addEvent("sol:onBalanceCB", true)
addEventHandler("sol:onBalanceCB", resourceRoot, function(result, err)
    if _balanceRequester and isElement(_balanceRequester) then
        triggerClientEvent(_balanceRequester, "sol:balanceData", resourceRoot, result, err)
    end
end)

-- Override the original fetchBalance to use direct version
addEventHandler("sol:fetchBalance", root, function(address, network)
    local player = client
    _balanceRequester = player
    initForPlayer(player, network)
    sol:fetchBalance(address, "sol:onBalanceCB", resourceRoot)
end, true, "low")

-- Tokens
local _tokenRequester = nil
addEvent("sol:fetchTokens", true)
addEventHandler("sol:fetchTokens", root, function(address, network)
    local player = client
    _tokenRequester = player
    initForPlayer(player, network)
    sol:getTokensByOwner(address, nil, "sol:onTokensCB", resourceRoot)
end)

addEvent("sol:onTokensCB", true)
addEventHandler("sol:onTokensCB", resourceRoot, function(tokens, err)
    if _tokenRequester and isElement(_tokenRequester) then
        triggerClientEvent(_tokenRequester, "sol:tokensData", resourceRoot, tokens, err)
    end
end)

-- TX History
local _historyRequester = nil
addEvent("sol:fetchHistory", true)
addEventHandler("sol:fetchHistory", root, function(address, network, limit)
    local player = client
    _historyRequester = player
    initForPlayer(player, network)
    sol:getTransactionHistory(address, { limit = limit or 5 }, "sol:onHistoryCB", resourceRoot)
end)

addEvent("sol:onHistoryCB", true)
addEventHandler("sol:onHistoryCB", resourceRoot, function(txs, err)
    if _historyRequester and isElement(_historyRequester) then
        triggerClientEvent(_historyRequester, "sol:historyData", resourceRoot, txs, err)
    end
end)

-- ---
-- HELPER: load wallet from DB (decrypt + import to SDK)
-- ---

local function loadWalletFromDB(player, walletId, network, callback)
    local dbid = getDBID(player)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not rows or #rows == 0 then
            callback(nil, "Wallet not found")
            return
        end
        local privateKey = decryptKey(player, rows[1].encrypted_key)
        if not privateKey or #privateKey < 10 then
            callback(nil, "Failed to decrypt key")
            return
        end
        privateKey = privateKey:gsub("%s+", ""):gsub("%z+", "")
        initForPlayer(player, network)
        local addr = sol:importWallet(privateKey)
        if not addr then
            if rows[1].address and sol:hasWallet(rows[1].address) then
                addr = rows[1].address
            end
        end
        if not addr then
            callback(nil, "Import failed. Delete and recreate wallet.")
            return
        end
        callback(addr)
    end, db, "SELECT address, encrypted_key FROM wallets WHERE id=? AND dbid=?", walletId, dbid)
end

-- ---
-- SEND SOL
-- ---

local _sendRequester = nil
addEvent("sol:sendSOL", true)
addEventHandler("sol:sendSOL", root, function(walletId, toAddress, amount, network)
    local player = client
    _sendRequester = player
    loadWalletFromDB(player, walletId, network, function(addr, err)
        if not addr then
            triggerClientEvent(player, "sol:notify", resourceRoot, err or "Failed to load wallet", "error")
            return
        end
        sol:transferSOL(addr, toAddress, tonumber(amount), "sol:onSendCB", resourceRoot)
    end)
end)

addEvent("sol:onSendCB", true)
addEventHandler("sol:onSendCB", resourceRoot, function(result, err)
    if not _sendRequester or not isElement(_sendRequester) then return end
    if err then
        triggerClientEvent(_sendRequester, "sol:notify", resourceRoot, "Transfer failed: " .. tostring(err), "error")
    else
        triggerClientEvent(_sendRequester, "sol:notify", resourceRoot, "Success! Sig: " .. tostring(result.signature):sub(1, 16) .. "...", "success")
    end
    triggerClientEvent(_sendRequester, "sol:sendDone", resourceRoot, result, err)
end)

-- Send SPL Token (auto-create ATA for receiver, detect Token/Token-2022)
local _pendingTokenSend = nil
addEvent("sol:sendToken", true)
addEventHandler("sol:sendToken", root, function(walletId, sourceTokenAccount, toAddress, uiAmount, mint, decimals, tokenProgramId, network)
    local player = client
    _sendRequester = player
    decimals = tonumber(decimals) or 0
    local rawAmount = math.floor(tonumber(uiAmount) * (10 ^ decimals))

    -- Detect token program: query the source token account to get its owner (= token program)
    initForPlayer(player, network)
    sol:fetchAccount(sourceTokenAccount, "sol:onDetectProgram", resourceRoot)
    _pendingTokenSend = {
        walletId = walletId,
        source = sourceTokenAccount,
        dest = toAddress,
        mint = mint,
        amount = rawAmount,
        tokenProgram = tokenProgramId,
        network = network,
    }
end)

addEvent("sol:onDetectProgram", true)
addEventHandler("sol:onDetectProgram", resourceRoot, function(result, err)
    if not _pendingTokenSend then return end
    local ps = _pendingTokenSend
    _pendingTokenSend = nil

    -- Detect program from account owner
    local detectedProgram = ps.tokenProgram
    if result and result.owner then
        detectedProgram = result.owner
        outputDebugString("[solana-example-wallet] Detected token program: " .. tostring(detectedProgram):sub(1, 12))
    end
    if not detectedProgram or #tostring(detectedProgram) < 30 then
        detectedProgram = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
    end

    outputDebugString("[solana-example-wallet] Token send: program=" .. detectedProgram:sub(1, 12) .. " raw=" .. ps.amount)

    loadWalletFromDB(_sendRequester, ps.walletId, ps.network, function(addr, loadErr)
        if not addr then
            if _sendRequester and isElement(_sendRequester) then
                triggerClientEvent(_sendRequester, "sol:notify", resourceRoot, loadErr or "Failed to load wallet", "error")
            end
            return
        end
        sol:transferTokenToWallet(addr, ps.source, ps.dest, ps.mint, ps.amount, detectedProgram, "sol:onSendCB", resourceRoot)
    end)
end)

-- Fetch full TX detail
local _txDetailRequester = nil
addEvent("sol:fetchTxDetail", true)
addEventHandler("sol:fetchTxDetail", root, function(signature, network)
    local player = client
    _txDetailRequester = player
    initForPlayer(player, network)
    sol:getTransaction(signature, "sol:onTxDetailCB", resourceRoot)
end)

addEvent("sol:onTxDetailCB", true)
addEventHandler("sol:onTxDetailCB", resourceRoot, function(result, err)
    if _txDetailRequester and isElement(_txDetailRequester) then
        triggerClientEvent(_txDetailRequester, "sol:txDetailData", resourceRoot, result, err)
    end
end)

-- Export key
-- Strip PKCS7 padding from AES decrypt result
local function stripPadding(str)
    if not str or #str == 0 then return str end
    local lastByte = string.byte(str, #str)
    if lastByte >= 1 and lastByte <= 16 then
        -- Check if last N bytes are all the same value (PKCS7)
        local valid = true
        for i = #str - lastByte + 1, #str do
            if string.byte(str, i) ~= lastByte then valid = false; break end
        end
        if valid then
            str = str:sub(1, #str - lastByte)
        end
    end
    return str
end

-- Clean key: remove all non-printable chars
local function cleanKey(str)
    if not str then return nil end
    str = stripPadding(str)
    -- Keep only printable ASCII (base58 chars)
    local clean = ""
    for i = 1, #str do
        local b = string.byte(str, i)
        if b >= 33 and b <= 126 then
            clean = clean .. string.char(b)
        end
    end
    return #clean > 10 and clean or nil
end

addEvent("sol:exportKey", true)
addEventHandler("sol:exportKey", root, function(walletId)
    local player = client
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not rows or #rows == 0 then
            triggerClientEvent(player, "sol:exportData", resourceRoot, nil, "Wallet not found")
            return
        end
        local raw = decryptKey(player, rows[1].encrypted_key)
        local privateKey = cleanKey(raw)
        if not privateKey then
            -- Fallback: just send the address so user knows which wallet
            triggerClientEvent(player, "sol:exportData", resourceRoot, nil,
                "Decrypt failed. Delete & recreate wallet.")
            return
        end
        outputDebugString("[solana-example-wallet] Export key len=" .. #privateKey .. " first6=" .. privateKey:sub(1,6))
        triggerClientEvent(player, "sol:exportData", resourceRoot, privateKey)
    end, db, "SELECT encrypted_key FROM wallets WHERE id=? AND dbid=?", walletId, getDBID(player))
end)

-- Cleanup
addEventHandler("onPlayerQuit", root, function()
    playerNetwork[source] = nil
end)
