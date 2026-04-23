-- https://github.com/yongsxyz
--[[
    Metaplex SDK - IPFS upload helper (Pinata).

    Why Pinata:
      * Free tier (1GB) — more than enough for thousands of agent JSONs.
      * pinJSONToIPFS endpoint accepts a plain JSON body, no multipart upload
        wrangling — works trivially with MTA's fetchRemote.
      * Returns a CID immediately. The CID is content-addressed, so retrieval
        works through ANY public IPFS gateway (ipfs.io, dweb.link, cloudflare,
        pinata's own gateway, etc.).

    Authentication:
      * Get a free JWT from https://app.pinata.cloud/developers/api-keys
      * Configure once per server session via setIpfsPinataJwt(jwt). The JWT
        is held in server-side Lua memory only (NOT persisted to disk by this
        module — caller can persist via MTA settings if desired).

    Read-side (no auth required):
      * Use ipfsToHttps(uri) or ipfsCidToHttps(cid) to convert ipfs:// or
        bare CIDs to a public HTTPS gateway URL. Useful for displaying or
        verifying uploaded content.
]]

MetaplexIpfs = {}

-- Pinata v1 endpoints (pinJSONToIPFS, pinFileToIPFS, data/testAuthentication)
-- accept EITHER auth method:
--   (A) Bearer JWT       → Authorization: Bearer <jwt>
--   (B) Key + Secret     → pinata_api_key: <key>  +  pinata_secret_api_key: <secret>
-- We keep both in memory and prefer whichever was set last.

local _pinataJwt = nil
local _pinataKey = nil
local _pinataSecret = nil
local _authMode = nil  -- "jwt" | "key" | nil

local function mask(s)
    if not s then return nil end
    if #s <= 12 then return string.rep("*", #s) end
    return s:sub(1, 6) .. "..." .. s:sub(-4)
end

function MetaplexIpfs.setPinataJwt(jwt)
    if jwt == "" then jwt = nil end
    _pinataJwt = jwt
    if jwt then
        _authMode = "jwt"
        -- Clear key/secret to avoid ambiguity
        _pinataKey, _pinataSecret = nil, nil
    end
    return _pinataJwt ~= nil
end

function MetaplexIpfs.setPinataKey(apiKey, apiSecret)
    if apiKey == "" then apiKey = nil end
    if apiSecret == "" then apiSecret = nil end
    _pinataKey = apiKey
    _pinataSecret = apiSecret
    if apiKey and apiSecret then
        _authMode = "key"
        _pinataJwt = nil -- clear JWT to avoid ambiguity
        return true
    end
    return false
end

function MetaplexIpfs.clearPinataAuth()
    _pinataJwt, _pinataKey, _pinataSecret, _authMode = nil, nil, nil, nil
end

function MetaplexIpfs.hasPinataAuth()
    return _authMode ~= nil
end

-- Back-compat alias
function MetaplexIpfs.hasPinataJwt()
    return _authMode ~= nil
end

function MetaplexIpfs.authInfo()
    return {
        configured = _authMode ~= nil,
        mode       = _authMode,
        jwt        = _pinataJwt and mask(_pinataJwt) or nil,
        apiKey     = _pinataKey and mask(_pinataKey) or nil,
        apiSecret  = _pinataSecret and mask(_pinataSecret) or nil,
    }
end

function MetaplexIpfs.maskedJwt()
    local info = MetaplexIpfs.authInfo()
    if info.mode == "jwt" then return info.jwt end
    if info.mode == "key" then return "key:" .. tostring(info.apiKey) end
    return nil
end

-- Build the auth headers for whichever credential is configured.
local function authHeaders()
    if _authMode == "jwt" and _pinataJwt then
        return { ["Authorization"] = "Bearer " .. _pinataJwt }
    elseif _authMode == "key" and _pinataKey and _pinataSecret then
        return {
            ["pinata_api_key"]        = _pinataKey,
            ["pinata_secret_api_key"] = _pinataSecret,
        }
    end
    return nil
end

-- ---
-- Public IPFS gateways. We expose several so the caller can pick whichever
-- their downstream consumers prefer. The CID is content-addressed, so all
-- of these return identical bytes for a given CID.
-- ---

local GATEWAYS = {
    ipfs_io     = "https://ipfs.io/ipfs/",
    pinata      = "https://gateway.pinata.cloud/ipfs/",
    dweb        = "https://dweb.link/ipfs/",
    cloudflare  = "https://cloudflare-ipfs.com/ipfs/",
    nftstorage  = "https://nftstorage.link/ipfs/",
    web3storage = "https://w3s.link/ipfs/",
}

function MetaplexIpfs.gateways(cid)
    local out = {}
    for k, prefix in pairs(GATEWAYS) do out[k] = prefix .. cid end
    return out
end

-- Convert an ipfs:// URI (or bare CID) to a public HTTPS gateway URL.
-- Default gateway is ipfs.io which is the most stable cross-resolver.
function MetaplexIpfs.toHttps(uri, gateway)
    gateway = gateway or "ipfs_io"
    local prefix = GATEWAYS[gateway] or GATEWAYS.ipfs_io
    if type(uri) ~= "string" then return nil end
    -- Already an HTTPS gateway URL?
    if uri:match("^https?://") then return uri end
    -- ipfs://<cid>[/path]
    local cidPath = uri:match("^ipfs://(.+)")
    if cidPath then return prefix .. cidPath end
    -- Bare CID
    return prefix .. uri
end

-- ---
-- Upload a JSON string to IPFS via Pinata. The string MUST be valid JSON
-- (we re-parse it before forwarding so Pinata gets a JSON object, not a
-- quoted string).
--
-- callback: function(result, errString)
-- result on success: {
--     cid              = "Qm.../bafy...",
--     ipfsUri          = "ipfs://<cid>",
--     gateways         = { ipfs_io, pinata, dweb, cloudflare, ... },
--     pinSize          = bytes pinned,
--     timestamp        = ISO timestamp,
-- }
-- ---
function MetaplexIpfs.uploadJson(jsonStr, opts, callback)
    opts = opts or {}
    local auth = authHeaders()
    if not auth then
        return callback(nil,
            "Pinata auth not configured. Call setPinataJwt(<jwt>) OR setPinataKey(<key>, <secret>).")
    end
    if type(jsonStr) ~= "string" or #jsonStr == 0 then
        return callback(nil, "uploadJson: empty input")
    end

    -- Parse the caller's JSON string (could come from our own encoder or
    -- elsewhere) into a Lua value so we can wrap it in the Pinata envelope.
    local content = fromJSON(jsonStr)
    if not content then
        return callback(nil, "uploadJson: input is not valid JSON")
    end
    -- MTA's fromJSON wraps a root object in a 1-element array ({x}). Unwrap
    -- once here so pinataContent ends up as a proper object, not a list.
    if type(content) == "table" and content[1] and not content.type then
        -- Heuristic: single element and no top-level object keys → unwrap
        local keyCount = 0
        for _ in pairs(content) do keyCount = keyCount + 1 end
        if keyCount == 1 and content[1] then content = content[1] end
    end

    -- Use our own JSON encoder so the outgoing body is a plain object
    -- (Pinata rejects or mis-stores array-wrapped payloads).
    local body = MetaplexJson.encodeOrdered({
        { "pinataContent",  content },
        { "pinataMetadata", { name = opts.name or "metaplex-sdk-upload" } },
        { "pinataOptions",  { cidVersion = 1 } },
    })

    -- Compose final headers: auth + Content-Type
    local headers = { ["Content-Type"] = "application/json" }
    for k, v in pairs(auth) do headers[k] = v end

    fetchRemote("https://api.pinata.cloud/pinning/pinJSONToIPFS", {
        method             = "POST",
        headers            = headers,
        postData           = body,
        connectionAttempts = 3,
        connectTimeout     = 15000,
    }, function(responseData, responseInfo)
        local status = responseInfo and responseInfo.statusCode
        if status ~= 200 then
            callback(nil, "Pinata HTTP " .. tostring(status) .. ": " ..
                tostring(responseData))
            return
        end
        local result = fromJSON(responseData)
        if not result or not result.IpfsHash then
            callback(nil, "Invalid Pinata response: " .. tostring(responseData))
            return
        end
        local cid = result.IpfsHash
        callback({
            cid       = cid,
            ipfsUri   = "ipfs://" .. cid,
            gateways  = MetaplexIpfs.gateways(cid),
            pinSize   = result.PinSize,
            timestamp = result.Timestamp,
        })
    end)
end

-- ---
-- Quick sanity check that the configured JWT is valid. Calls Pinata's
-- /data/testAuthentication endpoint. Used by the example to confirm the
-- user's JWT before they try a real upload.
-- ---
function MetaplexIpfs.testPinataAuth(callback)
    local auth = authHeaders()
    if not auth then
        return callback(false, "Auth not configured (no JWT or key+secret)")
    end
    fetchRemote("https://api.pinata.cloud/data/testAuthentication", {
        method             = "GET",
        headers            = auth,
        connectionAttempts = 2,
        connectTimeout     = 8000,
    }, function(responseData, responseInfo)
        local ok = responseInfo and responseInfo.statusCode == 200
        local mode = _authMode or "none"
        callback(ok, ok and ("Pinata auth OK (mode: " .. mode .. ")") or
            ("HTTP " .. tostring(responseInfo and responseInfo.statusCode) ..
             ": " .. tostring(responseData)))
    end)
end
