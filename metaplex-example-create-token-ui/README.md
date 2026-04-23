# Metaplex Token Creator UI (MTA:SA)

DirectX panel inside MTA:SA for creating, listing, updating, and burning fungible Solana tokens. Thin visual wrapper around [`metaplex-sdk`](../metaplex-sdk/).

Open with **F6**. Close with the X button or **Esc**.

## General Information

| Item | Detail |
|------|--------|
| **Author** | 0xverse |
| **Version** | 1.0.0 |
| **Type** | Server + client script resource |
| **Depends on** | `solana-sdk`, `metaplex-sdk` |
| **Toggle key** | `F6` |

## File Structure

```
metaplex-example-create-token-ui/
├── meta.xml          # Resource manifest
├── server.lua        # Bridges UI events to metaplex-sdk + JSON-persists "my tokens"
└── client.lua        # DirectX panel (home / create / info / update / burn)
```

## Screens

1. **Wallet picker** — shown automatically when no wallet from `solana-sdk` is loaded yet. Run `/solwallet phrase` or `/solwallet import <key>` in chat to populate this list; then reopen the panel.
2. **Home** — selected wallet + every token that wallet has created through the UI. Click a row to open it.
3. **Create** — form: name, symbol, URI, decimals, initial supply, BPS. Hits `createAndMintFungible` (atomic `CreateV1 + ATA + MintTo` in one signature).
4. **Info** — decoded Metadata + mint account: chain name/symbol/URI, raw supply, decimals, `isMutable`, update authority, mint authority.
5. **Update** — edit name / symbol / URI / BPS. Blank field = keep existing on-chain value. Requires `isMutable == true` and the current wallet to be the update authority.
6. **Burn** — burn N tokens in human units. Irreversible.

## Persistence

Tokens minted through the UI are recorded in `created_tokens.json` inside the resource folder, keyed by wallet base58 address. On next open the panel re-reads the file so the list survives across sessions. Removing a wallet from `solana-sdk`'s store does **not** delete its entries — the file is a separate index.

## Where "Active Wallet" comes from

The wallet shown on the Home screen is read from **`solana-sdk`**'s in-memory `_wallets` table via `exports["solana-sdk"]:listWallets()`. This UI does NOT create wallets on its own — it only selects from the ones already loaded.

The table is populated by one of:

* Chat: `/solwallet phrase`, `/solwallet import <key>`, `/solwallet create` (via `solana-example`)
* F5 wallet UI (`solana-example-wallet`) — wallets are AES-encrypted in SQLite and auto-reimported into `solana-sdk` when a player opens the UI
* A custom resource calling `exports["solana-sdk"]:createWallet()` / `:importWallet(privKey)`

When you click **Switch** in the header, the picker lists every address currently in `_wallets`. Click one → it becomes the "ACTIVE WALLET" for this UI session, and all Create / Update / Burn actions sign with its keypair.

⚠️ `solana-sdk`'s store is **in-memory only**. Restarting the `solana-sdk` resource wipes wallets loaded via `/solwallet`. Wallets from the F5 wallet UI survive because they're decrypted from SQLite per player.

## Requirements in chat before opening

| Step | Command |
|------|---------|
| 1. Load a wallet into `solana-sdk` | `/solwallet phrase` (or `/solwallet import <base58_or_hex>`) |
| 2. Fund it with devnet SOL | `/solairdrop <yourAddr> 2` |

Once a wallet is loaded, press **F6** to open the UI. Wallets appear in the picker automatically.

## Notes

- All transactions land on whichever cluster `solana-sdk` was initialised against (devnet by default).
- Each on-chain call takes ~1–2 seconds because Ed25519 signing runs in pure Lua. The "Working..." button state reflects the signing pass.
- The token list is scoped to **the currently-selected wallet**. Use the **Switch** button on Home to change wallets; the list refreshes.
- The Info screen's "Refresh" button pulls the latest on-chain metadata and mint account data via `getAccountInfo`. Use it after an Update or Burn to confirm changes propagated.

## Author

**0xverse** / **yongsxyz**
