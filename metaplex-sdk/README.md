# Metaplex SDK for MTA:SA

Pure Lua implementation of the [Metaplex Token Metadata](https://developers.metaplex.com/token-metadata) `CreateV1` flow plus the SPL `MintTo` and `CreateIdempotentATA` instructions needed to mint a fungible token end-to-end. Sits on top of the existing `solana-sdk` resource — it borrows wallet management, transaction signing, and JSON-RPC from there and only implements what is unique to Metaplex: PDA derivation (with on-curve checking), Borsh-style serialization, and the CreateV1 instruction layout.

## General Information

| Item | Detail |
|------|--------|
| **Author** | 0xverse |
| **Version** | 1.0.0 |
| **MTA Minimum** | 1.5.4-9.11342 |
| **Type** | Server-side script resource |
| **Depends on** | `solana-sdk` (>= 2.0.0) |
| **Token Metadata Program** | `metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s` |

## File Structure

```
metaplex-sdk/
├── meta.xml                 # MTA resource manifest
├── metaplex_base58.lua      # Base58 encoder (private copy)
├── metaplex_field.lua       # Ed25519 field arithmetic for on-curve check
├── metaplex_pda.lua         # findProgramAddress (canonical PDA finder)
├── metaplex_borsh.lua       # Borsh-style writers (u8/u16/u32/u64, string, option, vec, pubkey)
├── metaplex_programs.lua    # TokenMetadataProgram.createV1, .mintTo, .createIdempotentAta
└── metaplex_client.lua      # High-level exports (createFungibleToken, mintTokensTo, ...)
```

## Architecture

```
┌──────────────────────────────────┐
│   external resource              │
│   (e.g. metaplex-example)        │
└─────────────┬────────────────────┘
              │ exports["metaplex-sdk"]:createFungibleToken(opts, evt, src)
              ▼
┌──────────────────────────────────┐        ┌──────────────────────────────┐
│   metaplex_client.lua            │        │   solana-sdk resource         │
│   (build instruction →           │ uses → │   wallets, signing, RPC      │
│    delegate to solana-sdk)       │        └──────────────────────────────┘
└─────────────┬────────────────────┘
              │
              ├── metaplex_programs.lua  (createV1, mintTo, createIdempotentAta)
              ├── metaplex_pda.lua       (canonical PDA finder)
              ├── metaplex_field.lua     (Ed25519 on-curve check, mod p = 2^255 - 19)
              ├── metaplex_borsh.lua     (instruction data serialization)
              └── metaplex_base58.lua    (private base58 encoder/decoder)
```

## Why pure Lua?

MTA:SA scripts cannot link Rust crates or load native libraries — only Lua runs. The on-curve check that's required to derive a canonical Solana PDA is therefore implemented in plain Lua field arithmetic (the same 16-limb representation used by TweetNaCl). Hashing piggy-backs on MTA's built-in `hash("sha256", ...)`. Signing is reused from `solana-sdk`'s Ed25519 implementation, so the only new cryptographic primitive in this resource is the on-curve test.

## Wallet source

This SDK **does not own wallets** — it asks `solana-sdk` for them. Every call that needs to sign (e.g. `createFungibleToken`, `createAgent`, `burnTokens`) expects a `wallet` option:

```lua
mp:createAgent({ wallet = "<base58 address>", ... }, "onDone", resourceRoot)
```

That address must already exist inside `solana-sdk`'s in-memory `_wallets` table. If it doesn't, the SDK returns `"Wallet not loaded in solana-sdk: ..."`.

How wallets get into `solana-sdk`:

| Source | Trigger |
|--------|---------|
| Chat command | `/solwallet phrase` / `/solwallet import <key>` / `/solwallet create` (from `solana-example`) |
| F5 Wallet UI | Create Wallet / Add Wallet (from `solana-example-wallet`; wallets are AES-encrypted in SQLite and auto-reimported per player session) |
| Your own resource | `exports["solana-sdk"]:createWallet()` or `:importWallet(privateKey)` |

So before invoking this SDK, ensure at least one of the above populated `solana-sdk`. Then pass that address as `opts.wallet`.

## Usage

### 1. Initialize

`solana-sdk` must already be initialized. After both resources are running, `metaplex-sdk` is ready (it does not keep its own state):

```lua
exports["solana-sdk"]:initClient({ cluster = "devnet", commitment = "confirmed" })
exports["metaplex-sdk"]:initMetaplex() -- optional; called automatically on resource start
```

### 2. Create a fungible token (one-shot)

Equivalent to the Umi `createFungible(...).sendAndConfirm(...)` example from the docs:

```lua
local mp = exports["metaplex-sdk"]

mp:createFungibleToken({
    wallet               = walletAddress,                      -- payer + mint authority
    name                 = "My Fungible Token",
    symbol               = "MFT",
    uri                  = "https://example.com/my-token-metadata.json",
    sellerFeeBasisPoints = 0,
    decimals             = 9,
}, "onTokenCreated", resourceRoot)

addEvent("onTokenCreated", true)
addEventHandler("onTokenCreated", resourceRoot, function(result, err)
    if err then outputDebugString("Error: " .. err) return end
    outputDebugString("Mint:      " .. result.mint)       -- new mint address
    outputDebugString("Metadata:  " .. result.metadata)   -- on-chain metadata PDA
    outputDebugString("Signature: " .. result.signature)
end)
```

### 3. Create + mint in one call

Mirrors the docs' two-step example (`createFungible` then `mintTokensTo`) but runs all three needed transactions back-to-back:

```lua
mp:createAndMintFungible({
    wallet               = walletAddress,
    name                 = "My Fungible Token",
    symbol               = "MFT",
    uri                  = "https://example.com/my-token-metadata.json",
    sellerFeeBasisPoints = 0,
    decimals             = 9,
    amount               = 1000000000000000, -- 1,000,000 tokens at 9 decimals
}, "onTokenReady", resourceRoot)
```

The result payload contains `mint`, `metadata`, `ata`, and `signatures = { create, ata, mint }`.

### 4. Mint more supply later

```lua
local mp = exports["metaplex-sdk"]
local ata = mp:findAssociatedTokenAddress(walletAddress, mintAddress)

mp:createTokenAccount({ wallet = walletAddress, mint = mintAddress }, "onAtaReady", resourceRoot)
-- after onAtaReady fires:
mp:mintTokensTo({ wallet = walletAddress, mint = mintAddress, token = ata, amount = 5000000000 },
    "onMinted", resourceRoot)
```

### 5. PDA helpers

All synchronous (no RPC, no signing):

```lua
local mp = exports["metaplex-sdk"]
local metadata = mp:findMetadataPda(mintAddress)        -- "Md..."
local edition  = mp:findMasterEditionPda(mintAddress)   -- only meaningful for NFTs
local ata      = mp:findAssociatedTokenAddress(owner, mintAddress)
```

## Exports

### High-level token actions
| Function | Description |
|----------|-------------|
| `initMetaplex()` | No-op confirmation. Auto-runs on resource start. |
| `createFungibleToken(opts, eventName, eventSource)` | Single CreateV1 transaction; returns `{ mint, metadata, signature }`. |
| `createAndMintFungible(opts, eventName, eventSource)` | CreateV1 → CreateIdempotentATA → MintTo pipeline. |
| `createTokenAccount(opts, eventName, eventSource)` | Idempotent ATA creation. |
| `mintTokensTo(opts, eventName, eventSource)` | Plain SPL `MintTo` (instruction #7). |

### PDA helpers (sync)
| Function | Returns |
|----------|---------|
| `findMetadataPda(mint)` | `metadataAddress, bump` |
| `findMasterEditionPda(mint)` | `masterEditionAddress, bump` |
| `findAssociatedTokenAddress(owner, mint, tokenProgramId?)` | `ata, bump` |

### Reads
| Function | Description |
|----------|-------------|
| `fetchMetadata(mint, eventName, eventSource)` | Returns `{ metadata, account }` for the metadata PDA. |

### Constants
| Function | Returns |
|----------|---------|
| `getTokenMetadataProgramId()` | `"metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s"` |
| `getTokenStandards()` | Table of enum values: `NonFungible`, `FungibleAsset`, `Fungible`, etc. |

## Off-chain metadata JSON

The `uri` you pass to `createFungibleToken` should point to a publicly fetchable JSON file with at least:

```json
{
  "name": "My Fungible Token",
  "symbol": "MFT",
  "description": "A fungible token on Solana",
  "image": "https://arweave.net/<tx-hash>"
}
```

Recommended hosts: Arweave, IPFS, or any HTTPS endpoint. This SDK does not upload metadata — supply a URL that already exists.

## Performance

- PDA derivation iterates from bump 255 downward and runs the Ed25519 on-curve check until the first off-curve hash is found. About 50% of seed sets find the canonical PDA on the first try; the worst case observed is ~5 iterations. Each on-curve test runs ~250 field squarings, so plan for ~50–250 ms per `findProgramAddress` call on a typical MTA server.
- `createV1` and `mintTo` each take one transaction signature (~0.3–0.5 s of pure-Lua Ed25519 signing per signer in `solana-sdk`).

## Limitations

- Only fungible token creation is wired up. NFT/PNFT minting needs the `mintV1` instruction (Token Metadata) and master-edition PDAs — straightforward to add but intentionally omitted to keep the surface small.
- `fetchMetadata` returns the raw account; on-chain `Metadata` struct decoding is not implemented yet.
- Borsh writers cover what `CreateV1` needs. Adding new instructions is a matter of writing a new builder using `MetaplexBorsh`.

## Author

**0xverse** / **yongsxyz**
