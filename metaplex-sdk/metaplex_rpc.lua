-- https://github.com/yongsxyz
--[[
    Metaplex SDK - Minimal RPC client.

    solana-sdk exposes high-level helpers (fetchBalance, fetchAccount, etc.)
    but intentionally strips the raw `data` field from account responses to
    keep the API simple. Reading metadata / mint account layouts requires
    those raw bytes, so this module issues its own `getAccountInfo` calls
    via MTA's fetchRemote.

    We reuse solana-sdk's configured endpoint by querying
    exports["solana-sdk"]:getClientStatus() at call time.
]]

MetaplexRpc = {}

local CLUSTER_DEFAULTS = {
    ["mainnet"]      = "https://api.mainnet-beta.solana.com",
    ["mainnet-beta"] = "https://api.mainnet-beta.solana.com",
    ["devnet"]       = "https://api.devnet.solana.com",
    ["testnet"]      = "https://api.testnet.solana.com",
    ["localnet"]     = "http://127.0.0.1:8899",
}

local _requestId = 0

local function resolveEndpoint()
    -- solana-sdk stores the current endpoint; ask it first.
    local ok, endpoint = pcall(function()
        local _status, ep = exports["solana-sdk"]:getClientStatus()
        return ep
    end)
    if ok and endpoint then return endpoint end
    return CLUSTER_DEFAULTS["devnet"]
end

-- Low-level JSON-RPC wrapper. `callback(result, errString)`.
function MetaplexRpc.call(method, params, callback)
    _requestId = _requestId + 1
    local payload = toJSON({
        jsonrpc = "2.0",
        id      = _requestId,
        method  = method,
        params  = params or {},
    })

    fetchRemote(resolveEndpoint(), {
        method    = "POST",
        headers   = { ["Content-Type"] = "application/json" },
        postData  = payload,
        connectionAttempts = 3,
        connectTimeout     = 10000,
    }, function(responseData, responseInfo)
        if responseInfo.statusCode ~= 200 then
            callback(nil, "HTTP " .. tostring(responseInfo.statusCode) ..
                ": " .. tostring(responseData))
            return
        end
        local decoded = fromJSON(responseData)
        if not decoded then
            callback(nil, "Failed to parse JSON response")
            return
        end
        if decoded.error then
            callback(nil, "RPC Error [" .. tostring(decoded.error.code) ..
                "]: " .. tostring(decoded.error.message))
            return
        end
        callback(decoded.result)
    end)
end

-- Fetch raw account info (base64 data).
-- callback receives {
--     lamports, owner, executable, rentEpoch,
--     data = <byte array>    -- nil if the account doesn't exist
-- }
function MetaplexRpc.getAccountBytes(address, callback)
    MetaplexRpc.call("getAccountInfo", {
        address,
        { encoding = "base64", commitment = "confirmed" },
    }, function(result, err)
        if err then callback(nil, err) return end
        if not result or not result.value then
            callback(nil, "Account not found")
            return
        end
        local v = result.value
        local dataBytes = nil
        if v.data and type(v.data) == "table" and v.data[1] then
            local decoded, derr = MetaplexBorsh.base64ToBytes(v.data[1])
            if not decoded then
                callback(nil, "Failed to decode account data: " .. tostring(derr))
                return
            end
            dataBytes = decoded
        end
        callback({
            lamports   = v.lamports,
            owner      = v.owner,
            executable = v.executable,
            rentEpoch  = v.rentEpoch,
            data       = dataBytes,
            slot       = result.context and result.context.slot,
        })
    end)
end
