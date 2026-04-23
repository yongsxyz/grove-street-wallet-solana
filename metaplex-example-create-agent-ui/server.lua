-- https://github.com/yongsxyz
--[[
    Metaplex Agent Creator - Server side.

    Responsibilities:
      * Relay UI requests (create / list / info / deposit) to metaplex-sdk.
      * Persist the agent list per wallet (in created_agents.json).
      * Auto-initialize solana-sdk + Pinata on resource start.
]]

local sol = exports["solana-sdk"]
local mp  = exports["metaplex-sdk"]

-- ---
-- Pinata credentials. LEAVE BLANK in committed code.
-- Populate at runtime via chat: /mpipfskey <apiKey> <apiSecret>
-- (or /mpipfsjwt <jwt>). Grab free keys at
-- https://app.pinata.cloud/developers/api-keys
-- ---
local PINATA_API_KEY    = ""
local PINATA_API_SECRET = ""

-- ---
-- Persistent agent store: one entry per agent, keyed by wallet address.
-- Schema:
--   store[walletAddr] = {
--     { agent, collection, agentIdentityPda, agentSigner, name, description,
--       image, ipfsCid, onChainUri, signature, createdAt }, ...
--   }
-- ---
local STORE_FILE = "created_agents.json"
local store = {}

local function loadStore()
    if not fileExists(STORE_FILE) then store = {}; return end
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

local function recordAgent(walletAddr, entry)
    store[walletAddr] = store[walletAddr] or {}
    for i, e in ipairs(store[walletAddr]) do
        if e.agent == entry.agent then
            store[walletAddr][i] = entry
            saveStore()
            return
        end
    end
    table.insert(store[walletAddr], 1, entry)
    saveStore()
end

local function removeAgentEntry(walletAddr, agent)
    if not store[walletAddr] then return end
    for i, e in ipairs(store[walletAddr]) do
        if e.agent == agent then
            table.remove(store[walletAddr], i)
            saveStore()
            return
        end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    loadStore()

    local status = sol:getClientStatus()
    if status ~= "ready" and status ~= "connecting" then
        sol:initClient({ cluster = "devnet", commitment = "confirmed" })
        outputDebugString("[mp-agent-ui] solana-sdk initClient() (was: " ..
            tostring(status) .. ")")
    end

    if PINATA_API_KEY ~= "" and PINATA_API_SECRET ~= "" then
        if mp:setIpfsPinataKey(PINATA_API_KEY, PINATA_API_SECRET) then
            outputDebugString("[mp-agent-ui] Pinata auto-configured.")
        end
    end

    outputDebugString("[mp-agent-ui] Store loaded.")
end)

-- ---
-- Event name helper
-- ---

local function eventName(prefix)
    return prefix .. "_" .. tostring(getTickCount()) .. "_" .. tostring(math.random(1, 1e9))
end

-- ---
-- Wallet list + agent list
-- ---

addEvent("mpaui:getWallets", true)
addEventHandler("mpaui:getWallets", root, function()
    triggerClientEvent(client, "mpaui:walletsData", resourceRoot, sol:listWallets() or {})
end)

addEvent("mpaui:getAgents", true)
addEventHandler("mpaui:getAgents", root, function(walletAddr)
    local list = (walletAddr and store[walletAddr]) or {}
    triggerClientEvent(client, "mpaui:agentsData", resourceRoot, walletAddr, list)
end)

-- ---
-- Create Agent (MPL Core + Agent Registry, atomic)
-- Payload: { wallet, name, description, image }
-- ---

addEvent("mpaui:createAgent", true)
addEventHandler("mpaui:createAgent", root, function(opts)
    local player = client
    if not opts or not opts.wallet or not opts.name or not opts.description then
        triggerClientEvent(player, "mpaui:createResult", resourceRoot, false,
            "Missing wallet/name/description")
        return
    end
    if not sol:hasWallet(opts.wallet) then
        triggerClientEvent(player, "mpaui:createResult", resourceRoot, false,
            "Wallet not loaded in solana-sdk.")
        return
    end
    local s = mp:getIpfsPinataStatus()
    if not s.configured then
        triggerClientEvent(player, "mpaui:createResult", resourceRoot, false,
            "Pinata not configured server-side.")
        return
    end

    local evt = eventName("mpaui_create")
    addEvent(evt, true)
    local handler
    handler = function(result, err)
        removeEventHandler(evt, resourceRoot, handler)
        if err then
            triggerClientEvent(player, "mpaui:createResult", resourceRoot, false, tostring(err))
            return
        end
        recordAgent(opts.wallet, {
            agent            = result.agent,
            collection       = result.collection,
            agentIdentityPda = result.agentIdentityPda,
            agentSigner      = result.agentSigner,
            name             = opts.name,
            description      = opts.description,
            image            = opts.image or "",
            ipfsCid          = result.ipfsCid,
            onChainUri       = result.onChainUri,
            signature        = result.signature,
            metaplexUrl      = result.metaplexUrl,
            createdAt        = getRealTime().timestamp,
        })
        triggerClientEvent(player, "mpaui:createResult", resourceRoot, true, result,
            store[opts.wallet] or {})
    end
    addEventHandler(evt, resourceRoot, handler)

    -- Pass services through as-is. The SDK's buildAgentRegistrationJson
    -- auto-fills the "web" endpoint when it's left blank, so the UI can
    -- always send web with empty endpoint to signal "use default".
    -- Other services are expected to have endpoints filled by the user.
    local services = nil
    if opts.services and #opts.services > 0 then services = opts.services end

    mp:createAgent({
        wallet         = opts.wallet,
        name           = opts.name,
        description    = opts.description,
        image          = opts.image or "",
        services       = services,                  -- nil = default (web auto)
        supportedTrust = opts.supportedTrust,       -- array of strings
        x402Support    = opts.x402Support == true,
    }, evt, resourceRoot)
end)

-- ---
-- Deposit SOL to agent's built-in wallet (Asset Signer PDA)
-- Payload: { wallet, agentSigner, amount } (amount in SOL, float)
-- ---

addEvent("mpaui:depositSol", true)
addEventHandler("mpaui:depositSol", root, function(opts)
    local player = client
    if not opts or not opts.wallet or not opts.agentSigner or not opts.amount then
        triggerClientEvent(player, "mpaui:depositResult", resourceRoot, false,
            "Missing wallet/agentSigner/amount")
        return
    end
    if not sol:hasWallet(opts.wallet) then
        triggerClientEvent(player, "mpaui:depositResult", resourceRoot, false,
            "Wallet not loaded.")
        return
    end

    local amt = tonumber(opts.amount)
    if not amt or amt <= 0 then
        triggerClientEvent(player, "mpaui:depositResult", resourceRoot, false,
            "Amount must be positive")
        return
    end

    local evt = eventName("mpaui_deposit")
    addEvent(evt, true)
    local handler
    handler = function(result, err)
        removeEventHandler(evt, resourceRoot, handler)
        if err then
            triggerClientEvent(player, "mpaui:depositResult", resourceRoot, false, tostring(err))
            return
        end
        triggerClientEvent(player, "mpaui:depositResult", resourceRoot, true, result)
    end
    addEventHandler(evt, resourceRoot, handler)

    sol:transferSOL(opts.wallet, opts.agentSigner, amt, evt, resourceRoot)
end)

-- ---
-- Get SOL balance of an arbitrary address (used for agent PDA balance)
-- ---

addEvent("mpaui:getBalance", true)
addEventHandler("mpaui:getBalance", root, function(addr)
    local player = client
    local evt = eventName("mpaui_bal")
    addEvent(evt, true)
    local handler
    handler = function(result, err)
        removeEventHandler(evt, resourceRoot, handler)
        if err then
            triggerClientEvent(player, "mpaui:balanceData", resourceRoot, addr, nil, tostring(err))
            return
        end
        triggerClientEvent(player, "mpaui:balanceData", resourceRoot, addr,
            result and result.sol or 0, nil)
    end
    addEventHandler(evt, resourceRoot, handler)
    sol:fetchBalance(addr, evt, resourceRoot)
end)

-- ---
-- Forget an agent from local list (doesn't touch chain)
-- ---

addEvent("mpaui:forgetAgent", true)
addEventHandler("mpaui:forgetAgent", root, function(walletAddr, agent)
    removeAgentEntry(walletAddr, agent)
    triggerClientEvent(client, "mpaui:agentsData", resourceRoot, walletAddr,
        store[walletAddr] or {})
end)

-- ---
-- Auto agent-icon fetcher (mirrors the token UI pattern).
--
-- NOTE: MPL Core assets are NOT the same as Token Metadata mints. The metaplex-sdk's
-- fetchMetadata only works for Token Metadata accounts. MPL Core agents don't have
-- those. We *could* fetch the asset's on-chain URI via MPL Core, but simpler for now:
-- use the URI stored in our own local `created_agents.json` (filled at creation time)
-- as the source of truth.
-- ---

local _imgCache = {}       -- [agent] = "fetching" | "ready" | "failed"

local function sendImageResult(player, agent, bytes, mime, err)
    if not isElement(player) then return end
    triggerClientEvent(player, "mpaui:agentImageData", resourceRoot,
        agent, bytes, mime, err)
end

-- Find the stored on-chain URI for an agent across all wallets
local function findAgentUri(agent)
    for _, list in pairs(store) do
        for _, e in ipairs(list) do
            if e.agent == agent then
                return e.onChainUri, e.image
            end
        end
    end
    return nil, nil
end

addEvent("mpaui:getAgentImage", true)
addEventHandler("mpaui:getAgentImage", root, function(agent)
    local player = client
    if not agent then return end
    if _imgCache[agent] == "failed" then
        sendImageResult(player, agent, nil, nil, "previously failed")
        return
    end
    if _imgCache[agent] == "fetching" or _imgCache[agent] == "ready" then return end
    _imgCache[agent] = "fetching"

    -- Look up the registration JSON URI we saved during creation.
    local uri, directImage = findAgentUri(agent)

    -- If the entry stored a direct image URL already, we can short-circuit.
    local function downloadImage(imgUrl)
        if imgUrl:match("^ipfs://") then
            imgUrl = "https://ipfs.io/ipfs/" .. imgUrl:sub(8)
        end
        if not imgUrl:match("^https?://") then
            _imgCache[agent] = "failed"
            sendImageResult(player, agent, nil, nil, "bad image url")
            return
        end
        fetchRemote(imgUrl, {
            method = "GET", connectionAttempts = 2, connectTimeout = 12000,
        }, function(imgData, imgInfo)
            if not imgInfo or imgInfo.statusCode ~= 200 then
                _imgCache[agent] = "failed"
                sendImageResult(player, agent, nil, nil,
                    "image http " .. tostring(imgInfo and imgInfo.statusCode))
                return
            end
            local mime = "image/png"
            local lower = imgUrl:lower()
            if lower:match("%.jpe?g") then mime = "image/jpeg"
            elseif lower:match("%.gif") then mime = "image/gif" end
            _imgCache[agent] = "ready"
            sendImageResult(player, agent, imgData, mime, nil)
        end)
    end

    -- Path A: we have a direct image URL in the store (image field)
    if directImage and directImage ~= "" then
        downloadImage(directImage)
        return
    end

    -- Path B: pull the registration JSON from the stored URI, then the image
    if not uri or uri == "" then
        _imgCache[agent] = "failed"
        sendImageResult(player, agent, nil, nil, "no uri / no image stored")
        return
    end
    if uri:match("^ipfs://") then uri = "https://ipfs.io/ipfs/" .. uri:sub(8) end
    if not uri:match("^https?://") then
        _imgCache[agent] = "failed"
        sendImageResult(player, agent, nil, nil, "non-http uri")
        return
    end

    fetchRemote(uri, {
        method = "GET", connectionAttempts = 2, connectTimeout = 8000,
    }, function(jsonData, info)
        if not info or info.statusCode ~= 200 then
            _imgCache[agent] = "failed"
            sendImageResult(player, agent, nil, nil,
                "json http " .. tostring(info and info.statusCode))
            return
        end
        local j = fromJSON(jsonData)
        if type(j) == "table" and j[1] and not j.image then j = j[1] end
        if not j or type(j) ~= "table" or not j.image or j.image == "" then
            _imgCache[agent] = "failed"
            sendImageResult(player, agent, nil, nil, "no image field")
            return
        end
        downloadImage(j.image)
    end)
end)
