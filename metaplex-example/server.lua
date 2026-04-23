-- https://github.com/yongsxyz
--[[
    METAPLEX EXAMPLE - server side
    Demonstrates how to mint a SPL fungible token with Metaplex Token
    Metadata, in pure Lua, on top of solana-sdk + metaplex-sdk.

    COMMANDS
    ── HELPERS ─────────────────────────────────────────────
    /mphelp                                Print this help
    /mpprogram                             Show Token Metadata program id

    ── PDA HELPERS (instant, no RPC) ───────────────────────
    /mpmetapda <mint>                      Print metadata PDA for a mint
    /mpata <owner> <mint>                  Print ATA for owner+mint

    ── TOKEN CREATION ──────────────────────────────────────
    /mpcreate <wallet> <name> <symbol> <uri> [decimals] [bps]
        Run CreateV1 only. Generates a fresh mint keypair.
        Example:
          /mpcreate <walletAddr> "MTA SA Coin" MSA https://example.com/meta.json 9 0

    /mpmint <wallet> <mint> <ata> <amount>
        SPL MintTo to an existing ATA. Amount is RAW (factor in decimals).

    /mpata-create <wallet> <mint>
        Idempotent ATA creation for the wallet itself.

    /mpall <wallet> <name> <symbol> <uri> <amount> [decimals] [bps]
        Full pipeline: CreateV1 -> CreateIdempotentATA -> MintTo.
        amount is RAW (e.g. 1000000000000000 for 1,000,000 @ 9 decimals).

    /mptoken <wallet> <name> <symbol> <uri> <initialSupply> [decimals] [bps]
        Same as /mpall but initialSupply is in HUMAN units.
        e.g. /mptoken <addr> "My Fungible Token" MFT https://example.com/meta.json 1000000 9
        -> creates token + mints 1,000,000 MFT (decimals 9) to your wallet.

    ── READ ────────────────────────────────────────────────
    /mpfetch <mint>                        Fetch metadata account info

    NOTE: Make sure the wallet you pass is already imported in solana-sdk
          (e.g. /solwallet phrase or /solwallet import) and has some SOL
          for fees. On devnet you can /solairdrop <wallet> 2 first.
]]

local sol = exports["solana-sdk"]
local mp  = exports["metaplex-sdk"]

-- ---
-- Pinata credentials (server-side default).
--
-- LEAVE BLANK for commits. Populate AT RUNTIME via either:
--   * Chat:  /mpipfskey <apiKey> <apiSecret>   (in-memory, per session)
--   *   OR:  /mpipfsjwt <pinataJwt>            (JWT alternative)
--   * Server console / a private config file outside the git repo
--
-- Get free keys at https://app.pinata.cloud/developers/api-keys
-- ---
local PINATA_API_KEY    = ""
local PINATA_API_SECRET = ""

addEventHandler("onResourceStart", resourceRoot, function()
    outputDebugString("[metaplex-example] Ready. Token Metadata program: " ..
        tostring(mp:getTokenMetadataProgramId()))

    -- Ensure solana-sdk has an initialized RPC client. Without this,
    -- any call into the SDK fails with "Client not initialized".
    -- Re-initializing an already-connected client is harmless — it just
    -- re-resolves the endpoint and verifies connectivity.
    local status = sol:getClientStatus()
    if status ~= "ready" and status ~= "connecting" then
        sol:initClient({
            cluster    = "devnet",       -- change to "mainnet-beta" for production
            commitment = "confirmed",
        })
        outputDebugString("[metaplex-example] solana-sdk initClient() called (was: " ..
            tostring(status) .. ")")
    else
        outputDebugString("[metaplex-example] solana-sdk already initialized (" ..
            tostring(status) .. ")")
    end

    if PINATA_API_KEY ~= "" and PINATA_API_SECRET ~= "" then
        local ok = mp:setIpfsPinataKey(PINATA_API_KEY, PINATA_API_SECRET)
        if ok then
            outputDebugString("[metaplex-example] Pinata auto-configured (key+secret).")
        else
            outputDebugString("[metaplex-example] Pinata auto-config failed.", 2)
        end
    end
end)

-- ---
-- Per-player request queue (mirrors the pattern from solana-example)
-- ---

local _pending = {}

local function pushPlayer(key, player)
    _pending[key] = _pending[key] or {}
    table.insert(_pending[key], player)
end

local function popPlayer(key)
    local q = _pending[key]
    if q and #q > 0 then return table.remove(q, 1) end
    return nil
end

local function chat(player, color, prefix, msg)
    if not player then return end
    outputChatBox(color .. "[" .. prefix .. "] #ffffff" .. tostring(msg),
        player, 255, 255, 255, true)
end

-- ---
-- /mphelp
-- ---

addCommandHandler("mphelp", function(player)
    chat(player, "#9b6dff", "Metaplex", "Commands:")
    outputChatBox("#aaaaaa  /mpprogram", player, 255, 255, 255, true)
    outputChatBox("#aaaaaa  /mpmetapda <mint>", player, 255, 255, 255, true)
    outputChatBox("#aaaaaa  /mpata <owner> <mint>", player, 255, 255, 255, true)
    outputChatBox("#aaaaaa  /mpcreate <wallet> <name> <symbol> <uri> [decimals] [bps]", player, 255, 255, 255, true)
    outputChatBox("#aaaaaa  /mpata-create <wallet> <mint>", player, 255, 255, 255, true)
    outputChatBox("#aaaaaa  /mpmint <wallet> <mint> <ata> <amount>", player, 255, 255, 255, true)
    outputChatBox("#aaaaaa  /mpall <wallet> <name> <symbol> <uri> <amount> [decimals] [bps]", player, 255, 255, 255, true)
    outputChatBox("#00ff88  /mptoken <wallet> <name> <symbol> <uri> <initialSupply> [decimals] [bps]", player, 255, 255, 255, true)
    outputChatBox("#888888    ^ same as /mpall but supply is in HUMAN units (1000000 = 1M tokens)", player, 255, 255, 255, true)
    outputChatBox("#aaaaaa  /mpupdate <wallet> <mint> <name> <symbol> <uri> [bps]", player, 255, 255, 255, true)
    outputChatBox("#aaaaaa  /mpburn <wallet> <mint> <humanAmount> [decimals]", player, 255, 255, 255, true)
    outputChatBox("#aaaaaa  /mpinfo <mint>              -- fetch decoded metadata + mint data", player, 255, 255, 255, true)
    outputChatBox("#aaaaaa  /mpbalance <owner> <mint>   -- token balance via ATA", player, 255, 255, 255, true)
    outputChatBox("#aaaaaa  /mpfetch <mint>             -- raw metadata account info", player, 255, 255, 255, true)
    outputChatBox("#ffaa00  --- IPFS (Pinata) ---", player, 255, 255, 255, true)
    outputChatBox("#9b6dff  /mpipfskey <apiKey> <apiSecret>    -- configure API Key + Secret (PREFERRED)", player, 255, 255, 255, true)
    outputChatBox("#9b6dff  /mpipfsjwt <pinataJwt>             -- OR configure via Bearer JWT", player, 255, 255, 255, true)
    outputChatBox("#9b6dff  /mpipfsconfig <pinataJwt>          -- alias for /mpipfsjwt (legacy)", player, 255, 255, 255, true)
    outputChatBox("#9b6dff  /mpipfsclear                       -- wipe stored credentials", player, 255, 255, 255, true)
    outputChatBox("#9b6dff  /mpipfsstatus                      -- show current auth mode", player, 255, 255, 255, true)
    outputChatBox("#9b6dff  /mpipfstest                        -- test Pinata auth", player, 255, 255, 255, true)
    outputChatBox("#ffaa00  --- AGENT ---", player, 255, 255, 255, true)
    outputChatBox("#00ff88  /mpagentcreate <wallet> <name> <description> [imageUri]", player, 255, 255, 255, true)
    outputChatBox("#888888    ^ ONE-SHOT: builds ERC-8004 JSON -> uploads to IPFS -> mints atomic TX", player, 255, 255, 255, true)
    outputChatBox("#9b6dff  /mpagentjson <agentMint> <name> <description> <imageUri>   -- preview JSON only", player, 255, 255, 255, true)
    outputChatBox("#9b6dff  /mpagentpublish <wallet> <agentMint> <name> <description> <imageUri>", player, 255, 255, 255, true)
    outputChatBox("#888888    ^ re-upload JSON + update URI for an EXISTING agent", player, 255, 255, 255, true)
    outputChatBox("#9b6dff  /mpagentsetreg <wallet> <agentMint> <registrationUri>      -- link hosted JSON manually", player, 255, 255, 255, true)
    outputChatBox("#9b6dff  /mpagentpda <agentMint>      -- derive Agent Asset Signer PDA", player, 255, 255, 255, true)
    outputChatBox("#9b6dff  /mpagenttoken <wallet> <agentMint> <name> <symbol> <uri> <supply> [decimals] [bps]", player, 255, 255, 255, true)
    outputChatBox("#888888    ^ simplified agent token (creator = agent PDA, no bonding curve)", player, 255, 255, 255, true)
    outputChatBox("#ffaa00Tip:#ffffff need a wallet first? -> /solwallet phrase, then /solairdrop <addr> 2",
        player, 255, 255, 255, true)
end)

-- ---
-- /mpprogram
-- ---

addCommandHandler("mpprogram", function(player)
    chat(player, "#9b6dff", "Metaplex", "Token Metadata: " .. mp:getTokenMetadataProgramId())
end)

-- ---
-- /mpmetapda <mint>
-- ---

addCommandHandler("mpmetapda", function(player, _, mint)
    if not mint then chat(player, "#ffaa00", "Metaplex", "Usage: /mpmetapda <mint>") return end
    local pda, bump = mp:findMetadataPda(mint)
    if not pda then
        chat(player, "#ff5555", "Metaplex", "Failed to derive PDA (invalid mint?)")
        return
    end
    chat(player, "#00ff88", "Metaplex", "Metadata PDA: " .. pda)
    chat(player, "#00ff88", "Metaplex", "Bump: " .. tostring(bump))
end)

-- ---
-- /mpata <owner> <mint>
-- ---

addCommandHandler("mpata", function(player, _, owner, mint)
    if not owner or not mint then
        chat(player, "#ffaa00", "Metaplex", "Usage: /mpata <owner> <mint>") return
    end
    local ata, bump = mp:findAssociatedTokenAddress(owner, mint)
    if not ata then chat(player, "#ff5555", "Metaplex", "Failed to derive ATA") return end
    chat(player, "#00ff88", "Metaplex", "ATA: " .. ata)
    chat(player, "#00ff88", "Metaplex", "Bump: " .. tostring(bump))
end)

-- ---
-- /mpcreate <wallet> <name> <symbol> <uri> [decimals] [bps]
-- ---

addEvent("onMpCreateResult", true)
addEventHandler("onMpCreateResult", resourceRoot, function(result, err)
    local player = popPlayer("create")
    if not player then return end
    if err then chat(player, "#ff5555", "Metaplex", "CreateV1 failed: " .. tostring(err)) return end

    chat(player, "#00ff88", "Metaplex", "Token created!")
    chat(player, "#00ff88", "Metaplex", "Mint:      " .. tostring(result.mint))
    chat(player, "#00ff88", "Metaplex", "Metadata:  " .. tostring(result.metadata))
    chat(player, "#00ff88", "Metaplex", "Signature: " .. tostring(result.signature))
    chat(player, "#888888", "Metaplex", "Solscan: https://solscan.io/tx/" .. tostring(result.signature) .. "?cluster=devnet")
end)

addCommandHandler("mpcreate", function(player, _, wallet, name, symbol, uri, decimals, bps)
    if not wallet or not name or not symbol or not uri then
        chat(player, "#ffaa00", "Metaplex",
            "Usage: /mpcreate <wallet> <name> <symbol> <uri> [decimals] [bps]")
        return
    end

    decimals = tonumber(decimals) or 9
    bps = tonumber(bps) or 0

    if not sol:hasWallet(wallet) then
        chat(player, "#ff5555", "Metaplex", "Wallet not loaded in solana-sdk")
        return
    end

    chat(player, "#9b6dff", "Metaplex", "Building CreateV1 transaction... (~1-2s sign)")
    pushPlayer("create", player)

    mp:createFungibleToken({
        wallet               = wallet,
        name                 = name,
        symbol               = symbol,
        uri                  = uri,
        decimals             = decimals,
        sellerFeeBasisPoints = bps,
    }, "onMpCreateResult", resourceRoot)
end)

-- ---
-- /mpata-create <wallet> <mint>
-- ---

addEvent("onMpAtaCreateResult", true)
addEventHandler("onMpAtaCreateResult", resourceRoot, function(result, err)
    local player = popPlayer("ata-create")
    if not player then return end
    if err then chat(player, "#ff5555", "Metaplex", "ATA create failed: " .. tostring(err)) return end
    chat(player, "#00ff88", "Metaplex", "ATA ready: " .. tostring(result.ata))
    chat(player, "#00ff88", "Metaplex", "Signature: " .. tostring(result.signature))
end)

addCommandHandler("mpata-create", function(player, _, wallet, mint)
    if not wallet or not mint then
        chat(player, "#ffaa00", "Metaplex", "Usage: /mpata-create <wallet> <mint>")
        return
    end
    if not sol:hasWallet(wallet) then
        chat(player, "#ff5555", "Metaplex", "Wallet not loaded in solana-sdk")
        return
    end
    chat(player, "#9b6dff", "Metaplex", "Submitting CreateIdempotent ATA...")
    pushPlayer("ata-create", player)
    mp:createTokenAccount({ wallet = wallet, mint = mint },
        "onMpAtaCreateResult", resourceRoot)
end)

-- ---
-- /mpmint <wallet> <mint> <ata> <amount>
-- ---

addEvent("onMpMintResult", true)
addEventHandler("onMpMintResult", resourceRoot, function(result, err)
    local player = popPlayer("mint")
    if not player then return end
    if err then chat(player, "#ff5555", "Metaplex", "MintTo failed: " .. tostring(err)) return end
    chat(player, "#00ff88", "Metaplex", "Minted!")
    chat(player, "#00ff88", "Metaplex", "Signature: " .. tostring(result.signature))
end)

addCommandHandler("mpmint", function(player, _, wallet, mint, ata, amount)
    if not wallet or not mint or not ata or not amount then
        chat(player, "#ffaa00", "Metaplex",
            "Usage: /mpmint <wallet> <mint> <ata> <amount>   (amount = RAW u64)")
        return
    end
    -- Keep amount as a digit string to preserve precision above 2^53.
    local amountStr = tostring(amount):gsub("^%+", "")
    if not amountStr:match("^%d+$") or amountStr == "0" then
        chat(player, "#ff5555", "Metaplex", "Amount must be a positive whole number")
        return
    end
    if not sol:hasWallet(wallet) then
        chat(player, "#ff5555", "Metaplex", "Wallet not loaded in solana-sdk")
        return
    end
    chat(player, "#9b6dff", "Metaplex", "Submitting MintTo...")
    pushPlayer("mint", player)
    mp:mintTokensTo({ wallet = wallet, mint = mint, token = ata, amount = amountStr },
        "onMpMintResult", resourceRoot)
end)

-- ---
-- /mpall <wallet> <name> <symbol> <uri> <amount> [decimals] [bps]
-- ---

addEvent("onMpAllResult", true)
addEventHandler("onMpAllResult", resourceRoot, function(result, err)
    local player = popPlayer("all")
    if not player then return end
    if err then chat(player, "#ff5555", "Metaplex", "Pipeline failed: " .. tostring(err)) return end

    chat(player, "#00ff88", "Metaplex", "All done! (single atomic transaction)")
    chat(player, "#00ff88", "Metaplex", "Mint:      " .. tostring(result.mint))
    chat(player, "#00ff88", "Metaplex", "Metadata:  " .. tostring(result.metadata))
    if result.ata then
        chat(player, "#00ff88", "Metaplex", "ATA:       " .. tostring(result.ata))
    end
    chat(player, "#00ff88", "Metaplex", "Signature: " .. tostring(result.signature))
    if result.signature then
        chat(player, "#888888", "Metaplex",
            "Solscan: https://solscan.io/tx/" .. tostring(result.signature) .. "?cluster=devnet")
    end
end)

addCommandHandler("mpall", function(player, _, wallet, name, symbol, uri, amount, decimals, bps)
    if not wallet or not name or not symbol or not uri or not amount then
        chat(player, "#ffaa00", "Metaplex",
            "Usage: /mpall <wallet> <name> <symbol> <uri> <amount> [decimals] [bps]")
        chat(player, "#ffaa00", "Metaplex",
            "Example: /mpall <walletAddr> MTA SA https://example.com/meta.json 1000000000000000 9 0")
        return
    end

    local amountStr = tostring(amount):gsub("^%+", "")
    if not amountStr:match("^%d+$") or amountStr == "0" then
        chat(player, "#ff5555", "Metaplex", "Amount must be a positive whole number (raw u64)")
        return
    end

    decimals = tonumber(decimals) or 9
    bps = tonumber(bps) or 0

    if not sol:hasWallet(wallet) then
        chat(player, "#ff5555", "Metaplex", "Wallet not loaded in solana-sdk")
        return
    end

    chat(player, "#9b6dff", "Metaplex", "Building atomic TX: CreateV1 + CreateIdempotentATA + MintTo...")
    chat(player, "#888888", "Metaplex", "One transaction, two signatures. ~1-2s in pure Lua.")
    pushPlayer("all", player)

    mp:createAndMintFungible({
        wallet               = wallet,
        name                 = name,
        symbol               = symbol,
        uri                  = uri,
        decimals             = decimals,
        sellerFeeBasisPoints = bps,
        amount               = amountStr,
    }, "onMpAllResult", resourceRoot)
end)

-- ---
-- /mptoken <wallet> <name> <symbol> <uri> <initialSupply> [decimals] [bps]
-- One-shot: create fungible + ATA + mint INITIAL SUPPLY (in human units).
-- Mirrors the Metaplex docs example exactly — 1,000,000 tokens with 9 decimals
-- becomes /mptoken <wallet> "My Fungible Token" MFT https://example.com/meta.json 1000000
-- ---

addEvent("onMpTokenResult", true)
addEventHandler("onMpTokenResult", resourceRoot, function(result, err)
    local player = popPlayer("token")
    if not player then return end
    if err then chat(player, "#ff5555", "Metaplex", "Pipeline failed: " .. tostring(err)) return end

    chat(player, "#00ff88", "Metaplex", "Token created and initial supply minted! (atomic)")
    chat(player, "#00ff88", "Metaplex", "Mint:      " .. tostring(result.mint))
    chat(player, "#00ff88", "Metaplex", "Metadata:  " .. tostring(result.metadata))
    if result.ata then
        chat(player, "#00ff88", "Metaplex", "ATA:       " .. tostring(result.ata))
    end
    chat(player, "#00ff88", "Metaplex", "Signature: " .. tostring(result.signature))
    if result.signature then
        chat(player, "#888888", "Metaplex",
            "Solscan: https://solscan.io/tx/" .. tostring(result.signature) .. "?cluster=devnet")
    end
end)

-- SPL Token program supply is stored as u64. Max raw value:
-- 18_446_744_073_709_551_615 -> "18446744073709551615" as decimal string.
local SPL_U64_MAX = "18446744073709551615"

-- Compare two non-negative decimal strings. Returns -1, 0, or 1.
local function strCmp(a, b)
    a = a:gsub("^0+", ""); if a == "" then a = "0" end
    b = b:gsub("^0+", ""); if b == "" then b = "0" end
    if #a ~= #b then return (#a < #b) and -1 or 1 end
    if a == b then return 0 end
    return (a < b) and -1 or 1
end

addCommandHandler("mptoken", function(player, _, wallet, name, symbol, uri, initialSupply, decimals, bps)
    if not wallet or not name or not symbol or not uri or not initialSupply then
        chat(player, "#ffaa00", "Metaplex",
            "Usage: /mptoken <wallet> <name> <symbol> <uri> <initialSupply> [decimals] [bps]")
        chat(player, "#ffaa00", "Metaplex",
            "Example: /mptoken <walletAddr> MFT MFT https://example.com/meta.json 1000000 9 0")
        chat(player, "#888888", "Metaplex",
            "initialSupply is in HUMAN units. 1000000 + decimals 9 -> 1,000,000 tokens.")
        return
    end

    -- Accept supply as digit string (preserves precision > 2^53 natively).
    local supplyStr = tostring(initialSupply):gsub("^%+", "")
    if not supplyStr:match("^%d+$") or supplyStr == "0" then
        chat(player, "#ff5555", "Metaplex",
            "initialSupply must be a positive whole number (no decimals / commas)")
        return
    end

    decimals = tonumber(decimals) or 9
    bps = tonumber(bps) or 0

    if decimals < 0 or decimals > 18 then
        chat(player, "#ff5555", "Metaplex", "decimals must be 0..18")
        return
    end

    if not sol:hasWallet(wallet) then
        chat(player, "#ff5555", "Metaplex", "Wallet not loaded in solana-sdk")
        return
    end

    -- Compute raw u64 as a string: supply * 10^decimals == append zeros.
    local rawStr = supplyStr .. string.rep("0", decimals)

    -- Enforce the on-chain u64 ceiling for SPL supply.
    if strCmp(rawStr, SPL_U64_MAX) > 0 then
        chat(player, "#ff5555", "Metaplex",
            "Raw amount " .. rawStr .. " exceeds SPL u64 max (" .. SPL_U64_MAX .. ").")
        chat(player, "#888888", "Metaplex",
            "Tip: 18 decimals caps total supply at ~18 tokens on Solana. Try 6 or 9 decimals.")
        return
    end

    chat(player, "#9b6dff", "Metaplex",
        "Atomic TX: CreateV1 + ATA + MintTo (" .. supplyStr ..
        " tokens @ " .. tostring(decimals) .. " decimals -> raw " .. rawStr .. ")")
    chat(player, "#888888", "Metaplex", "One transaction, two signatures. ~1-2s in pure Lua.")
    pushPlayer("token", player)

    mp:createAndMintFungible({
        wallet               = wallet,
        name                 = name,
        symbol               = symbol,
        uri                  = uri,
        decimals             = decimals,
        sellerFeeBasisPoints = bps,
        initialSupply        = supplyStr,  -- pass as string, SDK does string-bigint math
    }, "onMpTokenResult", resourceRoot)
end)

-- ---
-- /mpfetch <mint>
-- ---

addEvent("onMpFetchResult", true)
addEventHandler("onMpFetchResult", resourceRoot, function(result, err)
    local player = popPlayer("fetch")
    if not player then return end
    if err then chat(player, "#ff5555", "Metaplex", "Fetch failed: " .. tostring(err)) return end
    chat(player, "#00ff88", "Metaplex", "Metadata PDA: " .. tostring(result.metadata))
    local d = result.data or {}
    chat(player, "#00ff88", "Metaplex", "Name:   " .. tostring(d.name))
    chat(player, "#00ff88", "Metaplex", "Symbol: " .. tostring(d.symbol))
    chat(player, "#00ff88", "Metaplex", "URI:    " .. tostring(d.uri))
    chat(player, "#888888", "Metaplex", "sellerFeeBasisPoints: " .. tostring(d.sellerFeeBasisPoints))
    chat(player, "#888888", "Metaplex", "isMutable: " .. tostring(d.isMutable))
end)

addCommandHandler("mpfetch", function(player, _, mint)
    if not mint then chat(player, "#ffaa00", "Metaplex", "Usage: /mpfetch <mint>") return end
    pushPlayer("fetch", player)
    mp:fetchMetadata(mint, "onMpFetchResult", resourceRoot)
end)

-- ---
-- /mpinfo <mint>
-- Full digital-asset read: metadata + mint account (supply, decimals, authorities).
-- ---

addEvent("onMpInfoResult", true)
addEventHandler("onMpInfoResult", resourceRoot, function(result, err)
    local player = popPlayer("info")
    if not player then return end
    if err then chat(player, "#ff5555", "Metaplex", "Info failed: " .. tostring(err)) return end

    local d = result.metadata or {}
    local m = result.mintInfo or {}

    chat(player, "#9b6dff", "Metaplex", "=== Digital Asset ===")
    chat(player, "#00ff88", "Metaplex", "Mint:     " .. tostring(result.mint))
    chat(player, "#00ff88", "Metaplex", "Name:     " .. tostring(d.name))
    chat(player, "#00ff88", "Metaplex", "Symbol:   " .. tostring(d.symbol))
    chat(player, "#00ff88", "Metaplex", "URI:      " .. tostring(d.uri))
    chat(player, "#00ff88", "Metaplex", "Decimals: " .. tostring(m.decimals))
    chat(player, "#00ff88", "Metaplex", "Supply:   " .. tostring(m.supply) .. "  (raw)")

    if m.decimals and m.supply then
        -- Compute human-readable supply via string math (no Lua double loss).
        local s = m.supply
        local d_ = m.decimals
        if #s <= d_ then
            chat(player, "#888888", "Metaplex",
                "          0." .. string.rep("0", d_ - #s) .. s .. "  (human)")
        else
            local intPart = s:sub(1, #s - d_)
            local fracPart = s:sub(#s - d_ + 1):gsub("0+$", "")
            local human = fracPart == "" and intPart or (intPart .. "." .. fracPart)
            chat(player, "#888888", "Metaplex", "          " .. human .. "  (human)")
        end
    end

    chat(player, "#888888", "Metaplex", "Update auth:    " .. tostring(d.updateAuthority))
    chat(player, "#888888", "Metaplex", "Mint authority: " .. tostring(m.mintAuthority))
    chat(player, "#888888", "Metaplex", "isMutable:      " .. tostring(d.isMutable) ..
        "  tokenStandard: " .. tostring(d.tokenStandard))
end)

addCommandHandler("mpinfo", function(player, _, mint)
    if not mint then chat(player, "#ffaa00", "Metaplex", "Usage: /mpinfo <mint>") return end
    pushPlayer("info", player)
    mp:fetchDigitalAsset(mint, "onMpInfoResult", resourceRoot)
end)

-- ---
-- /mpbalance <owner> <mint>
-- ---

addEvent("onMpBalanceResult", true)
addEventHandler("onMpBalanceResult", resourceRoot, function(result, err)
    local player = popPlayer("balance")
    if not player then return end
    if err then chat(player, "#ff5555", "Metaplex", "Balance failed: " .. tostring(err)) return end
    chat(player, "#00ff88", "Metaplex", "ATA:      " .. tostring(result.ata))
    chat(player, "#00ff88", "Metaplex", "Balance:  " .. tostring(result.uiAmountString) ..
        "  (raw " .. tostring(result.amount) .. ", decimals " .. tostring(result.decimals) .. ")")
end)

addCommandHandler("mpbalance", function(player, _, owner, mint)
    if not owner or not mint then
        chat(player, "#ffaa00", "Metaplex", "Usage: /mpbalance <owner> <mint>")
        return
    end
    pushPlayer("balance", player)
    mp:fetchTokenBalance(owner, mint, "onMpBalanceResult", resourceRoot)
end)

-- ---
-- /mpupdate <wallet> <mint> <name> <symbol> <uri> [bps]
-- Changes the token's name/symbol/uri on-chain. Wallet must be the current
-- update authority AND the token must have been minted with isMutable=true.
-- ---

addEvent("onMpUpdateResult", true)
addEventHandler("onMpUpdateResult", resourceRoot, function(result, err)
    local player = popPlayer("update")
    if not player then return end
    if err then chat(player, "#ff5555", "Metaplex", "Update failed: " .. tostring(err)) return end
    chat(player, "#00ff88", "Metaplex", "Metadata updated!")
    chat(player, "#00ff88", "Metaplex", "Mint:      " .. tostring(result.mint))
    chat(player, "#00ff88", "Metaplex", "Signature: " .. tostring(result.signature))
    if result.updated then
        chat(player, "#888888", "Metaplex", "  name:   " .. tostring(result.updated.name))
        chat(player, "#888888", "Metaplex", "  symbol: " .. tostring(result.updated.symbol))
        chat(player, "#888888", "Metaplex", "  uri:    " .. tostring(result.updated.uri))
        chat(player, "#888888", "Metaplex", "  bps:    " .. tostring(result.updated.sellerFeeBasisPoints))
    end
    if result.signature then
        chat(player, "#888888", "Metaplex",
            "Solscan: https://solscan.io/tx/" .. tostring(result.signature) .. "?cluster=devnet")
    end
end)

addCommandHandler("mpupdate", function(player, _, wallet, mint, name, symbol, uri, bps)
    if not wallet or not mint or not name or not symbol or not uri then
        chat(player, "#ffaa00", "Metaplex",
            "Usage: /mpupdate <wallet> <mint> <name> <symbol> <uri> [bps]")
        chat(player, "#888888", "Metaplex",
            "Wallet must be the update authority. Token must have been created mutable.")
        return
    end
    if not sol:hasWallet(wallet) then
        chat(player, "#ff5555", "Metaplex", "Wallet not loaded in solana-sdk")
        return
    end
    chat(player, "#9b6dff", "Metaplex", "Fetching current metadata + submitting updateV1...")
    pushPlayer("update", player)
    mp:updateMetadata({
        wallet               = wallet,
        mint                 = mint,
        name                 = name,
        symbol               = symbol,
        uri                  = uri,
        sellerFeeBasisPoints = tonumber(bps) or nil,
    }, "onMpUpdateResult", resourceRoot)
end)

-- ---
-- /mpburn <wallet> <mint> <humanAmount> [decimals]
-- Permanently destroys tokens from the wallet's ATA. Irreversible.
-- humanAmount is in display units (e.g. 100 burns 100 tokens regardless
-- of decimals — SDK auto-multiplies by 10^decimals).
-- ---

addEvent("onMpBurnResult", true)
addEventHandler("onMpBurnResult", resourceRoot, function(result, err)
    local player = popPlayer("burn")
    if not player then return end
    if err then chat(player, "#ff5555", "Metaplex", "Burn failed: " .. tostring(err)) return end
    chat(player, "#00ff88", "Metaplex", "Burned!")
    if result.burned then
        chat(player, "#888888", "Metaplex",
            "Raw amount: " .. tostring(result.burned.amount) ..
            " from ATA " .. tostring(result.burned.tokenAccount))
    end
    chat(player, "#00ff88", "Metaplex", "Signature: " .. tostring(result.signature))
    if result.signature then
        chat(player, "#888888", "Metaplex",
            "Solscan: https://solscan.io/tx/" .. tostring(result.signature) .. "?cluster=devnet")
    end
end)

addCommandHandler("mpburn", function(player, _, wallet, mint, humanAmount, decimals)
    if not wallet or not mint or not humanAmount then
        chat(player, "#ffaa00", "Metaplex", "Usage: /mpburn <wallet> <mint> <humanAmount> [decimals]")
        chat(player, "#888888", "Metaplex",
            "Example: /mpburn <addr> <mint> 100 9   -> burns 100 tokens @ 9 decimals")
        chat(player, "#ff5555", "Metaplex", "BURN IS PERMANENT AND IRREVERSIBLE.")
        return
    end

    local supplyStr = tostring(humanAmount):gsub("^%+", "")
    if not supplyStr:match("^%d+$") or supplyStr == "0" then
        chat(player, "#ff5555", "Metaplex", "humanAmount must be a positive whole number")
        return
    end

    decimals = tonumber(decimals) or 9

    if not sol:hasWallet(wallet) then
        chat(player, "#ff5555", "Metaplex", "Wallet not loaded in solana-sdk")
        return
    end

    chat(player, "#9b6dff", "Metaplex", "Burning " .. supplyStr ..
        " tokens @ " .. tostring(decimals) .. " decimals...")
    pushPlayer("burn", player)
    mp:burnTokens({
        wallet        = wallet,
        mint          = mint,
        initialSupply = supplyStr,
        decimals      = decimals,
    }, "onMpBurnResult", resourceRoot)
end)

-- ---
-- /mpagentpda <agentMint>
-- Derive the agent's Asset Signer PDA (the built-in wallet of an MPL Core
-- agent asset). Deterministic, no RPC — just SHA-256 with seeds
-- ['mpl-core-execute', agentMint] under the MPL Core program.
-- ---

addCommandHandler("mpagentpda", function(player, _, agentMint)
    if not agentMint then
        chat(player, "#ffaa00", "Metaplex", "Usage: /mpagentpda <agentMint>")
        chat(player, "#888888", "Metaplex",
            "agentMint = base58 Core asset address of a registered agent.")
        return
    end
    local pda, bump, err = mp:findAgentAssetSigner(agentMint)
    if not pda then
        chat(player, "#ff5555", "Metaplex", "Failed: " .. tostring(err))
        return
    end
    chat(player, "#00ff88", "Metaplex", "Agent Asset Signer PDA:")
    chat(player, "#ffffff", "Metaplex", "  " .. pda)
    chat(player, "#888888", "Metaplex",
        "Bump: " .. tostring(bump) ..
        "  |  Seeds: ['mpl-core-execute', <agentMint>]")
    chat(player, "#888888", "Metaplex",
        "This is the agent's built-in wallet. Funds sent here are controlled")
    chat(player, "#888888", "Metaplex",
        "by the agent via MPL Core's Execute instruction — no private key exists.")
end)

-- ---
-- /mpagenttoken <wallet> <agentMint> <name> <symbol> <uri> <supply> [decimals] [bps]
-- Launch a simplified agent token: a fungible mint whose sole creator is
-- the agent's Asset Signer PDA. Routes creator attribution to the agent,
-- without the full Genesis bonding-curve / registerIdentity flow.
-- ---

addEvent("onMpAgentTokenResult", true)
addEventHandler("onMpAgentTokenResult", resourceRoot, function(result, err)
    local player = popPlayer("agenttoken")
    if not player then return end
    if err then
        chat(player, "#ff5555", "Metaplex", "Agent token failed: " .. tostring(err))
        return
    end

    chat(player, "#9b6dff", "Metaplex", "=== AGENT TOKEN LAUNCHED ===")
    chat(player, "#00ff88", "Metaplex", "Mint:          " .. tostring(result.mint))
    chat(player, "#00ff88", "Metaplex", "Metadata:      " .. tostring(result.metadata))
    chat(player, "#00ff88", "Metaplex", "Creator (PDA): " .. tostring(result.agentSigner))
    if result.ata then
        chat(player, "#00ff88", "Metaplex", "ATA:           " .. tostring(result.ata))
    end
    chat(player, "#00ff88", "Metaplex", "Signature:     " .. tostring(result.signature))
    if result.signature then
        chat(player, "#888888", "Metaplex",
            "Solscan: https://solscan.io/tx/" .. tostring(result.signature) .. "?cluster=devnet")
    end
    chat(player, "#ffaa00", "Metaplex",
        "Note: simplified demo. No bonding curve, no setToken binding.")
end)

addCommandHandler("mpagenttoken",
    function(player, _, wallet, agentMint, name, symbol, uri, supply, decimals, bps)
        if not wallet or not agentMint or not name or not symbol or not uri or not supply then
            chat(player, "#ffaa00", "Metaplex",
                "Usage: /mpagenttoken <wallet> <agentMint> <name> <symbol> <uri> <supply> [decimals] [bps]")
            chat(player, "#888888", "Metaplex",
                "agentMint must be the base58 Core asset address of an existing agent.")
            chat(player, "#888888", "Metaplex",
                "Example: /mpagenttoken <walletAddr> <agentMintAddr> \"Agent Coin\" AGT https://.../meta.json 1000000 9 0")
            return
        end

        local supplyStr = tostring(supply):gsub("^%+", "")
        if not supplyStr:match("^%d+$") or supplyStr == "0" then
            chat(player, "#ff5555", "Metaplex", "Supply must be a positive whole number")
            return
        end

        decimals = tonumber(decimals) or 9
        bps = tonumber(bps) or 0

        if not sol:hasWallet(wallet) then
            chat(player, "#ff5555", "Metaplex", "Wallet not loaded in solana-sdk")
            return
        end

        -- Preview: show the derived agent PDA so the player can confirm
        local pda = mp:findAgentAssetSigner(agentMint)
        if not pda then
            chat(player, "#ff5555", "Metaplex", "Invalid agentMint address")
            return
        end
        chat(player, "#9b6dff", "Metaplex",
            "Launching agent token... creator routes to:")
        chat(player, "#888888", "Metaplex", "  agent PDA = " .. pda)
        chat(player, "#888888", "Metaplex",
            "Atomic TX: CreateV1 (creators = [agentPda, 100%]) + ATA + MintTo")

        pushPlayer("agenttoken", player)
        mp:createAgentToken({
            wallet               = wallet,
            agentMint            = agentMint,
            name                 = name,
            symbol               = symbol,
            uri                  = uri,
            decimals             = decimals,
            sellerFeeBasisPoints = bps,
            initialSupply        = supplyStr,
        }, "onMpAgentTokenResult", resourceRoot)
    end)

-- ---
-- /mpagentcreate <wallet> <name> <description> <imageUri>
-- 3-step simplified agent creation:
--   1. Mints a 1/1 SPL token with name/symbol/placeholder-uri on-chain.
--   2. Returns the mint address (== agent asset address) and PDA.
--   3. Prints the ERC-8004 registration JSON so the user can upload it.
-- Next step is /mpagentsetreg once the JSON is hosted.
-- ---

addEvent("onMpAgentCreateResult", true)
addEventHandler("onMpAgentCreateResult", resourceRoot, function(result, err)
    local player = popPlayer("agentcreate")
    if not player then return end
    if err then
        chat(player, "#ff5555", "Agent", "Create failed: " .. tostring(err))
        return
    end

    chat(player, "#9b6dff", "Agent", "=== AGENT REGISTERED ON-CHAIN ===")
    chat(player, "#00ff88", "Agent", "Asset (agent id):    " .. tostring(result.agent))
    chat(player, "#00ff88", "Agent", "Collection:          " .. tostring(result.collection))
    chat(player, "#00ff88", "Agent", "Agent Identity PDA:  " .. tostring(result.agentIdentityPda))
    chat(player, "#00ff88", "Agent", "Asset Signer PDA:    " .. tostring(result.agentSigner))
    chat(player, "#00ff88", "Agent", "IPFS CID:            " .. tostring(result.ipfsCid))
    chat(player, "#00ff88", "Agent", "URI on-chain:        " .. tostring(result.onChainUri))
    chat(player, "#00ff88", "Agent", "Signature:           " .. tostring(result.signature))
    if result.signature then
        chat(player, "#888888", "Agent",
            "Solscan: https://solscan.io/tx/" .. tostring(result.signature) .. "?cluster=devnet")
    end
    if result.metaplexUrl then
        chat(player, "#ffaa00", "Agent",
            "=> metaplex.com: " .. tostring(result.metaplexUrl))
    end
    if result.gateways then
        chat(player, "#888888", "Agent", "Verify JSON via any gateway:")
        for k, v in pairs(result.gateways) do
            outputChatBox("#666666    " .. k .. ":  " .. v, player, 255, 255, 255, true)
        end
    end
end)

addCommandHandler("mpagentcreate", function(player, _, wallet, name, description, imageUri)
    if not wallet or not name or not description then
        chat(player, "#ffaa00", "Agent",
            "Usage: /mpagentcreate <wallet> <name> <description> [imageUri]")
        chat(player, "#888888", "Agent",
            "Example: /mpagentcreate <walletAddr> aa aa https://i.imgur.com/92DcjTK.png")
        chat(player, "#888888", "Agent",
            "imageUri optional — pass \"\" or skip if you don't have one yet.")
        return
    end
    if not sol:hasWallet(wallet) then
        chat(player, "#ff5555", "Agent", "Wallet not loaded in solana-sdk")
        return
    end

    local status = mp:getIpfsPinataStatus()
    if not status.configured then
        chat(player, "#ff5555", "Agent",
            "Pinata not configured. Set credentials in server.lua (PINATA_API_KEY / PINATA_API_SECRET)")
        chat(player, "#888888", "Agent",
            "or run /mpipfskey <apiKey> <apiSecret>")
        return
    end

    chat(player, "#9b6dff", "Agent",
        "Building ERC-8004 JSON -> uploading to IPFS -> minting atomic TX...")
    pushPlayer("agentcreate", player)
    mp:createAgent({
        wallet      = wallet,
        name        = name,
        description = description,
        image       = imageUri or "",
    }, "onMpAgentCreateResult", resourceRoot)
end)

-- ---
-- /mpagentjson <agentMint> <name> <description> <imageUri>
-- Re-generate the ERC-8004 JSON document without touching chain.
-- Handy if the user wants to tweak text before uploading.
-- ---

addCommandHandler("mpagentjson", function(player, _, agentMint, name, description, imageUri)
    if not agentMint or not name or not description or not imageUri then
        chat(player, "#ffaa00", "Agent",
            "Usage: /mpagentjson <agentMint> <name> <description> <imageUri>")
        return
    end
    local json = mp:buildAgentRegistrationJson(agentMint, {
        name        = name,
        description = description,
        image       = imageUri,
    })
    chat(player, "#9b6dff", "Agent", "ERC-8004 registration JSON for " .. agentMint .. ":")
    local CHUNK = 160
    for i = 1, #json, CHUNK do
        outputChatBox("#dddddd" .. json:sub(i, i + CHUNK - 1),
            player, 255, 255, 255, true)
    end
end)

-- ---
-- /mpagentsetreg <wallet> <agentMint> <registrationUri>
-- Updates the on-chain metadata URI so it points to the hosted ERC-8004 JSON.
-- Wallet must be the update authority (default: whoever created the agent).
-- ---

addEvent("onMpAgentSetRegResult", true)
addEventHandler("onMpAgentSetRegResult", resourceRoot, function(result, err)
    local player = popPlayer("agentsetreg")
    if not player then return end
    if err then
        chat(player, "#ff5555", "Agent", "Update failed: " .. tostring(err))
        return
    end
    chat(player, "#00ff88", "Agent", "Agent registration URI updated!")
    chat(player, "#00ff88", "Agent", "Signature: " .. tostring(result.signature))
    if result.updated and result.updated.uri then
        chat(player, "#888888", "Agent", "New URI: " .. tostring(result.updated.uri))
    end
end)

addCommandHandler("mpagentsetreg",
    function(player, _, wallet, agentMint, registrationUri)
        if not wallet or not agentMint or not registrationUri then
            chat(player, "#ffaa00", "Agent",
                "Usage: /mpagentsetreg <wallet> <agentMint> <registrationUri>")
            return
        end
        if not sol:hasWallet(wallet) then
            chat(player, "#ff5555", "Agent", "Wallet not loaded")
            return
        end
        chat(player, "#9b6dff", "Agent", "Submitting updateV1 with new URI...")
        pushPlayer("agentsetreg", player)
        mp:setAgentRegistrationUri({
            wallet = wallet,
            agent  = agentMint,
            uri    = registrationUri,
        }, "onMpAgentSetRegResult", resourceRoot)
    end)

-- ---
-- IPFS / Pinata config commands
-- ---

local function maskJwt(jwt)
    if not jwt then return "(none)" end
    if #jwt <= 16 then return string.rep("*", #jwt) end
    return jwt:sub(1, 8) .. "..." .. jwt:sub(-6)
end

local function setJwtHandler(player, _, jwt)
    if not jwt or #jwt < 20 then
        chat(player, "#ffaa00", "IPFS", "Usage: /mpipfsjwt <pinataJwt>")
        chat(player, "#888888", "IPFS",
            "Get a JWT at https://app.pinata.cloud/developers/api-keys (free tier).")
        chat(player, "#888888", "IPFS",
            "Stored in server memory only — gone on resource restart. /mpipfstest to verify.")
        return
    end
    local ok = mp:setIpfsPinataJwt(jwt)
    if ok then
        chat(player, "#00ff88", "IPFS", "Pinata JWT stored: " .. maskJwt(jwt))
        chat(player, "#888888", "IPFS", "Run /mpipfstest to verify auth.")
    else
        chat(player, "#ff5555", "IPFS", "Failed to store JWT.")
    end
end

addCommandHandler("mpipfsjwt",    setJwtHandler)
addCommandHandler("mpipfsconfig", setJwtHandler)   -- legacy alias

addCommandHandler("mpipfskey", function(player, _, apiKey, apiSecret)
    if not apiKey or not apiSecret or #apiKey < 10 or #apiSecret < 20 then
        chat(player, "#ffaa00", "IPFS", "Usage: /mpipfskey <apiKey> <apiSecret>")
        chat(player, "#888888", "IPFS",
            "Create an API Key + Secret at https://app.pinata.cloud/developers/api-keys")
        chat(player, "#888888", "IPFS",
            "Stored in server memory only — gone on resource restart. /mpipfstest to verify.")
        return
    end
    local ok = mp:setIpfsPinataKey(apiKey, apiSecret)
    if ok then
        chat(player, "#00ff88", "IPFS",
            "Pinata API Key stored: " .. maskJwt(apiKey) ..
            "  |  secret: " .. maskJwt(apiSecret))
        chat(player, "#888888", "IPFS", "Run /mpipfstest to verify auth.")
    else
        chat(player, "#ff5555", "IPFS", "Failed to store credentials.")
    end
end)

addCommandHandler("mpipfsclear", function(player)
    mp:clearIpfsPinataAuth()
    chat(player, "#00ff88", "IPFS", "Pinata credentials cleared.")
end)

addCommandHandler("mpipfsstatus", function(player)
    local s = mp:getIpfsPinataStatus()
    if not s.configured then
        chat(player, "#ffaa00", "IPFS", "No credentials. Use /mpipfskey or /mpipfsjwt.")
        return
    end
    if s.mode == "jwt" then
        chat(player, "#00ff88", "IPFS", "Auth mode: JWT  (" .. tostring(s.masked) .. ")")
    elseif s.mode == "key" then
        chat(player, "#00ff88", "IPFS",
            "Auth mode: API Key + Secret  (key=" .. tostring(s.apiKey) ..
            ", secret=" .. tostring(s.apiSecret) .. ")")
    end
end)

addEvent("onMpIpfsTestResult", true)
addEventHandler("onMpIpfsTestResult", resourceRoot, function(result)
    local player = popPlayer("ipfstest")
    if not player then return end
    if result and result.ok then
        chat(player, "#00ff88", "IPFS", "Auth OK — Pinata accepts your JWT.")
    else
        chat(player, "#ff5555", "IPFS",
            "Auth failed: " .. tostring(result and result.message or "unknown"))
    end
end)

addCommandHandler("mpipfstest", function(player)
    pushPlayer("ipfstest", player)
    chat(player, "#9b6dff", "IPFS", "Pinging Pinata...")
    mp:testIpfsAuth("onMpIpfsTestResult", resourceRoot)
end)

-- ---
-- /mpagentpublish <wallet> <agentMint> <name> <description> <imageUri>
-- One-shot: build ERC-8004 JSON -> upload to IPFS -> updateV1 metadata uri.
-- ---

addEvent("onMpAgentPublishResult", true)
addEventHandler("onMpAgentPublishResult", resourceRoot, function(result, err)
    local player = popPlayer("agentpublish")
    if not player then return end
    if err then
        chat(player, "#ff5555", "Agent", "Publish failed: " .. tostring(err))
        return
    end
    chat(player, "#9b6dff", "Agent", "=== AGENT PUBLISHED ===")
    chat(player, "#00ff88", "Agent", "IPFS CID:   " .. tostring(result.cid))
    chat(player, "#00ff88", "Agent", "ipfs:// URI:" .. tostring(result.ipfsUri))
    chat(player, "#00ff88", "Agent", "https URL:  " .. tostring(result.httpsUri))
    chat(player, "#00ff88", "Agent", "On-chain sig: " .. tostring(result.signature))
    chat(player, "#888888", "Agent", "Verify in browser: " .. tostring(result.httpsUri))
    if result.gateways then
        chat(player, "#888888", "Agent", "Other gateways:")
        for k, v in pairs(result.gateways) do
            outputChatBox("#666666    " .. k .. ": " .. v, player, 255, 255, 255, true)
        end
    end
end)

addCommandHandler("mpagentpublish",
    function(player, _, wallet, agentMint, name, description, imageUri)
        if not wallet or not agentMint or not name or not description then
            chat(player, "#ffaa00", "Agent",
                "Usage: /mpagentpublish <wallet> <agentMint> <name> <description> <imageUri>")
            chat(player, "#888888", "Agent",
                "Builds ERC-8004 JSON, uploads to IPFS via Pinata, and points the agent's metadata URI at the result.")
            return
        end
        if not sol:hasWallet(wallet) then
            chat(player, "#ff5555", "Agent", "Wallet not loaded in solana-sdk")
            return
        end
        local s = mp:getIpfsPinataStatus()
        if not s.configured then
            chat(player, "#ff5555", "Agent",
                "Pinata JWT not configured. Run /mpipfsconfig <jwt> first.")
            return
        end
        chat(player, "#9b6dff", "Agent",
            "Building JSON -> uploading to IPFS -> updating on-chain URI...")
        pushPlayer("agentpublish", player)
        mp:publishAgent({
            wallet      = wallet,
            agent       = agentMint,
            name        = name,
            description = description,
            image       = imageUri or "",
        }, "onMpAgentPublishResult", resourceRoot)
    end)
