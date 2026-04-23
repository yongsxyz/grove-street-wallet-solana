-- https://github.com/yongsxyz
--[[
    Metaplex SDK - Instruction builders.

    Programs covered:
        TokenMetadataProgram (metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s)
            - createV1   (used by createFungible / createNft / createPNft)
            - mintV1     (used to mint NFT / pNFT supply via Token Metadata)
        TokenProgramExtras
            - mintTo     (SPL Token instruction #7, plain fungible mint)
        AssociatedTokenProgram
            - createIdempotent (already exists in solana-sdk, replicated for self-containment)

    Each builder returns an instruction table compatible with
    sendCustomTransaction from solana-sdk:
        { programId = "...", keys = { {pubkey, isSigner, isWritable}, ... }, data = {...} }
]]

local floor = math.floor

-- Program IDs
TokenMetadataProgram = {}
TokenMetadataProgram.PROGRAM_ID       = "metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s"
TokenMetadataProgram.SYSTEM_PROGRAM_ID = "11111111111111111111111111111111"
TokenMetadataProgram.SYSVAR_INSTRUCTIONS = "Sysvar1nstructions1111111111111111111111111"
TokenMetadataProgram.SPL_TOKEN_PROGRAM_ID = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
TokenMetadataProgram.SPL_ATA_PROGRAM_ID   = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"
-- MPL Core program (used to derive an agent's Asset Signer PDA)
TokenMetadataProgram.MPL_CORE_PROGRAM_ID  = "CoREENxT6tW1HoK8ypY1SxRMZTcVPm7R94rH4PZNhX7d"

-- Token standards (matches enum order in mpl-token-metadata IDL)
TokenMetadataProgram.TOKEN_STANDARD = {
    NonFungible                    = 0,
    FungibleAsset                  = 1,
    Fungible                       = 2,
    NonFungibleEdition             = 3,
    ProgrammableNonFungible        = 4,
    ProgrammableNonFungibleEdition = 5,
}

-- ---
-- PDA helpers
-- ---

-- Metadata PDA seeds: ["metadata", programId, mint]
function TokenMetadataProgram.findMetadataPda(mintAddress)
    local programIdBytes = MetaplexBase58.decodePubkey(TokenMetadataProgram.PROGRAM_ID)
    local mintBytes = MetaplexBase58.decodePubkey(mintAddress)
    if not mintBytes then return nil, nil, "Invalid mint address" end

    local seeds = {
        "metadata",
        programIdBytes,
        mintBytes,
    }
    local addrBytes, bump = MetaplexPDA.findProgramAddressBytes(seeds, programIdBytes)
    if not addrBytes then return nil, nil, "PDA derivation failed" end

    return MetaplexBase58.encode(addrBytes), bump
end

-- Master Edition PDA seeds: ["metadata", programId, mint, "edition"]
function TokenMetadataProgram.findMasterEditionPda(mintAddress)
    local programIdBytes = MetaplexBase58.decodePubkey(TokenMetadataProgram.PROGRAM_ID)
    local mintBytes = MetaplexBase58.decodePubkey(mintAddress)
    if not mintBytes then return nil, nil, "Invalid mint address" end

    local seeds = {
        "metadata",
        programIdBytes,
        mintBytes,
        "edition",
    }
    local addrBytes, bump = MetaplexPDA.findProgramAddressBytes(seeds, programIdBytes)
    if not addrBytes then return nil, nil, "PDA derivation failed" end

    return MetaplexBase58.encode(addrBytes), bump
end

-- Associated Token Account PDA seeds: [walletAddress, tokenProgramId, mintAddress]
function TokenMetadataProgram.findAssociatedTokenAddress(walletAddress, mintAddress, tokenProgramId)
    tokenProgramId = tokenProgramId or TokenMetadataProgram.SPL_TOKEN_PROGRAM_ID

    local ataProgramBytes = MetaplexBase58.decodePubkey(TokenMetadataProgram.SPL_ATA_PROGRAM_ID)
    local walletBytes     = MetaplexBase58.decodePubkey(walletAddress)
    local tokenProgBytes  = MetaplexBase58.decodePubkey(tokenProgramId)
    local mintBytes       = MetaplexBase58.decodePubkey(mintAddress)
    if not walletBytes or not tokenProgBytes or not mintBytes then
        return nil, nil, "Invalid address arg"
    end

    local seeds = { walletBytes, tokenProgBytes, mintBytes }
    local addrBytes, bump = MetaplexPDA.findProgramAddressBytes(seeds, ataProgramBytes)
    if not addrBytes then return nil, nil, "ATA derivation failed" end

    return MetaplexBase58.encode(addrBytes), bump
end

-- MPL Core Asset Signer PDA seeds: ["mpl-core-execute", agentMint]
-- Used by the Genesis protocol to route creator fees to the agent's built-in
-- wallet. Deterministic — anyone can derive it from an agent mint address.
function TokenMetadataProgram.findAgentAssetSignerPda(agentMintAddress)
    local mplCoreBytes = MetaplexBase58.decodePubkey(TokenMetadataProgram.MPL_CORE_PROGRAM_ID)
    local mintBytes    = MetaplexBase58.decodePubkey(agentMintAddress)
    if not mintBytes then return nil, nil, "Invalid agent mint address" end

    local seeds = { "mpl-core-execute", mintBytes }
    local addrBytes, bump = MetaplexPDA.findProgramAddressBytes(seeds, mplCoreBytes)
    if not addrBytes then return nil, nil, "Asset signer PDA derivation failed" end

    return MetaplexBase58.encode(addrBytes), bump
end

-- ---
-- CreateV1 instruction (Token Metadata program)
-- Variant 42, sub-discriminator 0
--
-- args (table):
--   mint              base58 string (signer + writable)
--   authority         base58 string (signer)
--   payer             base58 string (signer + writable)
--   updateAuthority   base58 string (defaults to authority)
--   name              string (max 32 chars)
--   symbol            string (max 10 chars)
--   uri               string (max 200 chars)
--   sellerFeeBasisPoints  integer 0..10000  (e.g. 550 = 5.5%)
--   tokenStandard     integer (use TokenMetadataProgram.TOKEN_STANDARD.Fungible etc.)
--   decimals          integer or nil  (passed as option<u8>; nil = none)
--   isMutable         bool, default true
--   primarySaleHappened  bool, default false
--   creators          array of {address=string, share=u8, verified=bool} or nil for default
--                     (nil means: single creator = authority, share=100, verified=true)
--   collection        nil (none) or { verified=bool, key=base58 }
--   uses              nil (none) or { useMethod=u8, remaining=u64, total=u64 }
--   collectionDetails nil (none) or "V2"
--   ruleSet           nil (none) or base58
--   printSupply       nil (none) or { kind="Zero"|"Limited"|"Unlimited", limit=u64 }
-- ---
function TokenMetadataProgram.createV1(args)
    assert(args.mint, "createV1: mint is required")
    assert(args.authority, "createV1: authority is required")
    assert(args.payer, "createV1: payer is required")
    assert(args.name, "createV1: name is required")
    assert(args.uri, "createV1: uri is required")
    assert(args.tokenStandard, "createV1: tokenStandard is required")
    assert(args.sellerFeeBasisPoints ~= nil, "createV1: sellerFeeBasisPoints is required")

    local updateAuthority = args.updateAuthority or args.authority
    local symbol = args.symbol or ""
    local isMutable = args.isMutable
    if isMutable == nil then isMutable = true end
    local primarySaleHappened = args.primarySaleHappened == true

    local TS = TokenMetadataProgram.TOKEN_STANDARD
    local isNonFungible = (
        args.tokenStandard == TS.NonFungible or
        args.tokenStandard == TS.NonFungibleEdition or
        args.tokenStandard == TS.ProgrammableNonFungible or
        args.tokenStandard == TS.ProgrammableNonFungibleEdition
    )

    -- Default creators: authority with share 100, verified true (authority signs)
    local creators = args.creators
    if creators == nil then
        creators = {
            { address = args.authority, share = 100, verified = true },
        }
    end

    -- Resolve PDA accounts
    local metadataAddr = select(1, TokenMetadataProgram.findMetadataPda(args.mint))
    if not metadataAddr then return nil, "Failed to derive metadata PDA" end

    local masterEditionAddr = nil
    if isNonFungible then
        masterEditionAddr = select(1, TokenMetadataProgram.findMasterEditionPda(args.mint))
        if not masterEditionAddr then return nil, "Failed to derive master edition PDA" end
    end

    -- Optional accounts that are absent in fungible flow get filled with the
    -- Token Metadata program ID (matches umi's "programId" omitted strategy).
    local programIdPlaceholder = TokenMetadataProgram.PROGRAM_ID

    -- Build instruction data
    local w = MetaplexBorsh.newWriter()
    MetaplexBorsh.writeU8(w, 42)                                  -- discriminator
    MetaplexBorsh.writeU8(w, 0)                                   -- createV1Discriminator
    MetaplexBorsh.writeString(w, args.name)
    MetaplexBorsh.writeString(w, symbol)
    MetaplexBorsh.writeString(w, args.uri)
    MetaplexBorsh.writeU16(w, args.sellerFeeBasisPoints)

    -- creators: option<vec<Creator>>
    MetaplexBorsh.writeOption(w, creators, function(ww, list)
        MetaplexBorsh.writeVec(ww, list, function(www, c)
            MetaplexBorsh.writePubkey(www, c.address)
            MetaplexBorsh.writeBool(www, c.verified == true)
            MetaplexBorsh.writeU8(www, c.share or 0)
        end)
    end)

    MetaplexBorsh.writeBool(w, primarySaleHappened)
    MetaplexBorsh.writeBool(w, isMutable)
    MetaplexBorsh.writeU8(w, args.tokenStandard)                  -- TokenStandard enum

    -- collection: option<Collection { verified: bool, key: pubkey }>
    MetaplexBorsh.writeOption(w, args.collection, function(ww, col)
        MetaplexBorsh.writeBool(ww, col.verified == true)
        MetaplexBorsh.writePubkey(ww, col.key)
    end)

    -- uses: option<Uses { useMethod: u8, remaining: u64, total: u64 }>
    MetaplexBorsh.writeOption(w, args.uses, function(ww, u)
        MetaplexBorsh.writeU8(ww, u.useMethod or 0)
        MetaplexBorsh.writeU64(ww, u.remaining or 0)
        MetaplexBorsh.writeU64(ww, u.total or 0)
    end)

    -- collectionDetails: option<CollectionDetails>
    -- only "V2" variant supported (with 8 zero padding bytes)
    MetaplexBorsh.writeOption(w, args.collectionDetails, function(ww, cd)
        if cd == "V2" or (type(cd) == "table" and cd.kind == "V2") then
            MetaplexBorsh.writeU8(ww, 1) -- V2 enum tag
            for _ = 1, 8 do MetaplexBorsh.writeU8(ww, 0) end
        else
            error("Unsupported collectionDetails variant")
        end
    end)

    -- ruleSet: option<pubkey>
    MetaplexBorsh.writeOption(w, args.ruleSet, function(ww, rs)
        MetaplexBorsh.writePubkey(ww, rs)
    end)

    -- decimals: option<u8>
    MetaplexBorsh.writeOption(w, args.decimals, function(ww, d)
        MetaplexBorsh.writeU8(ww, d)
    end)

    -- printSupply: option<PrintSupply data enum>
    MetaplexBorsh.writeOption(w, args.printSupply, function(ww, ps)
        local kind = (type(ps) == "string") and ps or ps.kind
        if kind == "Zero" then
            MetaplexBorsh.writeU8(ww, 0)
        elseif kind == "Limited" then
            MetaplexBorsh.writeU8(ww, 1)
            MetaplexBorsh.writeU64(ww, ps.limit or 0)
        elseif kind == "Unlimited" then
            MetaplexBorsh.writeU8(ww, 2)
        else
            error("Unknown PrintSupply kind: " .. tostring(kind))
        end
    end)

    local data = MetaplexBorsh.toBytes(w)

    -- Account order matches createV1.ts (accounts sorted by index)
    local keys = {
        { pubkey = metadataAddr,                                  isSigner = false, isWritable = true },
        { pubkey = masterEditionAddr or programIdPlaceholder,     isSigner = false, isWritable = masterEditionAddr ~= nil },
        { pubkey = args.mint,                                     isSigner = true,  isWritable = true },
        { pubkey = args.authority,                                isSigner = true,  isWritable = false },
        { pubkey = args.payer,                                    isSigner = true,  isWritable = true },
        { pubkey = updateAuthority,                               isSigner = false, isWritable = false },
        { pubkey = TokenMetadataProgram.SYSTEM_PROGRAM_ID,        isSigner = false, isWritable = false },
        { pubkey = TokenMetadataProgram.SYSVAR_INSTRUCTIONS,      isSigner = false, isWritable = false },
        { pubkey = TokenMetadataProgram.SPL_TOKEN_PROGRAM_ID,     isSigner = false, isWritable = false },
    }

    return {
        programId = TokenMetadataProgram.PROGRAM_ID,
        keys = keys,
        data = data,
    }, metadataAddr
end

-- ---
-- SPL Token MintTo (instruction #7) — used to mint plain Fungible supply.
-- args:
--   mint            base58 string (writable)
--   token           base58 string (writable, destination ATA)
--   mintAuthority   base58 string (signer)
--   amount          u64 (raw). Pass a Lua number for amounts <= 2^53,
--                   or a decimal STRING (e.g. "1000000000000000000") for
--                   anything bigger up to the SPL u64 ceiling.
-- ---
function TokenMetadataProgram.mintTo(args)
    assert(args.mint and args.token and args.mintAuthority and args.amount,
        "mintTo: mint, token, mintAuthority, amount are required")

    local w = MetaplexBorsh.newWriter()
    MetaplexBorsh.writeU8(w, 7)               -- discriminator
    MetaplexBorsh.writeU64(w, args.amount)    -- amount (number OR string)

    return {
        programId = TokenMetadataProgram.SPL_TOKEN_PROGRAM_ID,
        keys = {
            { pubkey = args.mint,          isSigner = false, isWritable = true  },
            { pubkey = args.token,         isSigner = false, isWritable = true  },
            { pubkey = args.mintAuthority, isSigner = true,  isWritable = false },
        },
        data = MetaplexBorsh.toBytes(w),
    }
end

-- ---
-- UpdateV1 instruction (Token Metadata program).
-- Discriminator 50, sub-discriminator 0.
--
-- This is the "modern" update instruction. It ALWAYS requires a `data`
-- payload when you want to change name/symbol/uri/sellerFeeBasisPoints.
-- If you pass nil for `data`, the on-chain metadata is left untouched —
-- you could still be updating `newUpdateAuthority`, `primarySaleHappened`,
-- etc., but for our fungible use-case those are rarely needed.
--
-- args (table):
--   authority     base58 (signer, current update authority)
--   payer         optional, defaults to authority
--   mint          base58
--   token         optional base58 token account — only required for
--                 pNFT flows, pass nil for plain fungibles
--   data          nil OR table:
--                   {
--                     name, symbol, uri,
--                     sellerFeeBasisPoints,
--                     creators (table or nil),  -- nil = none
--                   }
--   newUpdateAuthority   optional base58 — pass to transfer update auth
--   primarySaleHappened  optional bool
--   isMutable            optional bool
-- ---
function TokenMetadataProgram.updateV1(args)
    assert(args.mint,      "updateV1: mint is required")
    assert(args.authority, "updateV1: authority is required")

    local payer = args.payer or args.authority

    local metadataAddr = select(1, TokenMetadataProgram.findMetadataPda(args.mint))
    if not metadataAddr then return nil, "Failed to derive metadata PDA" end

    local programPlaceholder = TokenMetadataProgram.PROGRAM_ID

    -- Build instruction data
    local w = MetaplexBorsh.newWriter()
    MetaplexBorsh.writeU8(w, 50)  -- discriminator
    MetaplexBorsh.writeU8(w, 0)   -- updateV1 sub-discriminator

    -- newUpdateAuthority: option<pubkey>
    MetaplexBorsh.writeOption(w, args.newUpdateAuthority, function(ww, pk)
        MetaplexBorsh.writePubkey(ww, pk)
    end)

    -- data: option<Data>
    MetaplexBorsh.writeOption(w, args.data, function(ww, d)
        MetaplexBorsh.writeString(ww, d.name or "")
        MetaplexBorsh.writeString(ww, d.symbol or "")
        MetaplexBorsh.writeString(ww, d.uri or "")
        MetaplexBorsh.writeU16(ww, d.sellerFeeBasisPoints or 0)
        MetaplexBorsh.writeOption(ww, d.creators, function(www, list)
            MetaplexBorsh.writeVec(www, list, function(wwww, c)
                MetaplexBorsh.writePubkey(wwww, c.address)
                MetaplexBorsh.writeBool(wwww, c.verified == true)
                MetaplexBorsh.writeU8(wwww, c.share or 0)
            end)
        end)
    end)

    -- primarySaleHappened: option<bool>
    MetaplexBorsh.writeOption(w, args.primarySaleHappened, function(ww, v)
        MetaplexBorsh.writeBool(ww, v)
    end)

    -- isMutable: option<bool>
    MetaplexBorsh.writeOption(w, args.isMutable, function(ww, v)
        MetaplexBorsh.writeBool(ww, v)
    end)

    -- collection, collectionDetails, uses, ruleSet: all "Toggle" data enums.
    -- "None" variant = tag 0 (no payload). We always write None.
    MetaplexBorsh.writeU8(w, 0)  -- collection None
    MetaplexBorsh.writeU8(w, 0)  -- collectionDetails None
    MetaplexBorsh.writeU8(w, 0)  -- uses None
    MetaplexBorsh.writeU8(w, 0)  -- ruleSet None

    -- authorizationData: option<AuthorizationData> — always none for fungible.
    MetaplexBorsh.writeU8(w, 0)

    local data = MetaplexBorsh.toBytes(w)

    -- Account order from updateV1.ts (indices 0..10)
    local keys = {
        { pubkey = args.authority,                                isSigner = true,  isWritable = false },  -- 0
        { pubkey = programPlaceholder,                            isSigner = false, isWritable = false },  -- 1 delegateRecord (unused)
        { pubkey = args.token or programPlaceholder,              isSigner = false, isWritable = false },  -- 2 token (unused for fungible)
        { pubkey = args.mint,                                     isSigner = false, isWritable = false },  -- 3 mint
        { pubkey = metadataAddr,                                  isSigner = false, isWritable = true  },  -- 4 metadata
        { pubkey = programPlaceholder,                            isSigner = false, isWritable = false },  -- 5 edition (unused for fungible)
        { pubkey = payer,                                         isSigner = true,  isWritable = true  },  -- 6 payer
        { pubkey = TokenMetadataProgram.SYSTEM_PROGRAM_ID,        isSigner = false, isWritable = false },  -- 7 systemProgram
        { pubkey = TokenMetadataProgram.SYSVAR_INSTRUCTIONS,      isSigner = false, isWritable = false },  -- 8 sysvarInstructions
        { pubkey = programPlaceholder,                            isSigner = false, isWritable = false },  -- 9 authorizationRulesProgram (unused)
        { pubkey = programPlaceholder,                            isSigner = false, isWritable = false },  -- 10 authorizationRules (unused)
    }

    return {
        programId = TokenMetadataProgram.PROGRAM_ID,
        keys = keys,
        data = data,
    }, metadataAddr
end

-- ---
-- SPL Token Burn (instruction #8). Destroys tokens in `tokenAccount`.
-- args:
--   tokenAccount  base58 (writable, source ATA)
--   mint          base58 (writable)
--   authority     base58 (signer, owner of tokenAccount)
--   amount        raw u64 (Lua number or digit string)
-- ---
function TokenMetadataProgram.burnToken(args)
    assert(args.tokenAccount and args.mint and args.authority and args.amount,
        "burnToken: tokenAccount, mint, authority, amount are required")

    local w = MetaplexBorsh.newWriter()
    MetaplexBorsh.writeU8(w, 8)                -- discriminator
    MetaplexBorsh.writeU64(w, args.amount)     -- u64 amount

    return {
        programId = TokenMetadataProgram.SPL_TOKEN_PROGRAM_ID,
        keys = {
            { pubkey = args.tokenAccount, isSigner = false, isWritable = true  },
            { pubkey = args.mint,         isSigner = false, isWritable = true  },
            { pubkey = args.authority,    isSigner = true,  isWritable = false },
        },
        data = MetaplexBorsh.toBytes(w),
    }
end

-- ---
-- Metadata account decoder.
-- Parses the on-chain MetadataV1 account bytes produced by Token Metadata.
-- Returns a table with parsed fields, OR nil, err if decoding fails.
-- Extra fields present after the hard-required ones are tolerated (future
-- program versions may append fields; we stop when we run out of bytes).
-- ---
function TokenMetadataProgram.decodeMetadataAccount(bytes)
    if not bytes or #bytes < 1 + 32 + 32 then
        return nil, "metadata: account too small"
    end
    local r = MetaplexBorsh.newReader(bytes)
    local ok, result = pcall(function()
        local out = {}
        out.key             = r:readU8()          -- 4 = MetadataV1
        out.updateAuthority = r:readPubkey()
        out.mint            = r:readPubkey()
        out.name            = r:readString(true)
        out.symbol          = r:readString(true)
        out.uri             = r:readString(true)
        out.sellerFeeBasisPoints = r:readU16()

        out.creators = r:readOption(function(rr)
            return rr:readVec(function(rrr)
                return {
                    address  = rrr:readPubkey(),
                    verified = rrr:readBool(),
                    share    = rrr:readU8(),
                }
            end)
        end)

        out.primarySaleHappened = r:readBool()
        out.isMutable           = r:readBool()
        out.editionNonce   = r:readOption(function(rr) return rr:readU8() end)
        out.tokenStandard  = r:readOption(function(rr) return rr:readU8() end)
        -- Skip the rest (collection/uses/collectionDetails/programmableConfig).
        -- Not needed for a fungible-token display.
        return out
    end)
    if not ok then
        return nil, "metadata: decode error (" .. tostring(result) .. ")"
    end
    return result
end

-- ---
-- SPL Mint account decoder (instruction layout defined by the SPL Token program).
-- 82 bytes:
--   0..36   : mintAuthority option<pubkey> (4 tag + 32)
--   36..44  : supply u64
--   44      : decimals u8
--   45      : isInitialized u8
--   46..82  : freezeAuthority option<pubkey> (4 tag + 32)
-- Note: unlike Borsh, SPL uses a 4-byte (COption) tag for the optional fields.
-- ---
function TokenMetadataProgram.decodeMintAccount(bytes)
    if not bytes or #bytes < 82 then
        return nil, "mint: account too small (" .. tostring(bytes and #bytes or 0) .. " bytes)"
    end

    local function tag4(r)
        -- COption: 4-byte little-endian tag, value != 0 means Some.
        local t = r:readU32()
        return t ~= 0
    end

    local r = MetaplexBorsh.newReader(bytes)
    local ok, result = pcall(function()
        local out = {}
        if tag4(r) then
            out.mintAuthority = r:readPubkey()
        else
            out.mintAuthority = nil
            r:readBytes(32)   -- skip 32 bytes of padding
        end
        out.supply        = r:readU64String()
        out.decimals      = r:readU8()
        out.isInitialized = r:readBool()
        if tag4(r) then
            out.freezeAuthority = r:readPubkey()
        else
            out.freezeAuthority = nil
            r:readBytes(32)
        end
        return out
    end)
    if not ok then
        return nil, "mint: decode error (" .. tostring(result) .. ")"
    end
    return result
end

-- ---
-- SPL Associated Token Account - CreateIdempotent (instruction #1).
-- Always succeeds whether or not the ATA already exists.
-- args:
--   payer        base58 (signer + writable)
--   ata          base58 (writable, ATA address)
--   walletOwner  base58
--   mint         base58
--   tokenProgram base58 (defaults to SPL Token)
-- ---
function TokenMetadataProgram.createIdempotentAta(args)
    local tokenProgram = args.tokenProgram or TokenMetadataProgram.SPL_TOKEN_PROGRAM_ID
    return {
        programId = TokenMetadataProgram.SPL_ATA_PROGRAM_ID,
        keys = {
            { pubkey = args.payer,        isSigner = true,  isWritable = true  },
            { pubkey = args.ata,          isSigner = false, isWritable = true  },
            { pubkey = args.walletOwner,  isSigner = false, isWritable = false },
            { pubkey = args.mint,         isSigner = false, isWritable = false },
            { pubkey = TokenMetadataProgram.SYSTEM_PROGRAM_ID, isSigner = false, isWritable = false },
            { pubkey = tokenProgram,                            isSigner = false, isWritable = false },
        },
        data = {1}, -- 1 = CreateIdempotent
    }
end
