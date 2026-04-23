-- https://github.com/yongsxyz
--[[
    Metaplex SDK - MPL Core + MPL Agent Identity instruction builders.

    Byte layouts reverse-engineered from the generated Kinobi TS client at:
      * contohmetaplex/mpl-core-main/clients/js/src/generated/instructions/
      * contohmetaplex/mpl-agent-main/clients/js/src/generated/identity/

    This is what makes an agent appear on metaplex.com/agents — the indexer
    there scans for accounts owned by MPL Core that have the AgentIdentity
    plugin attached (done here via `registerIdentityV1`).

    Covers:
      MPL Core program (CoREENxT6tW1HoK8ypY1SxRMZTcVPm7R94rH4PZNhX7d):
        * createCollectionV2  (discriminator 21)
        * createV2            (discriminator 20)
      MPL Agent Identity (1DREGFgysWYxLnRnKQnwrxnJQeSMk2HmGaC6whw2B2p):
        * registerIdentityV1  (discriminator 0 + 7-byte padding)
      PDA:
        * Agent Identity PDA = seeds ["agent_identity", asset]
]]

MplCoreProgram = {}
MplCoreProgram.PROGRAM_ID = "CoREENxT6tW1HoK8ypY1SxRMZTcVPm7R94rH4PZNhX7d"

MplAgentIdentityProgram = {}
MplAgentIdentityProgram.PROGRAM_ID = "1DREGFgysWYxLnRnKQnwrxnJQeSMk2HmGaC6whw2B2p"

local SYSTEM_PROGRAM_ID = "11111111111111111111111111111111"

-- ---
-- MPL Core :: createCollectionV2  (discriminator = 21)
-- Data layout:
--   u8  discriminator = 21
--   string  name
--   string  uri
--   option<vec<PluginAuthorityPair>>  plugins          (default = none — tag 0)
--   option<vec<BaseExternalPluginAdapterInitInfo>>  ePluginAdapters (default = Some([]))
--
-- Accounts (in index order):
--   0  collection       signer + writable
--   1  updateAuthority  readonly (optional)
--   2  payer            signer + writable
--   3  systemProgram    readonly
-- ---
function MplCoreProgram.createCollectionV2(args)
    assert(args.collection and args.payer, "createCollectionV2: collection + payer required")

    local w = MetaplexBorsh.newWriter()
    MetaplexBorsh.writeU8(w, 21)
    MetaplexBorsh.writeString(w, args.name or "")
    MetaplexBorsh.writeString(w, args.uri or "")
    -- plugins: none
    MetaplexBorsh.writeU8(w, 0)
    -- externalPluginAdapters: Some([])
    MetaplexBorsh.writeU8(w, 1)
    MetaplexBorsh.writeU32(w, 0)

    local keys = {
        { pubkey = args.collection,      isSigner = true,  isWritable = true  },
        { pubkey = args.updateAuthority or MplCoreProgram.PROGRAM_ID,
          isSigner = false, isWritable = false },  -- placeholder when unused
        { pubkey = args.payer,           isSigner = true,  isWritable = true  },
        { pubkey = SYSTEM_PROGRAM_ID,    isSigner = false, isWritable = false },
    }

    return {
        programId = MplCoreProgram.PROGRAM_ID,
        keys      = keys,
        data      = MetaplexBorsh.toBytes(w),
    }
end

-- ---
-- MPL Core :: createV2  (discriminator = 20)
-- Data layout:
--   u8  discriminator = 20
--   u8  dataState = 0 (AccountState)
--   string  name
--   string  uri
--   option<vec<PluginAuthorityPair>>  plugins           (default = Some([]))
--   option<vec<BaseExternalPluginAdapterInitInfo>>  ePluginAdapters (default = Some([]))
--
-- Accounts (in index order):
--   0  asset            signer + writable (new keypair)
--   1  collection       writable (optional)
--   2  authority        signer (optional — required when collection is set)
--   3  payer            signer + writable
--   4  owner            readonly (optional; defaults to authority on-chain)
--   5  updateAuthority  readonly (optional)
--   6  systemProgram    readonly
--   7  logWrapper       readonly (optional — SPL Noop)
-- ---
function MplCoreProgram.createV2(args)
    assert(args.asset and args.payer, "createV2: asset + payer required")

    local w = MetaplexBorsh.newWriter()
    MetaplexBorsh.writeU8(w, 20)
    MetaplexBorsh.writeU8(w, args.dataState or 0)
    MetaplexBorsh.writeString(w, args.name or "")
    MetaplexBorsh.writeString(w, args.uri or "")
    -- plugins: Some([])
    MetaplexBorsh.writeU8(w, 1)
    MetaplexBorsh.writeU32(w, 0)
    -- externalPluginAdapters: Some([])
    MetaplexBorsh.writeU8(w, 1)
    MetaplexBorsh.writeU32(w, 0)

    local placeholder = MplCoreProgram.PROGRAM_ID

    local keys = {
        { pubkey = args.asset,                              isSigner = true,  isWritable = true  },
        { pubkey = args.collection or placeholder,          isSigner = false, isWritable = args.collection ~= nil },
        { pubkey = args.authority or placeholder,           isSigner = args.authority ~= nil, isWritable = false },
        { pubkey = args.payer,                              isSigner = true,  isWritable = true  },
        { pubkey = args.owner or placeholder,               isSigner = false, isWritable = false },
        { pubkey = args.updateAuthority or placeholder,     isSigner = false, isWritable = false },
        { pubkey = SYSTEM_PROGRAM_ID,                       isSigner = false, isWritable = false },
        { pubkey = args.logWrapper or placeholder,          isSigner = false, isWritable = false },
    }

    return {
        programId = MplCoreProgram.PROGRAM_ID,
        keys      = keys,
        data      = MetaplexBorsh.toBytes(w),
    }
end

-- ---
-- Agent Identity V2 PDA.
-- Seeds = ["agent_identity" (raw bytes, no length prefix), asset (32 bytes)]
-- Program = MplAgentIdentityProgram.PROGRAM_ID
-- ---
function MplAgentIdentityProgram.findAgentIdentityPda(assetAddress)
    local programIdBytes = MetaplexBase58.decodePubkey(MplAgentIdentityProgram.PROGRAM_ID)
    local assetBytes     = MetaplexBase58.decodePubkey(assetAddress)
    if not assetBytes then return nil, nil, "Invalid asset address" end

    local seeds = { "agent_identity", assetBytes }
    local addrBytes, bump = MetaplexPDA.findProgramAddressBytes(seeds, programIdBytes)
    if not addrBytes then return nil, nil, "Agent identity PDA derivation failed" end

    return MetaplexBase58.encode(addrBytes), bump
end

-- ---
-- MPL Agent Identity :: registerIdentityV1  (discriminator = 0)
-- Data layout:
--   u8  discriminator = 0
--   [u8; 7]  padding = 0,0,0,0,0,0,0  (8-byte alignment)
--   string  agentRegistrationUri
--
-- Accounts (in index order):
--   0  agentIdentity    writable (PDA)
--   1  asset            writable
--   2  collection       writable (optional)
--   3  payer            signer + writable
--   4  authority        signer (optional; must be asset authority when set)
--   5  mplCoreProgram   readonly
--   6  systemProgram    readonly
-- ---
function MplAgentIdentityProgram.registerIdentityV1(args)
    assert(args.asset and args.payer and args.agentRegistrationUri,
        "registerIdentityV1: asset + payer + agentRegistrationUri required")

    local agentIdentityPda = args.agentIdentity
    if not agentIdentityPda then
        agentIdentityPda = select(1, MplAgentIdentityProgram.findAgentIdentityPda(args.asset))
        if not agentIdentityPda then
            return nil, "Failed to derive agent identity PDA"
        end
    end

    local w = MetaplexBorsh.newWriter()
    MetaplexBorsh.writeU8(w, 0)
    for _ = 1, 7 do MetaplexBorsh.writeU8(w, 0) end
    MetaplexBorsh.writeString(w, args.agentRegistrationUri)

    local placeholder = MplAgentIdentityProgram.PROGRAM_ID

    local keys = {
        { pubkey = agentIdentityPda,                     isSigner = false, isWritable = true  },
        { pubkey = args.asset,                           isSigner = false, isWritable = true  },
        { pubkey = args.collection or placeholder,       isSigner = false, isWritable = args.collection ~= nil },
        { pubkey = args.payer,                           isSigner = true,  isWritable = true  },
        { pubkey = args.authority or placeholder,        isSigner = args.authority ~= nil, isWritable = false },
        { pubkey = MplCoreProgram.PROGRAM_ID,            isSigner = false, isWritable = false },
        { pubkey = SYSTEM_PROGRAM_ID,                    isSigner = false, isWritable = false },
    }

    return {
        programId = MplAgentIdentityProgram.PROGRAM_ID,
        keys      = keys,
        data      = MetaplexBorsh.toBytes(w),
    }, agentIdentityPda
end
