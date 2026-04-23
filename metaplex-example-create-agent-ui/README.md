# Metaplex Agent Creator UI (MTA:SA)

DirectX panel inside MTA:SA for creating and managing **real Metaplex agents** — MPL Core assets with the AgentIdentity plugin attached, fully indexed by `metaplex.com/agents`. Thin visual wrapper around `metaplex-sdk`'s `createAgent` flow.

Open with **F7**. Close with the X button or **Esc**.

## General Information

| Item | Detail |
|------|--------|
| **Author** | 0xverse |
| **Version** | 1.0.0 |
| **Type** | Server + client resource |
| **Depends on** | `solana-sdk`, `metaplex-sdk` |
| **Toggle key** | `F7` |

## What "Creating an Agent" Actually Does

One atomic Solana transaction containing three instructions:

```
┌─ Instruction 0: MPL Core createCollectionV2
│    Allocates an on-chain collection account owned by CoREE...
│
├─ Instruction 1: MPL Core createV2
│    Allocates the asset account under that collection.
│    updateAuthority is inherited from the collection.
│
└─ Instruction 2: MPL Agent Registry registerIdentityV1
     Creates the AgentIdentity PDA (seeds ["agent_identity", asset])
     Attaches the AgentIdentity plugin to the asset, pointing to the
     uploaded ERC-8004 JSON on IPFS.
```

Side effects:
- **Metaplex indexer picks up the agent** — it appears at `metaplex.com/agents/<asset>`.
- **Asset Signer PDA** is derivable: `['mpl-core-execute', asset]` — the built-in wallet. Can receive SOL / tokens.
- **AgentIdentity plugin** attached with lifecycle hooks (Transfer, Update, Execute).

## Screens

1. **Wallet picker** — shown when no wallet is loaded; lists wallets from `solana-sdk`.
2. **Home** — selected wallet + list of every agent you've registered through the UI.
3. **Create** — Identity form (name, description, image URL). Shows the exact 3-instruction flow.
4. **Info** — selected agent's asset/collection/identity-PDA/signer-PDA addresses, IPFS CID, on-chain URI, and live PDA SOL balance.
5. **Deposit** — send SOL from your wallet to the agent's Asset Signer PDA.

## Where "Active Wallet" comes from

The wallet displayed at the top of the Home screen (and used for every on-chain action) is read from **`solana-sdk`**'s in-memory `_wallets` table via `exports["solana-sdk"]:listWallets()`. This UI only *selects* — it does NOT create wallets.

Populate `_wallets` via one of:

* Chat: `/solwallet phrase`, `/solwallet import <key>`, `/solwallet create` (requires `solana-example`)
* F5 wallet UI (`solana-example-wallet`) — persistent AES-encrypted SQLite, auto-reimports per player
* Direct export: `exports["solana-sdk"]:createWallet()` / `:importWallet(privKey)` from any custom resource

Click **Switch** in the header to see the picker — it lists every address currently in `solana-sdk`. Click one → it becomes the "ACTIVE WALLET" and signs all CreateV2 + createCollectionV2 + registerIdentityV1 instructions in the atomic agent-creation transaction.

⚠️ `solana-sdk`'s wallet list is **in-memory only**. If you restart the `solana-sdk` resource (not the UI), wallets loaded via `/solwallet` are lost. The F5 wallet UI persists them in SQLite.

## Requirements

Before opening the UI, have in place:

1. **Pinata credentials** — hard-coded in `server.lua` by default (the same ones as `metaplex-example`). Replace before production.
2. **A wallet with devnet SOL** — see the "Where Active Wallet comes from" section above, then `/solairdrop <addr> 2`.
3. **Image URL** (optional) — upload your logo at [app.pinata.cloud](https://app.pinata.cloud), paste the returned `gateway.pinata.cloud/ipfs/<cid>` URL in the Image field.

## Flow

```
F7 → Wallet picker auto-selects your first loaded wallet
Click "+ Create New Agent"
  - Name: "Plexpert"
  - Description: "Metaplex expert agent"
  - Image URL: https://gateway.pinata.cloud/ipfs/<your-logo>
Click "Register Agent"

Server steps (~2-3 seconds total):
  1. Pre-generate collection + asset keypairs
  2. Build ERC-8004 JSON, upload to IPFS (Pinata)
  3. Build 3 instructions, sign with 3 keypairs, submit atomic tx
  4. Record the agent in created_agents.json

UI auto-jumps to Info screen.

Click "Metaplex" button → copies https://www.metaplex.com/agent/<asset>
  to clipboard. Open in browser to verify indexer picked it up.

Click "Deposit SOL" → send SOL from your wallet to the agent's PDA.
Click "Refresh" → re-fetch PDA balance from RPC.
```

## Persistence

`created_agents.json` in the resource folder stores entries keyed by wallet address. Survives restarts. To clear, delete the file.

## Security

- Pinata credentials live in source — **rotate via [Pinata dashboard](https://app.pinata.cloud/developers/api-keys)** after demo.
- Agent's Asset Signer PDA has no private key — funds are safe from theft but also can't be withdrawn without MPL Core Execute instruction (not implemented here — would require additional SDK work).
- Wallets come from `solana-sdk`'s in-memory store. Never persisted by this resource.

## Author

**0xverse** / **yongsxyz**
