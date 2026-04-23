-- https://github.com/yongsxyz
--[[
    Metaplex SDK - High-level exports.

    Async results are delivered through events (mirrors solana-sdk's pattern):
        exports["metaplex-sdk"]:createFungibleToken(opts, "onMyEvent", resourceRoot)

        addEvent("onMyEvent", true)
        addEventHandler("onMyEvent", resourceRoot, function(result, err) ... end)

    All blockchain heavy lifting (fetchRemote, sign, send) is delegated to
    the solana-sdk resource via exports.
]]

local sol = exports["solana-sdk"]

-- ---
-- Init (no-op; we don't keep state — solana-sdk owns the RPC client)
-- ---

function initMetaplex()
    -- Nothing to do. Confirms the resource is loaded.
    outputDebugString("[metaplex-sdk] Ready. Token Metadata program: " ..
        TokenMetadataProgram.PROGRAM_ID)
    return true
end

addEventHandler("onResourceStart", resourceRoot, function()
    initMetaplex()
end)

-- ---
-- Constants
-- ---

function getTokenMetadataProgramId()
    return TokenMetadataProgram.PROGRAM_ID
end

function getTokenStandards()
    -- Shallow copy so callers can't accidentally mutate
    local out = {}
    for k, v in pairs(TokenMetadataProgram.TOKEN_STANDARD) do out[k] = v end
    return out
end

-- ---
-- PDA helpers (synchronous)
-- ---

function findMetadataPda(mintAddress)
    return TokenMetadataProgram.findMetadataPda(mintAddress)
end

function findMasterEditionPda(mintAddress)
    return TokenMetadataProgram.findMasterEditionPda(mintAddress)
end

function findAssociatedTokenAddress(walletAddress, mintAddress, tokenProgramId)
    return TokenMetadataProgram.findAssociatedTokenAddress(walletAddress, mintAddress, tokenProgramId)
end

-- Derive an MPL Core agent's Asset Signer PDA — deterministic.
-- Returns (address, bump). This is the built-in wallet address for the
-- registered agent (seeds = ["mpl-core-execute", agentMint]).
function findAgentAssetSigner(agentMintAddress)
    return TokenMetadataProgram.findAgentAssetSignerPda(agentMintAddress)
end

-- ---
-- Internal helpers
-- ---

local function fire(eventName, eventSource, ...)
    if eventName and eventSource then
        triggerEvent(eventName, eventSource, ...)
    end
end

local function ensureWallet(addr)
    if not sol:hasWallet(addr) then
        return false, "Wallet not loaded in solana-sdk: " .. tostring(addr)
    end
    return true
end

-- ---
-- createFungibleToken
--   Creates a fresh mint (new keypair stored in solana-sdk) and submits
--   a CreateV1 instruction. The mint's authority and update authority
--   are set to the provided wallet.
--
--   opts:
--     wallet             base58 of an imported wallet (acts as authority + payer)
--     name               token name
--     symbol             token symbol
--     uri                URI of the off-chain JSON metadata
--     decimals           integer (e.g. 9). Defaults to 9.
--     sellerFeeBasisPoints  optional, default 0
--     isMutable          optional bool, default true
--     creators           optional, default = single creator (wallet, share 100, verified)
--     mintAddress        optional pre-generated mint base58 (must already be in solana-sdk)
--                        If omitted, a new mint keypair is generated automatically.
--
--   Result event payload:
--     { mint = "...", metadata = "...", signature = "..." }
-- ---
function createFungibleToken(opts, eventName, eventSource)
    opts = opts or {}

    local ok, err = ensureWallet(opts.wallet)
    if not ok then fire(eventName, eventSource, nil, err); return end

    -- Mint: either user-supplied or freshly generated.
    local mintAddress = opts.mintAddress
    local mintIsFresh = false
    if not mintAddress then
        mintAddress = sol:createWallet()
        if not mintAddress then
            fire(eventName, eventSource, nil, "Failed to create mint keypair")
            return
        end
        mintIsFresh = true
    elseif not sol:hasWallet(mintAddress) then
        fire(eventName, eventSource, nil, "Provided mintAddress is not in solana-sdk wallet store")
        return
    end

    local ix, ixErr = TokenMetadataProgram.createV1({
        mint                  = mintAddress,
        authority             = opts.wallet,
        payer                 = opts.wallet,
        updateAuthority       = opts.updateAuthority or opts.wallet,
        name                  = opts.name or "Untitled",
        symbol                = opts.symbol or "",
        uri                   = opts.uri or "",
        sellerFeeBasisPoints  = opts.sellerFeeBasisPoints or 0,
        tokenStandard         = TokenMetadataProgram.TOKEN_STANDARD.Fungible,
        decimals              = opts.decimals == nil and 9 or opts.decimals,
        isMutable             = opts.isMutable,
        primarySaleHappened   = opts.primarySaleHappened,
        creators              = opts.creators,
    })

    if not ix then
        if mintIsFresh then sol:removeWallet(mintAddress) end
        fire(eventName, eventSource, nil, ixErr or "Failed to build createV1 instruction")
        return
    end

    local metadataAddress = select(1, TokenMetadataProgram.findMetadataPda(mintAddress))

    -- The mint must be a signer too (alongside authority/payer wallet)
    -- Internal callback bridge: solana-sdk fires its own event when done
    local cbEvent = "onMetaplexCreateFungibleInternal_" .. tostring(getTickCount()) .. "_" .. tostring(math.random(1, 1e9))
    addEvent(cbEvent, true)
    local handler
    handler = function(result, sendErr)
        removeEventHandler(cbEvent, resourceRoot, handler)
        if sendErr then
            fire(eventName, eventSource, nil, sendErr)
            return
        end
        fire(eventName, eventSource, {
            mint      = mintAddress,
            metadata  = metadataAddress,
            signature = result and result.signature,
        })
    end
    addEventHandler(cbEvent, resourceRoot, handler)

    sol:sendCustomTransaction(opts.wallet, { ix }, { opts.wallet, mintAddress }, cbEvent, resourceRoot)
end

-- ---
-- createTokenAccount
--   Builds and sends a CreateIdempotent ATA instruction. Safe to call even
--   if the ATA already exists.
--
--   opts:
--     wallet         base58 (payer; must be loaded in solana-sdk)
--     owner          base58 (defaults to wallet)
--     mint           base58
--     tokenProgram   optional (defaults to SPL Token)
--
--   Result payload: { ata = "...", signature = "..." }
-- ---
function createTokenAccount(opts, eventName, eventSource)
    opts = opts or {}
    local ok, err = ensureWallet(opts.wallet)
    if not ok then fire(eventName, eventSource, nil, err); return end

    local owner = opts.owner or opts.wallet
    local ataAddress = select(1, TokenMetadataProgram.findAssociatedTokenAddress(
        owner, opts.mint, opts.tokenProgram))
    if not ataAddress then
        fire(eventName, eventSource, nil, "Failed to derive ATA")
        return
    end

    local ix = TokenMetadataProgram.createIdempotentAta({
        payer        = opts.wallet,
        ata          = ataAddress,
        walletOwner  = owner,
        mint         = opts.mint,
        tokenProgram = opts.tokenProgram,
    })

    local cbEvent = "onMetaplexCreateAtaInternal_" .. tostring(getTickCount()) .. "_" .. tostring(math.random(1, 1e9))
    addEvent(cbEvent, true)
    local handler
    handler = function(result, sendErr)
        removeEventHandler(cbEvent, resourceRoot, handler)
        if sendErr then fire(eventName, eventSource, nil, sendErr); return end
        fire(eventName, eventSource, { ata = ataAddress, signature = result and result.signature })
    end
    addEventHandler(cbEvent, resourceRoot, handler)

    sol:sendCustomTransaction(opts.wallet, { ix }, { opts.wallet }, cbEvent, resourceRoot)
end

-- ---
-- mintTokensTo
--   Submits a single SPL Token MintTo instruction.
--
--   opts:
--     wallet     base58 of mint authority (signer)
--     mint       base58
--     token      base58 ATA (must already exist; use createTokenAccount first)
--     amount     raw u64 (e.g. 1_000_000_000_000_000 for 1,000,000 with 9 decimals)
--
--   Result payload: { signature = "..." }
-- ---
function mintTokensTo(opts, eventName, eventSource)
    opts = opts or {}
    local ok, err = ensureWallet(opts.wallet)
    if not ok then fire(eventName, eventSource, nil, err); return end

    local ix = TokenMetadataProgram.mintTo({
        mint          = opts.mint,
        token         = opts.token,
        mintAuthority = opts.wallet,
        amount        = opts.amount,
    })

    local cbEvent = "onMetaplexMintToInternal_" .. tostring(getTickCount()) .. "_" .. tostring(math.random(1, 1e9))
    addEvent(cbEvent, true)
    local handler
    handler = function(result, sendErr)
        removeEventHandler(cbEvent, resourceRoot, handler)
        if sendErr then fire(eventName, eventSource, nil, sendErr); return end
        fire(eventName, eventSource, { signature = result and result.signature })
    end
    addEventHandler(cbEvent, resourceRoot, handler)

    sol:sendCustomTransaction(opts.wallet, { ix }, { opts.wallet }, cbEvent, resourceRoot)
end

-- ---
-- createAndMintFungible
--   Atomic one-shot: creates the fungible token, its ATA for `owner`, and
--   mints the initial supply — ALL in a single Solana transaction.
--
--   Why a single transaction:
--     * Eliminates cross-tx race conditions (no "mint doesn't exist yet"
--       errors when the next step fires before the previous one confirms).
--     * Uses one signature from wallet + one from mint, shared across all
--       three instructions — saves 2 of 3 pure-Lua signings (~1s).
--     * Matches the on-chain semantics of the docs example. The docs split
--       it into two transactions only because Umi's `sendAndConfirm()` is
--       the natural unit — the Solana runtime itself is happy with one.
--
--   opts:
--     wallet                required, base58 of mint authority / payer.
--     name, symbol, uri     token metadata.
--     decimals              default 9.
--     sellerFeeBasisPoints  default 0.
--     amount                raw u64 to mint. Lua number OR digit string.
--     initialSupply         human units (e.g. 1000000). Auto-multiplied by
--                           10^decimals to produce the raw u64. Wins over
--                           `amount` when both are set. Safe for any
--                           decimals up to the SPL u64 ceiling (~1.8e19).
--     owner                 recipient of the minted supply (default wallet).
--
--   Result payload:
--     { mint, metadata, ata, signature }   -- single atomic signature
-- ---
function createAndMintFungible(opts, eventName, eventSource)
    opts = opts or {}

    local ok, err = ensureWallet(opts.wallet)
    if not ok then fire(eventName, eventSource, nil, err); return end

    -- Resolve amount from initialSupply (human units) if provided.
    local decimals = opts.decimals == nil and 9 or opts.decimals
    if opts.initialSupply ~= nil then
        local raw, hErr = MetaplexBorsh.humanToRawString(opts.initialSupply, decimals)
        if not raw then
            fire(eventName, eventSource, nil, "Invalid initialSupply: " .. tostring(hErr))
            return
        end
        if raw ~= "0" then opts.amount = raw end
    end

    -- Enforce SPL u64 ceiling so we fail BEFORE signing anything on-chain.
    if type(opts.amount) == "string" then
        local SPL_U64_MAX = "18446744073709551615"
        local a = opts.amount:gsub("^0+", "")
        if a == "" then a = "0" end
        local overflow = (#a > #SPL_U64_MAX) or (#a == #SPL_U64_MAX and a > SPL_U64_MAX)
        if overflow then
            fire(eventName, eventSource, nil,
                "amount " .. opts.amount .. " exceeds SPL u64 max (" .. SPL_U64_MAX ..
                "). Reduce supply or decimals.")
            return
        end
    end

    -- Pre-generated mint (opts.mintAddress) or fresh keypair from solana-sdk.
    -- The agent flow pre-generates a mint so it can build + upload a JSON
    -- containing the mint address BEFORE the on-chain transaction runs.
    local mintAddress = opts.mintAddress
    if mintAddress then
        if not sol:hasWallet(mintAddress) then
            fire(eventName, eventSource, nil,
                "opts.mintAddress must already be in solana-sdk's wallet store")
            return
        end
    else
        mintAddress = sol:createWallet()
        if not mintAddress then
            fire(eventName, eventSource, nil, "Failed to create mint keypair")
            return
        end
    end

    local owner = opts.owner or opts.wallet

    -- Build all three instructions.
    local createIx, cErr = TokenMetadataProgram.createV1({
        mint                  = mintAddress,
        authority             = opts.wallet,
        payer                 = opts.wallet,
        updateAuthority       = opts.updateAuthority or opts.wallet,
        name                  = opts.name or "Untitled",
        symbol                = opts.symbol or "",
        uri                   = opts.uri or "",
        sellerFeeBasisPoints  = opts.sellerFeeBasisPoints or 0,
        tokenStandard         = TokenMetadataProgram.TOKEN_STANDARD.Fungible,
        decimals              = decimals,
        isMutable             = opts.isMutable,
        primarySaleHappened   = opts.primarySaleHappened,
        creators              = opts.creators,
    })
    if not createIx then
        sol:removeWallet(mintAddress)
        fire(eventName, eventSource, nil, cErr or "Failed to build createV1")
        return
    end

    local metadataAddress = select(1, TokenMetadataProgram.findMetadataPda(mintAddress))
    local ataAddress      = select(1, TokenMetadataProgram.findAssociatedTokenAddress(owner, mintAddress))

    local instructions = { createIx }

    -- Mint supply only if requested.
    local mintAmount = opts.amount
    local hasMint = (mintAmount ~= nil and mintAmount ~= 0 and mintAmount ~= "0")
    if hasMint then
        instructions[#instructions + 1] = TokenMetadataProgram.createIdempotentAta({
            payer       = opts.wallet,
            ata         = ataAddress,
            walletOwner = owner,
            mint        = mintAddress,
        })
        instructions[#instructions + 1] = TokenMetadataProgram.mintTo({
            mint          = mintAddress,
            token         = ataAddress,
            mintAuthority = opts.wallet,
            amount        = mintAmount,
        })
    end

    -- Single TX, single sign pass, two signers (wallet + mint).
    local cbEvent = "onMetaplexAtomic_" .. tostring(getTickCount()) .. "_" .. tostring(math.random(1, 1e9))
    addEvent(cbEvent, true)
    local handler
    handler = function(result, sendErr)
        removeEventHandler(cbEvent, resourceRoot, handler)
        if sendErr then
            sol:removeWallet(mintAddress) -- rollback fresh keypair on failure
            fire(eventName, eventSource, nil, sendErr)
            return
        end
        fire(eventName, eventSource, {
            mint      = mintAddress,
            metadata  = metadataAddress,
            ata       = hasMint and ataAddress or nil,
            signature = result and result.signature,
        })
    end
    addEventHandler(cbEvent, resourceRoot, handler)

    sol:sendCustomTransaction(
        opts.wallet, instructions, { opts.wallet, mintAddress },
        cbEvent, resourceRoot
    )
end

-- ---
-- buildTokenMetadataJson
--   Builds the "Fungible Standard" metadata JSON used for SPL tokens:
--     { name, symbol, description, image }
--
--   Hosted at the URI passed to createV1/updateV1 — indexers and wallets
--   fetch this to display name/logo/description.
-- ---
function buildTokenMetadataJson(opts)
    opts = opts or {}
    local ordered = {
        { "name",        opts.name        or "" },
        { "symbol",      opts.symbol      or "" },
        { "description", opts.description or "" },
        { "image",       opts.image       or "" },
    }
    if opts.externalUrl then
        ordered[#ordered + 1] = { "external_url", opts.externalUrl }
    end
    if opts.attributes then
        ordered[#ordered + 1] = { "attributes", opts.attributes }
    end
    return MetaplexJson.encodeOrdered(ordered)
end

-- ---
-- createAndPublishFungible
--   High-level wrapper: builds the token metadata JSON, uploads it to
--   IPFS (Pinata), then atomically mints the fungible with the IPFS URL
--   as the on-chain URI.
--
--   opts (super-set of createAndMintFungible):
--     wallet, name, symbol      required
--     description               optional (default "")
--     image                     optional (default "")
--     decimals                  default 9
--     initialSupply             human units (string or number)
--     sellerFeeBasisPoints      default 0
--     gateway                   optional, "ipfs_io" | "pinata" | "dweb" | ...
--     externalUrl, attributes   optional, passed through to metadata JSON
--
--   Result payload: same as createAndMintFungible + {
--     tokenMetadataJson, ipfsCid, ipfsUri, onChainUri, gateways
--   }
-- ---
function createAndPublishFungible(opts, eventName, eventSource)
    opts = opts or {}
    if not opts.wallet or not opts.name or not opts.symbol then
        fire(eventName, eventSource, nil, "wallet, name, symbol are required")
        return
    end
    if not MetaplexIpfs.hasPinataAuth() then
        fire(eventName, eventSource, nil,
            "Pinata auth not configured. Call setIpfsPinataKey / setIpfsPinataJwt first.")
        return
    end

    local json = buildTokenMetadataJson({
        name        = opts.name,
        symbol      = opts.symbol,
        description = opts.description or "",
        image       = opts.image or "",
        externalUrl = opts.externalUrl,
        attributes  = opts.attributes,
    })

    MetaplexIpfs.uploadJson(json, {
        name = "token-" .. tostring(opts.symbol) .. "-" .. tostring(getTickCount()),
    }, function(upload, upErr)
        if upErr then
            fire(eventName, eventSource, nil, "IPFS upload failed: " .. tostring(upErr))
            return
        end

        local gw = opts.gateway or "ipfs_io"
        local uriOnChain = (gw == "ipfs") and upload.ipfsUri
            or ((upload.gateways and upload.gateways[gw]) or upload.gateways.ipfs_io)

        local cbEvent = "onMetaplexCAPF_" ..
            tostring(getTickCount()) .. "_" .. tostring(math.random(1, 1e9))
        addEvent(cbEvent, true)
        local handler
        handler = function(result, err)
            removeEventHandler(cbEvent, resourceRoot, handler)
            if err then fire(eventName, eventSource, nil, err); return end
            result = result or {}
            result.tokenMetadataJson = json
            result.ipfsCid           = upload.cid
            result.ipfsUri           = upload.ipfsUri
            result.onChainUri        = uriOnChain
            result.gateways          = upload.gateways
            fire(eventName, eventSource, result)
        end
        addEventHandler(cbEvent, resourceRoot, handler)

        createAndMintFungible({
            wallet               = opts.wallet,
            name                 = opts.name,
            symbol               = opts.symbol,
            uri                  = uriOnChain,
            decimals             = opts.decimals,
            sellerFeeBasisPoints = opts.sellerFeeBasisPoints,
            initialSupply        = opts.initialSupply,
            amount               = opts.amount,
            isMutable            = opts.isMutable,
            creators             = opts.creators,
        }, cbEvent, resourceRoot)
    end)
end

-- ---
-- buildAgentRegistrationJson
--   Produce an ERC-8004 registration JSON string. No network IO — pure
--   string building. Matches the field shape the Metaplex agent UI emits
--   in its "Default" mode (the same JSON spec at
--   https://eips.ethereum.org/EIPS/eip-8004#registration-v1).
--
--   opts (all optional except name/description/image which fall back to
--   defaults if missing — but you should ALWAYS provide them):
--     name           string, agent display name
--     description    string, natural-language description
--     image          string, image URL (Arweave / IPFS / HTTPS)
--     services       list of { name, endpoint, version?, skills?, domains? }
--                    default: single "web" entry
--     x402Support    bool, default false
--     active         bool, default true
--     registrations  list of { agentId, agentRegistry }, default = []
--                    (the Metaplex UI leaves this empty in Default mode)
--     supportedTrust list of strings, default = []
--                    e.g. ["reputation", "crypto-economic", "tee-attestation"]
--     externalLinks  optional { website, twitter, telegram }
--
--   Returns: JSON string (compact, no pretty-printing — MTA's toJSON output).
-- ---
function buildAgentRegistrationJson(agentMint, opts)
    opts = opts or {}

    local services = opts.services
    if not services or #services == 0 then
        services = {
            { name = "web", endpoint = "https://example.com/agent/" .. tostring(agentMint) },
        }
    else
        -- Auto-fill the "web" endpoint when the caller left it blank
        -- (common when the UI has a dynamic service list with web pre-added).
        for _, s in ipairs(services) do
            if s.name == "web" and (not s.endpoint or s.endpoint == "") then
                s.endpoint = "https://example.com/agent/" .. tostring(agentMint)
            end
        end
    end

    local active = opts.active
    if active == nil then active = true end

    local x402Support = opts.x402Support
    if x402Support == nil then x402Support = false end

    -- Ordered key emission so the JSON matches the ERC-8004 spec example
    -- byte-for-byte. Uses our own encoder to avoid MTA toJSON's outer
    -- `[ ... ]` array wrap (which corrupts object-expected endpoints).
    local ordered = {
        { "type",           "https://eips.ethereum.org/EIPS/eip-8004#registration-v1" },
        { "name",           opts.name or "Unnamed Agent" },
        { "description",    opts.description or "" },
        { "image",          opts.image or "" },
        { "services",       services },
        { "x402Support",    x402Support },
        { "active",         active },
        { "registrations",  opts.registrations or {} },
        { "supportedTrust", opts.supportedTrust or {} },
    }
    if opts.externalLinks then
        ordered[#ordered + 1] = { "externalLinks", opts.externalLinks }
    end
    return MetaplexJson.encodeOrdered(ordered)
end

-- ---
-- createAgent  (REAL MPL Core + MPL Agent Identity flow)
--
-- Produces an on-chain entity that WILL appear on metaplex.com/agents:
--   1. Pre-generate two keypairs (collection + asset), both stored in
--      solana-sdk's wallet table so they can sign the tx.
--   2. Build the ERC-8004 registration JSON, embed the asset's pubkey in it.
--   3. Upload the JSON to IPFS (Pinata).
--   4. Submit ONE atomic transaction containing three instructions:
--        (a) MPL Core createCollectionV2
--        (b) MPL Core createV2             (asset under collection)
--        (c) MPL Agent Identity registerIdentityV1
--      Signers: wallet (payer + authority), collection, asset.
--
-- Why atomic: if any instruction fails, NOTHING lands on-chain —
-- prevents orphan assets / half-registered agents.
--
-- Requires Pinata auth to be configured (setIpfsPinataJwt OR setIpfsPinataKey).
--
--   What we do:
--     * Mint a fresh 1/1 SPL token (decimals=0, supply=1) to the wallet,
--       atomic `CreateV1 + ATA + MintTo` (same as createAndMintFungible).
--     * The mint address IS the "agent asset address" — seeds for the
--       Asset Signer PDA match MPL Core's formula exactly:
--       ['mpl-core-execute', mint]. The PDA is a real Solana address that
--       can receive SOL/tokens.
--     * Set metadata { name, symbol, uri }. The uri starts empty/placeholder
--       because the user still needs to host the registration JSON.
--     * Build the ERC-8004 registration JSON string and return it in the
--       callback so the user can copy/paste into Arweave.
--
--   What we do NOT do:
--     * NO `registerIdentityV1` — we can't create the AgentIdentity plugin
--       without implementing MPL Core's plugin serialization.
--     * NO MPL Core lifecycle hooks (transfer/update/execute gating).
--     * NO collection grouping.
--
--   opts:
--     wallet         required, base58
--     name           required, max 32
--     description    required (used in registration JSON)
--     image          required, Arweave or HTTPS URL
--     symbol         optional, default = first 6 chars of name uppercased
--     registrationUri optional, if already hosted. Otherwise a placeholder
--                     URL is used and the caller is expected to upload the
--                     generated JSON and then call setAgentRegistrationUri.
--     services       optional, passed through to buildAgentRegistrationJson
--     supportedTrust optional, passed through
--
--   Result payload:
--     {
--       agent             = mint address,
--       metadata          = metadata PDA,
--       ata               = owner ATA (1/1 holder),
--       agentSigner       = Asset Signer PDA (derived),
--       agentSignerBump   = bump,
--       signature         = create transaction signature,
--       registrationJson  = ERC-8004 JSON string for upload,
--       placeholderUri    = the metadata URI we set on chain,
--     }
-- ---
function createAgent(opts, eventName, eventSource)
    opts = opts or {}
    if not opts.wallet or not opts.name or not opts.description then
        fire(eventName, eventSource, nil,
            "wallet, name, description are required")
        return
    end
    if not MetaplexIpfs.hasPinataAuth() then
        fire(eventName, eventSource, nil,
            "Pinata auth not configured. Call setIpfsPinataKey / setIpfsPinataJwt first.")
        return
    end

    local ok, err = ensureWallet(opts.wallet)
    if not ok then fire(eventName, eventSource, nil, err); return end

    local image = opts.image or ""

    -- Step 1: pre-generate collection + asset keypairs. Both need to sign
    -- the creation transaction (allocating their own accounts on-chain).
    local collectionAddr = sol:createWallet()
    if not collectionAddr then
        fire(eventName, eventSource, nil, "Failed to generate collection keypair")
        return
    end
    local assetAddr = sol:createWallet()
    if not assetAddr then
        sol:removeWallet(collectionAddr)
        fire(eventName, eventSource, nil, "Failed to generate asset keypair")
        return
    end

    -- Rollback helper for any failure path.
    local rollback = function()
        sol:removeWallet(collectionAddr)
        sol:removeWallet(assetAddr)
    end

    -- Step 2: build the ERC-8004 JSON — the asset address goes in
    -- services.web.endpoint so the doc self-identifies.
    local json = buildAgentRegistrationJson(assetAddr, {
        name           = opts.name,
        description    = opts.description,
        image          = image,
        services       = opts.services,
        active         = opts.active,
        x402Support    = opts.x402Support,
        supportedTrust = opts.supportedTrust,
        registrations  = opts.registrations,
        externalLinks  = opts.externalLinks,
    })

    -- Step 3: upload the JSON to IPFS (Pinata).
    MetaplexIpfs.uploadJson(json, {
        name = "agent-" .. assetAddr:sub(1, 12),
    }, function(upload, upErr)
        if upErr then
            rollback()
            fire(eventName, eventSource, nil, "IPFS upload failed: " .. tostring(upErr))
            return
        end

        -- URI to write on chain. Default = ipfs.io gateway URL.
        local gw = opts.gateway or "ipfs_io"
        local uriOnChain = (gw == "ipfs")
            and upload.ipfsUri
            or  ((upload.gateways and upload.gateways[gw]) or upload.gateways.ipfs_io)

        -- Derive agent identity PDA (will be created by registerIdentityV1).
        local agentIdentityPda =
            select(1, MplAgentIdentityProgram.findAgentIdentityPda(assetAddr))

        -- Step 4: build the three instructions for the atomic tx.
        local ixCollection = MplCoreProgram.createCollectionV2({
            collection      = collectionAddr,
            updateAuthority = opts.wallet,
            payer           = opts.wallet,
            name            = opts.name .. " Collection",
            uri             = uriOnChain,
        })

        -- IMPORTANT: updateAuthority MUST be nil when collection is provided.
        -- MPL Core returns ConflictingAuthority (0x1d) otherwise:
        --   processor/create.rs:84-86
        --   if update_authority.is_some() && collection.is_some() { err }
        -- The collection's update authority is inherited.
        local ixAsset = MplCoreProgram.createV2({
            asset      = assetAddr,
            collection = collectionAddr,
            authority  = opts.wallet,
            payer      = opts.wallet,
            -- updateAuthority intentionally omitted
            name       = opts.name,
            uri        = uriOnChain,
        })

        local ixRegister = MplAgentIdentityProgram.registerIdentityV1({
            agentIdentity        = agentIdentityPda,
            asset                = assetAddr,
            collection           = collectionAddr,
            payer                = opts.wallet,
            authority            = opts.wallet,
            agentRegistrationUri = uriOnChain,
        })

        -- Step 5: submit as ONE atomic transaction.
        -- Signers: wallet (payer+authority), collection (new account), asset (new account).
        local cbEvent = "onMetaplexRealAgent_" ..
            tostring(getTickCount()) .. "_" .. tostring(math.random(1, 1e9))
        addEvent(cbEvent, true)
        local handler
        handler = function(result, sendErr)
            removeEventHandler(cbEvent, resourceRoot, handler)
            if sendErr then
                rollback()
                fire(eventName, eventSource, nil, "On-chain flow failed: " .. tostring(sendErr))
                return
            end

            -- Asset Signer PDA (built-in wallet — seeds ['mpl-core-execute', asset])
            local agentSigner, signerBump =
                TokenMetadataProgram.findAgentAssetSignerPda(assetAddr)

            fire(eventName, eventSource, {
                agent              = assetAddr,
                collection         = collectionAddr,
                agentIdentityPda   = agentIdentityPda,
                agentSigner        = agentSigner,
                agentSignerBump    = signerBump,
                registrationJson   = json,
                ipfsCid            = upload.cid,
                ipfsUri            = upload.ipfsUri,
                onChainUri         = uriOnChain,
                gateways           = upload.gateways,
                signature          = result and result.signature,
                metaplexUrl        = "https://www.metaplex.com/agent/" .. assetAddr,
            })
        end
        addEventHandler(cbEvent, resourceRoot, handler)

        sol:sendCustomTransaction(
            opts.wallet,
            { ixCollection, ixAsset, ixRegister },
            { opts.wallet, collectionAddr, assetAddr },
            cbEvent, resourceRoot
        )
    end)
end

-- ---
-- IPFS upload helpers (thin wrappers around metaplex_ipfs.lua)
-- ---

function setIpfsPinataJwt(jwt)
    return MetaplexIpfs.setPinataJwt(jwt)
end

function setIpfsPinataKey(apiKey, apiSecret)
    return MetaplexIpfs.setPinataKey(apiKey, apiSecret)
end

function clearIpfsPinataAuth()
    MetaplexIpfs.clearPinataAuth()
    return true
end

function getIpfsPinataStatus()
    -- Back-compat shape + expanded info
    local info = MetaplexIpfs.authInfo()
    return {
        configured = info.configured,
        mode       = info.mode,        -- "jwt" | "key" | nil
        masked     = (info.mode == "jwt" and info.jwt) or
                     (info.mode == "key" and ("key=" .. tostring(info.apiKey))) or nil,
        apiKey     = info.apiKey,      -- masked
        apiSecret  = info.apiSecret,   -- masked
    }
end

function testIpfsAuth(eventName, eventSource)
    MetaplexIpfs.testPinataAuth(function(ok, msg)
        fire(eventName, eventSource, { ok = ok, message = msg })
    end)
end

function ipfsToHttps(uri, gateway)
    return MetaplexIpfs.toHttps(uri, gateway)
end

-- ---
-- uploadAgentRegistration
--   Build the ERC-8004 JSON for an agent + upload to IPFS via Pinata.
--   Result payload:
--     {
--       json     = the JSON string (so caller can echo / debug),
--       cid      = IPFS CID,
--       ipfsUri  = "ipfs://<cid>",
--       gateways = { ipfs_io, pinata, dweb, cloudflare, ... }
--     }
--
--   opts:
--     agent          required — the agent's mint address
--     name, description, image  required — passed to buildAgentRegistrationJson
--     services, supportedTrust, x402Support, registrations, externalLinks  optional
--     pinataName     optional — friendly name shown in Pinata dashboard
-- ---
function uploadAgentRegistration(opts, eventName, eventSource)
    opts = opts or {}
    if not opts.agent then
        fire(eventName, eventSource, nil, "agent (mint) is required")
        return
    end
    if not MetaplexIpfs.hasPinataJwt() then
        fire(eventName, eventSource, nil,
            "Pinata JWT not configured. Call setIpfsPinataJwt(<jwt>) first.")
        return
    end

    local json = buildAgentRegistrationJson(opts.agent, opts)

    MetaplexIpfs.uploadJson(json, {
        name = opts.pinataName or ("agent-" .. tostring(opts.agent):sub(1, 12)),
    }, function(result, err)
        if err then fire(eventName, eventSource, nil, err); return end
        result.json = json
        fire(eventName, eventSource, result)
    end)
end

-- ---
-- publishAgent
--   One-shot: upload the registration JSON to IPFS, then call updateMetadata
--   so the on-chain agent's URI points at the uploaded ipfs:// URI.
--
--   opts: same as uploadAgentRegistration, plus:
--     wallet  required — must be the update authority for the agent
--     gateway optional — which https gateway prefix to write on-chain
--             (default = "ipfs_io"). Set to "ipfs" to write the raw
--             ipfs:// URI instead.
-- ---
function publishAgent(opts, eventName, eventSource)
    opts = opts or {}
    if not opts.wallet then fire(eventName, eventSource, nil, "wallet required"); return end

    uploadAgentRegistration(opts, "_internalUploadDone_" ..
        tostring(getTickCount()) .. "_" .. tostring(math.random(1, 1e9)), resourceRoot)

    -- We can't easily chain the previous fire() because the inner event name
    -- needs to be dynamic. Re-do with explicit handler.
end

-- Robust two-step version — replaces the stub above.
function publishAgent(opts, eventName, eventSource)
    opts = opts or {}
    if not opts.wallet then
        fire(eventName, eventSource, nil, "wallet required")
        return
    end
    if not opts.agent then
        fire(eventName, eventSource, nil, "agent (mint) required")
        return
    end

    local uploadEvt = "onMetaplexAgentPublishUp_" ..
        tostring(getTickCount()) .. "_" .. tostring(math.random(1, 1e9))
    local updateEvt = "onMetaplexAgentPublishUpd_" ..
        tostring(getTickCount()) .. "_" .. tostring(math.random(1, 1e9))
    addEvent(uploadEvt, true)
    addEvent(updateEvt, true)

    local uploaded
    local hUpload, hUpdate

    hUpload = function(result, err)
        removeEventHandler(uploadEvt, resourceRoot, hUpload)
        if err then fire(eventName, eventSource, nil, "Upload failed: " .. tostring(err)); return end
        uploaded = result

        -- Pick which URI to store on chain
        local uriToStore
        local gw = opts.gateway or "ipfs_io"
        if gw == "ipfs" then
            uriToStore = result.ipfsUri
        else
            uriToStore = (result.gateways and result.gateways[gw]) or result.gateways.ipfs_io
        end

        setAgentRegistrationUri({
            wallet = opts.wallet,
            agent  = opts.agent,
            uri    = uriToStore,
        }, updateEvt, resourceRoot)
    end

    hUpdate = function(result, err)
        removeEventHandler(updateEvt, resourceRoot, hUpdate)
        if err then fire(eventName, eventSource, nil, "On-chain update failed: " .. tostring(err)); return end
        fire(eventName, eventSource, {
            agent     = opts.agent,
            cid       = uploaded.cid,
            ipfsUri   = uploaded.ipfsUri,
            httpsUri  = (uploaded.gateways and uploaded.gateways.ipfs_io),
            gateways  = uploaded.gateways,
            json      = uploaded.json,
            signature = result and result.signature,
        })
    end

    addEventHandler(uploadEvt, resourceRoot, hUpload)
    addEventHandler(updateEvt, resourceRoot, hUpdate)

    uploadAgentRegistration(opts, uploadEvt, resourceRoot)
end

-- ---
-- setAgentRegistrationUri
--   Updates the on-chain metadata URI for an agent (post-creation) so it
--   points to the hosted ERC-8004 JSON. Thin wrapper around updateMetadata.
--
--   opts:
--     wallet   base58 (must be the update authority — i.e. the creator)
--     agent    mint address of the agent
--     uri      new registration URI (https://arweave.net/... etc.)
-- ---
function setAgentRegistrationUri(opts, eventName, eventSource)
    opts = opts or {}
    if not opts.wallet or not opts.agent or not opts.uri then
        fire(eventName, eventSource, nil, "wallet, agent, uri are required")
        return
    end
    updateMetadata({
        wallet = opts.wallet,
        mint   = opts.agent,
        uri    = opts.uri,
    }, eventName, eventSource)
end

-- ---
-- createAgentToken
--   Simplified "agent token" — a fungible token where the creator is set
--   to the agent's Asset Signer PDA. This mirrors the Genesis protocol's
--   creator-fee routing pattern WITHOUT implementing the full bonding-curve
--   or `registerIdentityV1` flows (those require MPL Core + Agent Registry,
--   which are far too complex to DIY in pure Lua).
--
--   What this DOES:
--     * Derives the agent's Asset Signer PDA from the provided agent mint
--       (seeds ['mpl-core-execute', agentMint]).
--     * Creates a regular fungible + ATA + mint (atomic, one TX).
--     * Lists the agent's PDA as the sole creator of the token
--       (verified=false — the PDA can't sign our tx, but its presence in
--       the creators list is the convention indexers use to attribute
--       royalties / creator fees).
--     * Keeps `updateAuthority` on `wallet` so the user can still update
--       or burn the token later via our SDK.
--
--   What this does NOT do:
--     * No Metaplex Genesis API call (no hosted bonding curve).
--     * No registerIdentityV1 — the agent must already exist elsewhere.
--     * No `setToken: true` binding — that's Agent Registry only.
--
--   opts  (super-set of createAndMintFungible):
--     agentMint    base58 — REQUIRED. The Core asset address of the agent.
--     (rest: wallet, name, symbol, uri, decimals, initialSupply, bps, ...)
--
--   Result payload: identical to createAndMintFungible, plus `agentSigner`.
-- ---
function createAgentToken(opts, eventName, eventSource)
    opts = opts or {}
    if not opts.agentMint then
        fire(eventName, eventSource, nil, "agentMint is required")
        return
    end

    local agentSigner, bump, derr = TokenMetadataProgram.findAgentAssetSignerPda(opts.agentMint)
    if not agentSigner then
        fire(eventName, eventSource, nil, derr or "Failed to derive agent PDA")
        return
    end

    -- Route the creator attribution to the agent PDA. verified=false because
    -- the PDA isn't a signer on this transaction; on-chain validation only
    -- requires `verified=true` creators to sign.
    opts.creators = opts.creators or {
        { address = agentSigner, share = 100, verified = false },
    }

    -- Wrap the user's event handler so we can inject the agentSigner field.
    local wrapperEvent = "onMetaplexAgentToken_" ..
        tostring(getTickCount()) .. "_" .. tostring(math.random(1, 1e9))
    addEvent(wrapperEvent, true)
    local handler
    handler = function(result, err)
        removeEventHandler(wrapperEvent, resourceRoot, handler)
        if err then fire(eventName, eventSource, nil, err); return end
        result = result or {}
        result.agentSigner = agentSigner
        result.agentSignerBump = bump
        fire(eventName, eventSource, result)
    end
    addEventHandler(wrapperEvent, resourceRoot, handler)

    createAndMintFungible(opts, wrapperEvent, resourceRoot)
end

-- ---
-- fetchMetadata
--   Fetches and decodes the Token Metadata account for a mint.
--   Result payload: { metadata = "pda", data = { name, symbol, uri, ... } }
-- ---
function fetchMetadata(mintAddress, eventName, eventSource)
    local metadataAddr, _, derr = TokenMetadataProgram.findMetadataPda(mintAddress)
    if not metadataAddr then
        fire(eventName, eventSource, nil, derr or "Failed to derive metadata PDA")
        return
    end

    MetaplexRpc.getAccountBytes(metadataAddr, function(account, err)
        if err then fire(eventName, eventSource, nil, err); return end
        if not account or not account.data then
            fire(eventName, eventSource, nil, "Metadata account has no data")
            return
        end
        local parsed, perr = TokenMetadataProgram.decodeMetadataAccount(account.data)
        if not parsed then fire(eventName, eventSource, nil, perr); return end
        fire(eventName, eventSource, { metadata = metadataAddr, data = parsed })
    end)
end

-- ---
-- fetchDigitalAsset
--   Parallel read of metadata + mint accounts. Mimics umi's fetchDigitalAsset.
--   Returns a single combined payload:
--     {
--       mint      = "...",
--       metadata  = { name, symbol, uri, sellerFeeBasisPoints, creators, isMutable, ... },
--       mintInfo  = { supply = "digit string", decimals = u8,
--                     mintAuthority = "..." or nil,
--                     freezeAuthority = "..." or nil }
--     }
-- ---
function fetchDigitalAsset(mintAddress, eventName, eventSource)
    local metadataAddr, _, derr = TokenMetadataProgram.findMetadataPda(mintAddress)
    if not metadataAddr then
        fire(eventName, eventSource, nil, derr or "Failed to derive metadata PDA")
        return
    end

    local mintInfo, metadata
    local done = 0
    local errored = false

    local function finish()
        done = done + 1
        if errored then return end
        if done < 2 then return end
        fire(eventName, eventSource, {
            mint     = mintAddress,
            metadata = metadata,
            mintInfo = mintInfo,
        })
    end

    local function fail(msg)
        if errored then return end
        errored = true
        fire(eventName, eventSource, nil, msg)
    end

    -- 1. Metadata account
    MetaplexRpc.getAccountBytes(metadataAddr, function(account, err)
        if err then fail(err); return end
        if not account or not account.data then fail("Metadata account empty"); return end
        local parsed, perr = TokenMetadataProgram.decodeMetadataAccount(account.data)
        if not parsed then fail(perr); return end
        metadata = parsed
        finish()
    end)

    -- 2. Mint account
    MetaplexRpc.getAccountBytes(mintAddress, function(account, err)
        if err then fail(err); return end
        if not account or not account.data then fail("Mint account empty"); return end
        local parsed, perr = TokenMetadataProgram.decodeMintAccount(account.data)
        if not parsed then fail(perr); return end
        mintInfo = parsed
        finish()
    end)
end

-- ---
-- fetchTokenBalance
--   Returns the balance of a specific (owner, mint) pair, resolved through
--   the associated token account. Uses solana-sdk's getTokenBalance for the
--   actual lookup.
-- ---
function fetchTokenBalance(ownerAddress, mintAddress, eventName, eventSource)
    local ata, _, derr = TokenMetadataProgram.findAssociatedTokenAddress(ownerAddress, mintAddress)
    if not ata then fire(eventName, eventSource, nil, derr or "ATA derivation failed"); return end

    local cbEvent = "onMetaplexBalance_" .. tostring(getTickCount()) .. "_" .. tostring(math.random(1, 1e9))
    addEvent(cbEvent, true)
    local handler
    handler = function(result, err)
        removeEventHandler(cbEvent, resourceRoot, handler)
        if err then fire(eventName, eventSource, nil, err); return end
        fire(eventName, eventSource, {
            ata            = ata,
            amount         = result.amount,
            decimals       = result.decimals,
            uiAmount       = result.uiAmount,
            uiAmountString = result.uiAmountString,
        })
    end
    addEventHandler(cbEvent, resourceRoot, handler)

    sol:getTokenBalance(ata, cbEvent, resourceRoot)
end

-- ---
-- updateMetadata
--   Update on-chain name / symbol / uri / sellerFeeBasisPoints for a mint.
--   Requires `wallet` to be the current update authority AND `isMutable=true`.
--
--   Any field left nil in opts falls back to the existing on-chain value
--   (we fetch + merge before submitting, matching Umi's pattern):
--
--       const asset = await fetchDigitalAsset(umi, mintAddress)
--       await updateV1(umi, { data: { ...asset.metadata, name: '...' } })
--
--   opts:
--     wallet                 base58, update authority + payer (signer)
--     mint                   base58
--     name                   optional string (defaults to existing)
--     symbol                 optional string (defaults to existing)
--     uri                    optional string (defaults to existing)
--     sellerFeeBasisPoints   optional u16   (defaults to existing)
--     creators               optional array (defaults to existing on-chain)
--     newUpdateAuthority     optional base58 — to transfer update auth
--     isMutable              optional bool  — set false to lock metadata
--
--   Result payload: { signature = "..." }
-- ---
function updateMetadata(opts, eventName, eventSource)
    opts = opts or {}
    local ok, err = ensureWallet(opts.wallet)
    if not ok then fire(eventName, eventSource, nil, err); return end
    if not opts.mint then fire(eventName, eventSource, nil, "mint is required"); return end

    -- Step 1: fetch current metadata so we can merge.
    MetaplexRpc.getAccountBytes(
        select(1, TokenMetadataProgram.findMetadataPda(opts.mint)),
        function(account, fetchErr)
            if fetchErr then fire(eventName, eventSource, nil, "Failed to fetch metadata: " .. fetchErr); return end
            if not account or not account.data then
                fire(eventName, eventSource, nil, "Metadata account empty — is the mint real?")
                return
            end
            local current, perr = TokenMetadataProgram.decodeMetadataAccount(account.data)
            if not current then fire(eventName, eventSource, nil, perr); return end

            if current.isMutable == false then
                fire(eventName, eventSource, nil,
                    "Token is immutable (isMutable=false). Metadata cannot be changed.")
                return
            end

            -- Step 2: merge old + new values.
            local merged = {
                name                 = opts.name                 or current.name,
                symbol               = opts.symbol               or current.symbol,
                uri                  = opts.uri                  or current.uri,
                sellerFeeBasisPoints = opts.sellerFeeBasisPoints or current.sellerFeeBasisPoints,
                creators             = opts.creators             or current.creators,
            }

            -- Step 3: build + send updateV1.
            local ix, ixErr = TokenMetadataProgram.updateV1({
                authority          = opts.wallet,
                payer              = opts.wallet,
                mint               = opts.mint,
                data               = merged,
                newUpdateAuthority = opts.newUpdateAuthority,
                isMutable          = opts.isMutable,
                primarySaleHappened = opts.primarySaleHappened,
            })
            if not ix then fire(eventName, eventSource, nil, ixErr); return end

            local cbEvent = "onMetaplexUpdate_" .. tostring(getTickCount()) .. "_" .. tostring(math.random(1, 1e9))
            addEvent(cbEvent, true)
            local handler
            handler = function(result, sendErr)
                removeEventHandler(cbEvent, resourceRoot, handler)
                if sendErr then fire(eventName, eventSource, nil, sendErr); return end
                fire(eventName, eventSource, {
                    mint      = opts.mint,
                    signature = result and result.signature,
                    updated   = {
                        name = merged.name, symbol = merged.symbol, uri = merged.uri,
                        sellerFeeBasisPoints = merged.sellerFeeBasisPoints,
                    },
                })
            end
            addEventHandler(cbEvent, resourceRoot, handler)

            sol:sendCustomTransaction(opts.wallet, { ix }, { opts.wallet }, cbEvent, resourceRoot)
        end
    )
end

-- ---
-- burnTokens
--   Destroys tokens from the caller's ATA. Irreversible.
--
--   opts:
--     wallet        base58, owner of the tokens (signer)
--     mint          base58
--     amount        raw u64, number OR digit string (raw, factor in decimals)
--     initialSupply human units (e.g. 100 = "100 tokens"). Auto-multiplied
--                   by 10^decimals. Takes priority over `amount` when both set.
--     decimals      required when using initialSupply. Defaults to 9.
--     tokenAccount  optional base58 to burn from (defaults to wallet's ATA)
--
--   Result payload: { signature = "...", burned = { amount_raw, tokenAccount } }
-- ---
function burnTokens(opts, eventName, eventSource)
    opts = opts or {}
    local ok, err = ensureWallet(opts.wallet)
    if not ok then fire(eventName, eventSource, nil, err); return end
    if not opts.mint or type(opts.mint) ~= "string" or #opts.mint < 32 then
        fire(eventName, eventSource, nil,
            "mint must be a base58 address (got " .. type(opts.mint) .. ")")
        return
    end

    -- Human → raw conversion. Accepts either `initialSupply` (human) or
    -- `amount` (raw). Explicit string type check so bad inputs give a clear
    -- error instead of a Lua-level "attempt to index nil" further down.
    local amount = opts.amount
    if opts.initialSupply ~= nil then
        local supply = opts.initialSupply
        if type(supply) ~= "string" and type(supply) ~= "number" then
            fire(eventName, eventSource, nil,
                "initialSupply must be string or number, got " .. type(supply))
            return
        end
        local decimals = opts.decimals == nil and 9 or opts.decimals
        local raw, hErr = MetaplexBorsh.humanToRawString(supply, decimals)
        if not raw then
            fire(eventName, eventSource, nil, "Invalid initialSupply: " .. tostring(hErr))
            return
        end
        amount = raw
    end
    if amount == nil or amount == 0 or amount == "0" or amount == "" then
        fire(eventName, eventSource, nil,
            "amount (or initialSupply) must be > 0, got " .. tostring(amount))
        return
    end

    local tokenAccount = opts.tokenAccount
    if not tokenAccount then
        local ataOk, ata = pcall(function()
            return select(1, TokenMetadataProgram.findAssociatedTokenAddress(
                opts.wallet, opts.mint))
        end)
        if not ataOk or not ata then
            fire(eventName, eventSource, nil,
                "ATA derivation failed: " .. tostring(ata or "invalid mint/wallet"))
            return
        end
        tokenAccount = ata
    end

    local ixOk, ix = pcall(TokenMetadataProgram.burnToken, {
        tokenAccount = tokenAccount,
        mint         = opts.mint,
        authority    = opts.wallet,
        amount       = amount,
    })
    if not ixOk or not ix then
        fire(eventName, eventSource, nil,
            "Failed to build burn instruction: " .. tostring(ix))
        return
    end

    local cbEvent = "onMetaplexBurn_" .. tostring(getTickCount()) .. "_" .. tostring(math.random(1, 1e9))
    addEvent(cbEvent, true)
    local handler
    handler = function(result, sendErr)
        removeEventHandler(cbEvent, resourceRoot, handler)
        if sendErr then fire(eventName, eventSource, nil, sendErr); return end
        fire(eventName, eventSource, {
            signature = result and result.signature,
            burned    = { amount = tostring(amount), tokenAccount = tokenAccount },
        })
    end
    addEventHandler(cbEvent, resourceRoot, handler)

    sol:sendCustomTransaction(opts.wallet, { ix }, { opts.wallet }, cbEvent, resourceRoot)
end
