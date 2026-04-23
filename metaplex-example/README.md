# Metaplex Example for MTA:SA

Pure Lua command-line demo for `metaplex-sdk` — the Metaplex companion to `solana-sdk`. Mirrors the [Metaplex "Create a Fungible Token" guide](https://developers.metaplex.com/token-metadata/getting-started/create-a-fungible-token) but every step runs from inside MTA:SA chat.

## General Information

| Item | Detail |
|------|--------|
| **Author** | 0xverse |
| **Version** | 1.0.0 |
| **Type** | Server-side script resource (with stub client) |
| **Depends on** | `solana-sdk`, `metaplex-sdk` |

## File Structure

```
metaplex-example/
├── meta.xml      # Resource manifest with includes for solana-sdk and metaplex-sdk
├── server.lua    # All chat commands and event handlers
└── client.lua    # Tiny placeholder for a future GUI
```

## Where wallets come from

Every `/mp*` command takes a `<wallet>` argument. That address **must already be in `solana-sdk`**'s in-memory wallet store. Populate it via one of:

* `/solwallet create` — random keypair (dev-only entropy, not crypto-secure)
* `/solwallet phrase` — generates a 12-word mnemonic
* `/solwallet import <base58Key>` — import from Phantom/Solflare
* Open the F5 **Grove Street Wallet** UI and Create/Add — the wallet UI stores encrypted keys in SQLite and pushes them into `solana-sdk` per player

If the wallet isn't loaded, `/mp*` commands respond: `Wallet not loaded in solana-sdk`.

> `solana-sdk`'s store is **in-memory** — restarting `solana-sdk` (not the UI) wipes wallets. Use F5's wallet UI for persistence.

## Quick Start

1. Drop `solana-sdk`, `metaplex-sdk`, and `metaplex-example` into your MTA server's `resources/` folder.
2. Start them in this order: `solana-sdk` → `metaplex-sdk` → `metaplex-example`.
3. In-game, prepare a wallet with some devnet SOL:
   ```
   /solwallet phrase                  # creates new mnemonic wallet, prints address
   /solairdrop <yourAddress> 2        # devnet only
   /solbalance <yourAddress>          # confirm SOL arrived
   ```
4. Pre-upload your token's metadata JSON somewhere reachable (Arweave, Pinata, GitHub raw, etc.). Minimum payload:
   ```json
   {
     "name": "My Fungible Token",
     "symbol": "MFT",
     "description": "A fungible token on Solana",
     "image": "https://arweave.net/<tx-hash>"
   }
   ```
5. Create + mint a fungible token in one command. Two flavours:
   ```
   # Friendly: supply in HUMAN units (1000000 = 1,000,000 tokens)
   /mptoken <yourAddress> "My Fungible Token" MFT https://example.com/meta.json 1000000 9 0

   # Power user: supply as RAW u64 (you do the * 10^decimals math yourself)
   /mpall   <yourAddress> "My Fungible Token" MFT https://example.com/meta.json 1000000000000000 9 0
   ```
   Both run CreateV1 → CreateIdempotent ATA → MintTo and print all three signatures.

## Commands

### Helpers
| Command | Description |
|---------|-------------|
| `/mphelp` | Short help screen (also gently reminds you to `/solairdrop` first). |
| `/mpprogram` | Print the Token Metadata program id (`metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s`). |

### PDA helpers (no RPC, instant)
| Command | Description |
|---------|-------------|
| `/mpmetapda <mint>` | Print the metadata PDA + bump for a mint. |
| `/mpata <owner> <mint>` | Print the ATA + bump for an owner+mint pair. |

### Token creation
| Command | Description |
|---------|-------------|
| `/mpcreate <wallet> <name> <symbol> <uri> [decimals] [bps]` | Just CreateV1. Generates a fresh mint keypair and prints its address. |
| `/mpata-create <wallet> <mint>` | Idempotent ATA creation for the wallet itself. |
| `/mpmint <wallet> <mint> <ata> <amount>` | Plain SPL `MintTo`. Amount is RAW u64 (factor in decimals yourself). |
| `/mpall <wallet> <name> <symbol> <uri> <amount> [decimals] [bps]` | Atomic: CreateV1 + CreateIdempotent ATA + MintTo in one TX. `amount` is RAW u64. |
| `/mptoken <wallet> <name> <symbol> <uri> <initialSupply> [decimals] [bps]` | Same atomic pipeline but `initialSupply` is in HUMAN units. SDK auto-multiplies by 10<sup>decimals</sup>. |

### Update & burn
| Command | Description |
|---------|-------------|
| `/mpupdate <wallet> <mint> <name> <symbol> <uri> [bps]` | Changes on-chain name/symbol/uri. Wallet must be the update authority and the token must be mutable (created with `isMutable=true`, the SDK default). |
| `/mpburn <wallet> <mint> <humanAmount> [decimals]` | Permanently destroys tokens from the wallet's ATA. Uses human units — pass `100` to burn 100 tokens. |

### Agents (simplified)

Two related flows:

**A. Create an agent identity** — mimics the Metaplex [Register an Agent](https://developers.metaplex.com/agents/register-an-agent) wizard (Identity → Services → Review).

| Command | Description |
|---------|-------------|
| `/mpipfskey <apiKey> <apiSecret>` | **(preferred)** Store Pinata API Key + Secret in server memory. |
| `/mpipfsjwt <pinataJwt>` | Alternative: use a Bearer JWT instead of key+secret. (Alias: `/mpipfsconfig`) |
| `/mpipfsstatus` / `/mpipfstest` | Show / verify the configured auth. |
| `/mpipfsclear` | Wipe stored credentials from memory. |
| `/mpagentcreate <wallet> <name> <description> <imageUri>` | Mint a 1/1 SPL token + print the ERC-8004 JSON. |
| `/mpagentjson <agentMint> <name> <description> <imageUri>` | Re-generate the JSON without touching chain. |
| **`/mpagentpublish <wallet> <agentMint> <name> <description> <imageUri>`** | **One-shot:** build JSON → upload to IPFS via Pinata → update on-chain URI. Most users want this. |
| `/mpagentsetreg <wallet> <agentMint> <registrationUri>` | Manual fallback if you uploaded the JSON yourself elsewhere. |
| `/mpagentpda <agentMint>` | Derive the agent's Asset Signer PDA (built-in wallet). Deterministic, no RPC. |

#### Where to host the registration JSON?

The ERC-8004 registration JSON needs to live somewhere reachable by HTTP. Common choices:

| Host | Cost | Persistence | Setup in this SDK |
|------|------|-------------|------------------|
| **Pinata IPFS** | Free tier (1GB) | As long as Pinata pins it (free indefinitely on free plan) | ✅ Built-in via `/mpagentpublish`. Get a JWT → `/mpipfsconfig <jwt>` once. |
| **NFT.Storage / Web3.Storage** | Free | Long-term backed by Filecoin | Not built-in (similar JSON pin API; could be added) |
| **Arweave (via Irys)** | Pay-once, permanent | Forever | Not built-in (requires AR/SOL signature flow that's complex in pure Lua) |
| **Plain HTTPS server** | Your hosting | While your server stays up | Use any URL you control with `/mpagentsetreg` |

The on-chain metadata URI is opaque — Solana doesn't care if it's `ipfs://`, `https://gateway.pinata.cloud/ipfs/...`, `https://arweave.net/...`, or your own static site. Pick whichever your downstream consumers (wallets, indexers) prefer.

**Recommended:** Pinata IPFS — free, no payment flow, content-addressed (same CID resolves through `ipfs.io`, `dweb.link`, `cloudflare-ipfs.com`, etc.).

**B. Launch a token tied to an agent** — mimics the Metaplex [Create an Agent Token](https://developers.metaplex.com/genesis/create-an-agent-token) docs.

| Command | Description |
|---------|-------------|
| `/mpagenttoken <wallet> <agentMint> <name> <symbol> <uri> <supply> [decimals] [bps]` | Create a fungible whose sole creator is the agent's Asset Signer PDA. Atomic pipeline like `/mptoken`. |

#### Typical flow (with auto IPFS upload)

```
# Pre-req: wallet loaded + funded
/solwallet phrase
/solairdrop <yourAddr> 2

# Pre-req (one-time): configure Pinata for IPFS uploads.
# Pick ONE of the two auth methods:
/mpipfskey  <apiKey> <apiSecret>          # preferred
#   -- OR --
/mpipfsjwt  eyJhbGciOi...your.jwt.here    # JWT alternative

/mpipfstest                                # confirm "Auth OK"

# 1. Mint the agent on-chain (1/1 SPL token + placeholder metadata URI)
/mpagentcreate <yourAddr> Plexpert "An informational agent" https://arweave.net/<image-tx>
# -> prints mint address, metadata PDA, agent signer PDA, AND the ERC-8004 JSON

# 2. Upload the JSON to IPFS + update the on-chain URI in ONE call:
/mpagentpublish <yourAddr> <agentMintFromStep1> Plexpert "An informational agent" https://arweave.net/<image-tx>
# -> prints CID, ipfs:// URI, multiple https gateway URLs, on-chain signature

# 3. (optional) Launch a token where creator fees route to the agent's PDA
/mpagenttoken <yourAddr> <agentMintFromStep1> "Plexpert Token" PLX https://gateway.pinata.cloud/ipfs/<tokenMetaCid> 1000000 9 0
```

#### Manual upload alternative

If you already host the JSON elsewhere (Arweave, your own server, etc.):

```
/mpagentcreate <yourAddr> Plexpert "Description" https://arweave.net/<image-tx>
# -> copy the JSON output, upload to your host, get URL
/mpagentsetreg <yourAddr> <agentMintFromStep1> https://your-host.example/agent.json
```

> **Heads-up: this is a simplified demo, not the real MPL Core + Agent Registry.**
>
> The full Metaplex flow requires:
>
> * **MPL Core** `create` / `createCollection` instructions — complex plugin system, ~thousands of lines of Rust/TS to replicate raw byte-for-byte
> * **MPL Agent Registry** `registerIdentityV1` — creates an AgentIdentity plugin with lifecycle hooks (Transfer, Update, Execute)
> * The hosted **Metaplex Genesis API** at `https://api.metaplex.com` for bonding-curve launches (private HTTP contract)
> * Wrapping launch transactions inside MPL Core's `Execute` instruction so the agent's PDA signs on-chain
>
> None of that is feasible in pure Lua. Instead we approximate each concept using primitives we already have:
>
> | Real Metaplex | Our simplified version |
> |---------------|------------------------|
> | MPL Core 1/1 asset | SPL token, decimals=0, supply=1 |
> | AgentIdentity plugin | Metadata URI pointing to ERC-8004 JSON |
> | Asset Signer PDA | Same derivation: `['mpl-core-execute', mint]` under MPL Core — the PDA address is IDENTICAL to the real one, but on-chain MPL Core won't actually execute for it |
> | `setToken: true` | Not implemented |
> | Bonding curve launch | Plain `createV1 + ATA + MintTo`, no liquidity curve |
>
> The PDA address, the ERC-8004 JSON contents, and the on-chain metadata format all match the real spec — so downstream indexers and UIs that only read these fields will see something sensible. What they WON'T see is a real `AgentIdentity` plugin on an MPL Core asset.

### Read
| Command | Description |
|---------|-------------|
| `/mpinfo <mint>` | Digital-asset view: decoded metadata + mint supply/decimals/authorities in one shot. |
| `/mpbalance <owner> <mint>` | Balance of `owner`'s associated token account for `mint`. |
| `/mpfetch <mint>` | Decoded Metadata account (name, symbol, uri, bps, isMutable). |

## Notes

- All transactions land on whichever cluster `solana-sdk` was initialised against (devnet by default per `solana-sdk/solana_client.lua`). Switch by editing the `initClient` call in `solana-sdk` or by running mainnet at your own risk.
- The wallet you pass to every command must already be loaded in `solana-sdk`'s in-memory store — see `/solwallet` commands in `solana-example` to create or import one.
- Each on-chain step takes ~1–2 seconds because Ed25519 signing happens in pure Lua. The `/mpall` pipeline therefore takes ~3–6 seconds end-to-end. Watch debugscript 3 for progress lines.
- The example assumes the metadata JSON URI is already publicly reachable. This SDK does not upload to Arweave/IPFS for you.

## Author

**0xverse** / **yongsxyz**
