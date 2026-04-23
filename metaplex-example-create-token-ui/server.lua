-- https://github.com/yongsxyz
--[[
    Metaplex Token Creator - Server side.

    Responsibilities:
      * Relay UI requests (create / info / update / burn) to metaplex-sdk
      * Send wallet list from solana-sdk to the client on demand
      * Persist the list of tokens created PER WALLET ADDRESS to disk so the
        UI can show "my tokens" across sessions. Storage lives in
        "created_tokens.json" inside the resource folder and is keyed by
        wallet base58 address.
]]

local sol = exports["solana-sdk"]
local mp  = exports["metaplex-sdk"]

-- ---
-- Per-wallet persistent store of tokens the user has minted.
-- Schema:
--   { ["<walletAddress>"] = { { mint, name, symbol, uri, decimals,
--                                supply, signature, createdAt } } }
-- ---

local STORE_FILE = "created_tokens.json"
local store = {}

local function loadStore()
    if not fileExists(STORE_FILE) then
        store = {}
        return
    end
    local f = fileOpen(STORE_FILE, true)
    if not f then store = {}; return end
    local content = fileRead(f, fileGetSize(f))
    fileClose(f)
    store = (content and content ~= "" and fromJSON(content)) or {}
end

local function saveStore()
    if fileExists(STORE_FILE) then fileDelete(STORE_FILE) end
    local f = fileCreate(STORE_FILE)
    if not f then return end
    fileWrite(f, toJSON(store))
    fileClose(f)
end

local function recordToken(walletAddr, entry)
    store[walletAddr] = store[walletAddr] or {}
    -- De-dupe by mint
    for i, e in ipairs(store[walletAddr]) do
        if e.mint == entry.mint then
            store[walletAddr][i] = entry
            saveStore()
            return
        end
    end
    table.insert(store[walletAddr], 1, entry)  -- newest first
    saveStore()
end

local function updateTokenEntry(walletAddr, mint, patch)
    if not store[walletAddr] then return end
    for _, e in ipairs(store[walletAddr]) do
        if e.mint == mint then
            for k, v in pairs(patch) do e[k] = v end
            saveStore()
            return
        end
    end
end

local function removeTokenEntry(walletAddr, mint)
    if not store[walletAddr] then return end
    for i, e in ipairs(store[walletAddr]) do
        if e.mint == mint then
            table.remove(store[walletAddr], i)
            saveStore()
            return
        end
    end
end

-- ---
-- Pinata credentials. LEAVE BLANK in committed code.
-- Populate at runtime via chat: /mpipfskey <apiKey> <apiSecret>
-- (or /mpipfsjwt <jwt>). Grab free keys at
-- https://app.pinata.cloud/developers/api-keys
-- ---
local PINATA_API_KEY    = ""
local PINATA_API_SECRET = ""

addEventHandler("onResourceStart", resourceRoot, function()
    loadStore()

    -- Ensure solana-sdk is initialised (no-op if another resource already did).
    local status = sol:getClientStatus()
    if status ~= "ready" and status ~= "connecting" then
        sol:initClient({ cluster = "devnet", commitment = "confirmed" })
        outputDebugString("[mp-ui] solana-sdk initClient() (was: " .. tostring(status) .. ")")
    end

    -- Auto-configure Pinata so "Create Token" auto-uploads metadata.
    if PINATA_API_KEY ~= "" and PINATA_API_SECRET ~= "" then
        if mp:setIpfsPinataKey(PINATA_API_KEY, PINATA_API_SECRET) then
            outputDebugString("[mp-ui] Pinata auto-configured.")
        end
    end

    outputDebugString("[mp-ui] Store loaded.")
end)

-- ---
-- Helper: which wallets from solana-sdk can the player use?
-- The solana-sdk stores keys in-memory only; we simply mirror its list.
-- ---

addEvent("mpui:getWallets", true)
addEventHandler("mpui:getWallets", root, function()
    local wallets = sol:listWallets() or {}
    triggerClientEvent(client, "mpui:walletsData", resourceRoot, wallets)
end)

addEvent("mpui:getTokens", true)
addEventHandler("mpui:getTokens", root, function(walletAddr)
    local list = (walletAddr and store[walletAddr]) or {}
    triggerClientEvent(client, "mpui:tokensData", resourceRoot, walletAddr, list)
end)

-- ---
-- Create token (calls metaplex-sdk createAndMintFungible)
-- Payload: { wallet, name, symbol, uri, decimals, supply, bps }
-- ---

local _pending = {}   -- eventName -> player

local function eventName(prefix)
    return prefix .. "_" .. tostring(getTickCount()) .. "_" .. tostring(math.random(1, 1e9))
end

-- Accepts EITHER of two payload shapes:
--   (a) legacy: { wallet, name, symbol, uri, decimals, supply, bps }
--   (b) new:    { wallet, name, symbol, description, image, decimals, supply, bps }
-- When description/image are given (and no `uri`), the server builds the
-- Fungible Standard JSON and auto-uploads it to IPFS.
addEvent("mpui:createToken", true)
addEventHandler("mpui:createToken", root, function(opts)
    local player = client
    if not opts or not opts.wallet or not opts.name or not opts.symbol then
        triggerClientEvent(player, "mpui:createResult", resourceRoot, false,
            "Missing required field (wallet/name/symbol)")
        return
    end
    if not sol:hasWallet(opts.wallet) then
        triggerClientEvent(player, "mpui:createResult", resourceRoot, false,
            "Wallet not loaded in solana-sdk.")
        return
    end

    local decimals = tonumber(opts.decimals) or 9
    local supplyStr = tostring(opts.supply or "0"):gsub("^%+", "")
    if not supplyStr:match("^%d+$") then
        triggerClientEvent(player, "mpui:createResult", resourceRoot, false,
            "Supply must be a positive whole number")
        return
    end

    local autoPublish = (opts.description and opts.description ~= "")
                     or (opts.image and opts.image ~= "")
                     or (not opts.uri or opts.uri == "")

    if autoPublish then
        -- Need Pinata for auto-upload path
        local s = mp:getIpfsPinataStatus()
        if not s.configured then
            triggerClientEvent(player, "mpui:createResult", resourceRoot, false,
                "Pinata not configured (server). Ask admin to set PINATA_API_KEY.")
            return
        end
    end

    local evt = eventName("mpui_create")
    addEvent(evt, true)
    local handler
    handler = function(result, err)
        removeEventHandler(evt, resourceRoot, handler)
        if err then
            triggerClientEvent(player, "mpui:createResult", resourceRoot, false, tostring(err))
            return
        end
        recordToken(opts.wallet, {
            mint        = result.mint,
            metadata    = result.metadata,
            ata         = result.ata,
            name        = opts.name,
            symbol      = opts.symbol,
            description = opts.description,
            image       = opts.image,
            uri         = result.onChainUri or opts.uri,
            ipfsCid     = result.ipfsCid,
            decimals    = decimals,
            supply      = supplyStr,
            bps         = tonumber(opts.bps) or 0,
            signature   = result.signature,
            createdAt   = getRealTime().timestamp,
        })
        triggerClientEvent(player, "mpui:createResult", resourceRoot, true, result,
            store[opts.wallet] or {})
    end
    addEventHandler(evt, resourceRoot, handler)

    if autoPublish then
        mp:createAndPublishFungible({
            wallet               = opts.wallet,
            name                 = opts.name,
            symbol               = opts.symbol,
            description          = opts.description or "",
            image                = opts.image or "",
            decimals             = decimals,
            sellerFeeBasisPoints = tonumber(opts.bps) or 0,
            initialSupply        = supplyStr,
        }, evt, resourceRoot)
    else
        mp:createAndMintFungible({
            wallet               = opts.wallet,
            name                 = opts.name,
            symbol               = opts.symbol,
            uri                  = opts.uri,
            decimals             = decimals,
            sellerFeeBasisPoints = tonumber(opts.bps) or 0,
            initialSupply        = supplyStr,
        }, evt, resourceRoot)
    end
end)

-- ---
-- Fetch digital asset (metadata + mint info)
-- ---

addEvent("mpui:getAsset", true)
addEventHandler("mpui:getAsset", root, function(mintAddr)
    local player = client
    if not mintAddr then
        triggerClientEvent(player, "mpui:assetData", resourceRoot, false, "No mint provided")
        return
    end
    local evt = eventName("mpui_info")
    addEvent(evt, true)
    local handler
    handler = function(result, err)
        removeEventHandler(evt, resourceRoot, handler)
        if err then
            triggerClientEvent(player, "mpui:assetData", resourceRoot, false, tostring(err))
            return
        end
        triggerClientEvent(player, "mpui:assetData", resourceRoot, true, result)
    end
    addEventHandler(evt, resourceRoot, handler)
    mp:fetchDigitalAsset(mintAddr, evt, resourceRoot)
end)

-- ---
-- Update metadata
-- Payload: { wallet, mint, name, symbol, uri, bps }
-- ---

addEvent("mpui:updateToken", true)
addEventHandler("mpui:updateToken", root, function(opts)
    local player = client
    if not opts or not opts.wallet or not opts.mint then
        triggerClientEvent(player, "mpui:updateResult", resourceRoot, false, "Missing wallet/mint")
        return
    end
    if not sol:hasWallet(opts.wallet) then
        triggerClientEvent(player, "mpui:updateResult", resourceRoot, false,
            "Wallet not loaded in solana-sdk")
        return
    end

    local evt = eventName("mpui_update")
    addEvent(evt, true)
    local handler
    handler = function(result, err)
        removeEventHandler(evt, resourceRoot, handler)
        if err then
            triggerClientEvent(player, "mpui:updateResult", resourceRoot, false, tostring(err))
            return
        end
        -- Mirror the change into the local store
        updateTokenEntry(opts.wallet, opts.mint, {
            name   = (opts.name and opts.name ~= "") and opts.name or nil,
            symbol = (opts.symbol and opts.symbol ~= "") and opts.symbol or nil,
            uri    = (opts.uri and opts.uri ~= "") and opts.uri or nil,
            bps    = tonumber(opts.bps),
            updatedSignature = result.signature,
        })
        triggerClientEvent(player, "mpui:updateResult", resourceRoot, true, result,
            store[opts.wallet] or {})
    end
    addEventHandler(evt, resourceRoot, handler)

    local patch = {
        wallet = opts.wallet,
        mint   = opts.mint,
    }
    if opts.name and opts.name ~= ""   then patch.name   = opts.name end
    if opts.symbol and opts.symbol ~= "" then patch.symbol = opts.symbol end
    if opts.uri and opts.uri ~= ""     then patch.uri    = opts.uri end
    if opts.bps ~= nil then patch.sellerFeeBasisPoints = tonumber(opts.bps) end

    mp:updateMetadata(patch, evt, resourceRoot)
end)

-- ---
-- Burn tokens
-- Payload: { wallet, mint, humanAmount, decimals }
-- ---

addEvent("mpui:burnTokens", true)
addEventHandler("mpui:burnTokens", root, function(opts)
    local player = client
    if not opts or not opts.wallet or not opts.mint or not opts.humanAmount then
        triggerClientEvent(player, "mpui:burnResult", resourceRoot, false,
            "Missing wallet/mint/amount")
        return
    end
    if not sol:hasWallet(opts.wallet) then
        triggerClientEvent(player, "mpui:burnResult", resourceRoot, false,
            "Wallet not loaded in solana-sdk")
        return
    end

    local supplyStr = tostring(opts.humanAmount):gsub("^%+", "")
    if not supplyStr:match("^%d+$") or supplyStr == "0" then
        triggerClientEvent(player, "mpui:burnResult", resourceRoot, false,
            "Amount must be positive whole number")
        return
    end

    local decimals = tonumber(opts.decimals) or 9

    local evt = eventName("mpui_burn")
    addEvent(evt, true)
    local handler
    handler = function(result, err)
        removeEventHandler(evt, resourceRoot, handler)
        if err then
            triggerClientEvent(player, "mpui:burnResult", resourceRoot, false, tostring(err))
            return
        end
        triggerClientEvent(player, "mpui:burnResult", resourceRoot, true, result)
    end
    addEventHandler(evt, resourceRoot, handler)

    mp:burnTokens({
        wallet        = opts.wallet,
        mint          = opts.mint,
        initialSupply = supplyStr,
        decimals      = decimals,
    }, evt, resourceRoot)
end)

-- ---
-- Drop token from local list (doesn't touch chain)
-- ---

addEvent("mpui:removeLocalToken", true)
addEventHandler("mpui:removeLocalToken", root, function(walletAddr, mint)
    removeTokenEntry(walletAddr, mint)
    triggerClientEvent(client, "mpui:tokensData", resourceRoot, walletAddr,
        store[walletAddr] or {})
end)

-- ---
-- Auto token-icon fetcher.
-- Same pipeline as solana-example-wallet: mint → metadata URI → JSON → image bytes.
-- Server-side cache prevents duplicate fetches across players.
-- ---

local _imgCache = {}    -- [mint] = "fetching" | "ready" | "failed"
local _evtCount = 0
local function uniqueEvt(prefix)
    _evtCount = _evtCount + 1
    return prefix .. "_" .. tostring(getTickCount()) .. "_" .. tostring(_evtCount)
end

local function sendImageResult(player, mint, bytes, mime, err)
    if not isElement(player) then return end
    triggerClientEvent(player, "mpui:tokenImageData", resourceRoot,
        mint, bytes, mime, err)
end

addEvent("mpui:getTokenImage", true)
addEventHandler("mpui:getTokenImage", root, function(mint)
    local player = client
    if not mint or #mint < 30 then return end
    if _imgCache[mint] == "failed" then
        sendImageResult(player, mint, nil, nil, "previously failed")
        return
    end
    if _imgCache[mint] == "fetching" or _imgCache[mint] == "ready" then return end
    _imgCache[mint] = "fetching"

    local mEvt = uniqueEvt("mpui_meta")
    addEvent(mEvt, true)
    local mHandler
    mHandler = function(result, err)
        removeEventHandler(mEvt, resourceRoot, mHandler)
        if err or not result or not result.data then
            _imgCache[mint] = "failed"
            sendImageResult(player, mint, nil, nil, "no metadata")
            return
        end
        local uri = result.data.uri
        if not uri or uri == "" then
            _imgCache[mint] = "failed"
            sendImageResult(player, mint, nil, nil, "no uri")
            return
        end
        if uri:match("^ipfs://") then uri = "https://ipfs.io/ipfs/" .. uri:sub(8) end
        if not uri:match("^https?://") then
            _imgCache[mint] = "failed"
            sendImageResult(player, mint, nil, nil, "non-http uri")
            return
        end

        fetchRemote(uri, {
            method = "GET", connectionAttempts = 2, connectTimeout = 8000,
        }, function(jsonData, info)
            if not info or info.statusCode ~= 200 then
                _imgCache[mint] = "failed"
                sendImageResult(player, mint, nil, nil,
                    "json http " .. tostring(info and info.statusCode))
                return
            end
            local j = fromJSON(jsonData)
            if type(j) == "table" and j[1] and not j.image then j = j[1] end
            if not j or type(j) ~= "table" or not j.image or j.image == "" then
                _imgCache[mint] = "failed"
                sendImageResult(player, mint, nil, nil, "no image field")
                return
            end
            local imgUrl = j.image
            if imgUrl:match("^ipfs://") then
                imgUrl = "https://ipfs.io/ipfs/" .. imgUrl:sub(8)
            end
            if not imgUrl:match("^https?://") then
                _imgCache[mint] = "failed"
                sendImageResult(player, mint, nil, nil, "bad image url")
                return
            end

            fetchRemote(imgUrl, {
                method = "GET", connectionAttempts = 2, connectTimeout = 12000,
            }, function(imgData, imgInfo)
                if not imgInfo or imgInfo.statusCode ~= 200 then
                    _imgCache[mint] = "failed"
                    sendImageResult(player, mint, nil, nil,
                        "image http " .. tostring(imgInfo and imgInfo.statusCode))
                    return
                end
                local mime = "image/png"
                local lower = imgUrl:lower()
                if lower:match("%.jpe?g") then mime = "image/jpeg"
                elseif lower:match("%.gif") then mime = "image/gif" end
                _imgCache[mint] = "ready"
                sendImageResult(player, mint, imgData, mime, nil)
            end)
        end)
    end
    addEventHandler(mEvt, resourceRoot, mHandler)
    mp:fetchMetadata(mint, mEvt, resourceRoot)
end)
