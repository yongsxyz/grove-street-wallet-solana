# Grove Street Wallet - Solana DApp for MTA:SA

Grove Street Wallet is a full-featured Solana Web3 wallet application with a complete UI built using Lua scripting within the MTA:SA environment. This wallet uses **solana-sdk** as the backend for all blockchain operations and provides an intuitive visual interface for managing wallets, assets, and transactions.

## General Information

| Item | Detail |
|------|--------|
| **Name** | Grove Street Wallet |
| **Author** | 0xverse |
| **Version** | 1.0.0 |
| **Dependencies** | `solana-sdk` |
| **Language** | Lua |
| **Type** | Client-server DApp UI |

## File Structure

```
solana-example-wallet/
├── meta.xml          # MTA resource configuration
├── server.lua        # Backend: database, encryption, blockchain integration
├── client.lua        # Frontend: DirectX UI rendering, input handling
├── wallets.db        # SQLite database (encrypted)
├── fonts/            # Custom fonts
│   └── (Poppins-Bold.ttf via :resources)
└── icons/            # UI icons
    ├── add.png       # Add wallet
    ├── back.png      # Back navigation
    ├── backup.png    # Recovery phrase
    ├── confirm.png   # Transaction confirmation
    ├── home.png      # Home tab
    ├── nav_activity.png  # Activity tab
    ├── nav_send.png      # Send tab
    ├── nav_wallets.png   # Wallets tab
    ├── receive.png   # Receive assets
    ├── send.png      # Send assets
    ├── sol.png       # Solana icon
    ├── trash.png     # Delete wallet
    ├── usdc.png      # USDC icon
    └── usdt.png      # USDT icon
```

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                   CLIENT (client.lua)                │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │ DirectX  │  │ Input    │  │ Screen   │          │
│  │ Renderer │  │ Handler  │  │ Manager  │          │
│  └──────────┘  └──────────┘  └──────────┘          │
└────────────────────────┬─────────────────────────────┘
                         │ triggerServerEvent / triggerClientEvent
┌────────────────────────▼─────────────────────────────┐
│                   SERVER (server.lua)                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │ SQLite   │  │ AES-128  │  │ Price    │          │
│  │ Database │  │ Encrypt  │  │ Feed API │          │
│  └──────────┘  └──────────┘  └──────────┘          │
└────────────────────────┬─────────────────────────────┘
                         │ exports["solana-sdk"]
┌────────────────────────▼─────────────────────────────┐
│                    SOLANA SDK                         │
│   Wallet, RPC, Transaction, Crypto, Programs         │
└──────────────────────────────────────────────────────┘
```

## Key Features

### 1. Wallet Management

- **Create new wallet** - Automatically generate keypair
- **Generate 12-word mnemonic** - Recovery phrase compatible with Phantom/Solflare
- **Import wallet** from private key (Phantom and hex formats)
- **Delete wallet** with confirmation
- **Select active wallet** for transactions
- **Database persistence** with encrypted private key storage

### 2. Asset Management

- **SOL balance tracking** with real-time conversion
- **SPL Token support** (USDC, USDT, and other SPL tokens)
- Token detection including Token Program and Token-2022 Program
- Display mint address, symbol, name, and token balance
- Token icons (sol.png, usdc.png, usdt.png)
- Scrollable token list (displays top 5-7 tokens)

### 3. Transaction Features

- **Send SOL** - Native Solana transfers
- **Send SPL Token** - Transfers with automatic ATA creation for recipients
- **Transaction history** with:
  - Status tracking (processed, confirmed, finalized, failed)
  - Block time and elapsed time
  - Full signature and transaction details
  - Instruction parsing, fees, slot, blockhash, compute units
  - Solscan block explorer integration

### 4. Currency & Pricing

- **Real-time price feed** via CoinGecko API:
  - SOL/USD and SOL/IDR
  - USDC/USD and USDC/IDR
  - Updates every 60 seconds
- **Currency toggle:** Display balance in SOL, USD, or IDR
- Automatic portfolio conversion for stablecoins

### 5. Network Support

- **Devnet** and **Mainnet-beta** options
- Per-wallet network tracking
- Network-specific RPC calls via solana-sdk

## Screens & Navigation Flow

```
┌─────────┐
│  Main   │ ──── Balance, Send/Receive buttons, token list
├─────────┤
│  Send   │ ──── Recipient address input, amount, token selection
├─────────┤
│ Receive │ ──── Wallet address for receiving funds
├─────────┤
│ Tokens  │ ──── Full token list with details
├─────────┤
│ Wallets │ ──── Stored wallet list, select/delete
├─────────┤
│Add Wallet│ ── Create new, generate mnemonic, or import
├─────────┤
│Mnemonic │ ──── Display recovery phrase for backup
├─────────┤
│Activity │ ──── Transaction history with status indicators
├─────────┤
│TX Detail│ ──── Full transaction information + explorer link
└─────────┘
```

### Bottom Navigation

| Tab | Icon | Function |
|-----|------|----------|
| Home | `home.png` | Main balance view |
| Send | `nav_send.png` | Transaction screen |
| Activity | `nav_activity.png` | Transaction history |
| Wallets | `nav_wallets.png` | Wallet management |

## UI Design

### Color Scheme

| Element | Color | Code |
|---------|-------|------|
| Background | Dark Navy | `rgb(13, 13, 22)` |
| Card | Slightly Lighter | `rgb(22, 22, 40)` |
| Primary Accent | Purple | `rgb(153, 69, 255)` |
| Success | Green | `rgb(20, 241, 149)` |
| Error | Red | `rgb(240, 50, 50)` |
| Warning/Devnet | Orange | `rgb(255, 170, 30)` |

### Font

Uses **Poppins-Bold** with various sizes:

| Variable | Size | Usage |
|----------|------|-------|
| `fSmall` | 10pt | Labels, secondary text |
| `fBold` | 13pt | Standard text, buttons |
| `fTitle` | 20pt | Screen titles |
| `fBig` | 28pt | Main balance display |

### Panel Dimensions

- **Base:** 400x640px (baseline 1920x1080)
- **Position:** Centered on screen
- **Responsive:** Scale factor applied to all elements

## Input System

Pure DirectX-based input system:

- Keyboard character input
- Backspace deletion
- Tab cycling between input fields
- Ctrl+V clipboard paste support
- Blinking visual cursor
- Placeholder text
- Text clipping for long inputs

## Server-Side Security

### Encryption

- **AES-128-CBC** with unique per-player key
- Key derivation: `SHA256(serial + dbid + salt)`
- Base64 encoding for storage
- PKCS7 padding handling

### Database Schema (SQLite)

```sql
CREATE TABLE wallets (
  id           INTEGER PRIMARY KEY,
  dbid         INTEGER,
  name         TEXT,
  address      TEXT,
  encrypted_key TEXT,
  network      TEXT,
  is_default   INTEGER,
  created_at   TEXT
);
```

## Event System

### Client to Server

| Event | Description |
|-------|-------------|
| `sol:getWallets` | Get player's wallet list |
| `sol:createWallet` | Create new wallet |
| `sol:createMnemonic` | Generate mnemonic |
| `sol:importWallet` | Import from private key |
| `sol:deleteWallet` | Delete wallet |
| `sol:fetchBalance` | Query SOL balance |
| `sol:fetchTokens` | Query all tokens |
| `sol:fetchHistory` | Get transaction history |
| `sol:fetchTxDetail` | Specific transaction details |
| `sol:sendSOL` | Send SOL |
| `sol:sendToken` | Send SPL token |
| `sol:getPrices` | Get price feed |
| `sol:exportKey` | Export private key |

### Server to Client

Each request above has a corresponding response event for UI updates.

## Integration with solana-sdk

```lua
local sol = exports["solana-sdk"]

-- Initialization
sol:initClient({ endpoint = network, commitment = "confirmed" })

-- Wallet
sol:createWallet()
sol:importWallet(privateKey)
sol:generateMnemonic(12)
sol:exportWalletPhantom(address)

-- Queries
sol:fetchBalance(address, callback)
sol:getTokensByOwner(address, ...)
sol:getTransactionHistory(address, ...)

-- Transactions
sol:transferSOL(from, to, amount, ...)
sol:transferTokenToWallet(...)
```
