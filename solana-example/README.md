# Solana Example - Demo Resource for MTA:SA

> **⚠ BETA** - This resource is still in beta. Some commands may change or break in future updates.

Solana Example is a demo resource for MTA:SA that demonstrates Solana blockchain integration. This resource shows how to use the **solana-sdk** to perform real blockchain operations through in-game commands.

## General Information

| Item | Detail |
|------|--------|
| **Author** | 0xverse |
| **Type** | Demo / tutorial resource |
| **Dependencies** | `solana-sdk` |
| **Default Network** | Devnet |
| **Language** | Lua |

## File Structure

```
solana-example/
├── meta.xml       # MTA resource configuration (includes solana-sdk)
├── server.lua     # Main server-side logic (791 lines)
└── client.lua     # Client-side UI display (17 lines)
```

## Architecture

```
┌───────────┐    command     ┌──────────────┐   exports    ┌────────────┐
│  Player   │ ──────────────>│  server.lua  │ ──────────>  │ solana-sdk │
│ (in-game) │                │  (handler)   │              │  (library) │
└───────────┘                └──────┬───────┘              └─────┬──────┘
      ▲                            │                             │
      │    triggerClientEvent       │       triggerEvent          │
      └────────────────────────────┘◄────────────────────────────┘
              chat output                  async callback
```

- **Server-side:** Handles all RPC calls to Solana, manages the async request queue, formats responses, and sends results to the player via chat
- **Client-side:** Listens for the `onSolBalanceUpdate` event from the server and displays information on the player's HUD/chat

## Command List

### Network Information

| Command | Description |
|---------|-------------|
| `/solhealth` | Check Solana cluster health and node version |
| `/solslot` | Get current slot, epoch info, and block height |

### Data Queries (Read-Only)

| Command | Parameters | Description |
|---------|------------|-------------|
| `/solbalance` | `<address>` | Get SOL balance (in SOL and lamports) |
| `/solaccount` | `<address>` | Get detailed account info (owner, executable status) |
| `/soltokens` | `<address>` | List all SPL tokens owned by the address |
| `/soltxhistory` | `<address> [limit]` | Get transaction history with signatures and status |
| `/solwatch` | `<address>` | Toggle real-time balance monitoring (updates every 5 seconds) |

### Wallet Management

| Command | Parameters | Description |
|---------|------------|-------------|
| `/solwallet create` | - | Create a new random wallet |
| `/solwallet phrase` | - | Create a wallet with a 12-word mnemonic (Phantom compatible) |
| `/solwallet import` | `<key>` | Import wallet from hex/base58 private key |
| `/solwallet list` | - | Display all stored wallets |
| `/solwallet export` | `<address>` | Export key in various formats |
| `/solwallet remove` | `<address>` | Remove wallet from storage |
| `/solphrase` | `[12\|24]` | Quick mnemonic generation (12 or 24 words) |
| `/solimport` | `<word1> ... <word12>` | Import wallet from mnemonic phrase |

### Devnet Operations

| Command | Parameters | Description |
|---------|------------|-------------|
| `/solairdrop` | `<address> [amount]` | Request testnet SOL (devnet only) |

### SOL Transfer

| Command | Parameters | Description |
|---------|------------|-------------|
| `/solsend` | `<from> <to> <amount>` | Transfer SOL with auto-signing (~0.5 seconds) |

### Token Operations (SPL)

| Command | Parameters | Description |
|---------|------------|-------------|
| `/soltokensend` | `<wallet> <src_ata> <dst_ata> <amount>` | Transfer SPL tokens between accounts |
| `/solapprove` | `<wallet> <token_acc> <delegate> <amount>` | Approve delegate for spending |
| `/solrevoke` | `<wallet> <token_acc>` | Revoke all approvals |
| `/solburn` | `<wallet> <token_acc> <mint> <amount>` | Permanently burn tokens |
| `/solcloseacc` | `<wallet> <token_acc>` | Close token account and reclaim rent SOL |

### Custom Program Interaction

| Command | Parameters | Description |
|---------|------------|-------------|
| `/solcustom` | `<wallet> <program_id> [hex_data]` | Call a custom Solana program |
| `/solanchor` | `<wallet> <program_id> <method> [hex_args]` | Call an Anchor program with auto discriminator |
| `/solmemo` | `<wallet> <text>` | Send an on-chain memo (permanently stored) |
| `/solmultitx` | `<wallet> <to> <amount>` | Demo atomic multi-instruction transaction (SOL transfer + memo) |

### Testing & Help

| Command | Description |
|---------|-------------|
| `/soltest` | Run Ed25519 cryptography self-test |
| `/solhelp` | Display quick-start guide |

## Async Callback Pattern

All blockchain operations are asynchronous. The SDK uses event-based callbacks:

```lua
local sol = exports["solana-sdk"]

-- Send request
sol:fetchBalance(address, "onSolBalanceResult", resourceRoot)

-- Capture response
addEvent("onSolBalanceResult", true)
addEventHandler("onSolBalanceResult", resourceRoot, function(result, error)
  if error then
    outputChatBox("Error: " .. error, player)
  else
    outputChatBox("Balance: " .. result.sol .. " SOL", player)
  end
end)
```

## Typical Workflow

1. Resource starts, `initClient` is called with devnet configuration
2. Player types a command in chat (e.g., `/solwallet create`)
3. Server receives the command and calls the appropriate SDK function
4. SDK performs the operation (key generation, RPC call, etc.)
5. Result is sent back via event trigger
6. Server formats the output and sends it to the player's chat

## Developer Features

- Ed25519 self-test for signature verification
- Raw instruction building and custom transaction support
- Anchor program integration with automatic discriminator calculation
- Multi-instruction transactions for atomic operations
- Flexible token amount handling (raw vs UI amounts)

## Security Notes

- Private keys are handled server-side only
- No sensitive data is sent to the client
- Input validation on all commands
- Clear warnings about key/phrase handling
