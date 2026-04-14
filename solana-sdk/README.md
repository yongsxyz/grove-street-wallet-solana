# Solana SDK for MTA:SA

Solana SDK is a complete Lua library for interacting with the Solana blockchain within the MTA:SA (Multi Theft Auto: San Andreas) environment. This SDK provides wallet management, transaction building and signing, and RPC communication with the Solana network.

## General Information

| Item | Detail |
|------|--------|
| **Author** | 0xverse |
| **Version** | 2.0.0 |
| **MTA Minimum** | 1.5.4-9.11342 |
| **Type** | Server-side script resource |
| **Language** | Lua |

## File Structure

```
solana-sdk/
├── meta.xml              # MTA resource configuration
├── base58.lua            # Base58 encoding/decoding
├── bip39.lua             # BIP39 mnemonic & SLIP-0010 key derivation
├── bip39_wordlist.lua    # BIP39 2048-word list (English)
├── crypto.lua            # Ed25519 cryptography (pure Lua)
├── programs.lua          # Instruction builder for on-chain programs
├── solana_client.lua     # High-level client API (main entry point)
├── solana_rpc.lua        # JSON-RPC client for network communication
├── token_registry.lua    # Offline token metadata
├── transaction.lua       # Transaction builder & signing
└── wallet.lua            # Wallet management & storage
```

## Architecture

```
┌─────────────────────┐
│  External Resources  │
│  (solana-example,    │
│   solana-example-wallet) │
└─────────┬───────────┘
          │  exports["solana-sdk"]:functionName(...)
          │
     ┌────▼──────────────────┐
     │  solana_client.lua     │  High-level API
     │  (convenience layer)   │  Build/sign/send transactions
     └────┬───────────────────┘  Query RPC via events
          │
          ├──────────┬──────────┬──────────────┐
          │          │          │              │
     ┌────▼──┐ ┌────▼─────┐ ┌─▼────────┐ ┌──▼──────────┐
     │wallet │ │solana_rpc│ │programs  │ │transaction  │
     │.lua   │ │.lua      │ │.lua      │ │.lua         │
     └────┬──┘ └────┬─────┘ └─┬────────┘ └──┬──────────┘
          │         │          │             │
     ┌────▼─────────▼──────────▼─────────────▼───┐
     │          crypto.lua (Ed25519)              │
     │   SHA-512, SHA-256, HMAC, Field Arithmetic │
     └────┬──────────────────────────────────────┘
          │
     ┌────▼─────────────────────────────────────┐
     │  base58.lua | bip39.lua | token_registry │
     │  Encoding & Utilities                     │
     └──────────────────────────────────────────┘
```

## Key Features

| Feature | Status | Notes |
|---------|--------|-------|
| **Network** | Mainnet, Devnet, Testnet, Localnet | Via cluster endpoints |
| **Wallet Format** | Hex, Base58, JSON, BIP39 | Compatible with Phantom/Solflare |
| **Key Type** | Ed25519 | 32-byte seed, 64-byte with pubkey |
| **Transactions** | Legacy (v0) | Versioned tx (v1) not yet supported |
| **Token Program** | Token & Token-2022 | SPL tokens |
| **ATA** | Auto-create with PDA derivation | Bump 255 to 0 |
| **Signing** | Single & multi-signer | All signers must be imported |
| **RPC Methods** | 30+ methods | Balance, tokens, history, blocks, etc. |
| **Async Pattern** | Event-based callbacks | `triggerEvent` for results |
| **Testing** | RFC 8032 test vectors | `runSelfTest()` |

## Module Descriptions

### base58.lua

Base58 encoding/decoding implementation for Solana addresses.

**Main Functions:**
- `Base58.encode(bytes)` - Convert byte array to Base58 string
- `Base58.decode(str)` - Decode Base58 string to byte array
- `Base58.isValidSolanaAddress(addr)` - Validate Solana address format (32-44 characters)

### crypto.lua

Pure Lua Ed25519 cryptography implementation, including signing, key derivation, and hash functions.

**Main Functions:**
- `Ed25519.keypairFromSeed(seed)` - Generate keypair from 32-byte seed
- `Ed25519.sign(message, keypair)` - Sign a message, producing a 64-byte signature
- `Crypto.sha512(data)` / `Crypto.sha256(data)` - Hash functions
- `Crypto.hmacSha512(key, message)` - HMAC-SHA512
- `Ed25519.selfTest()` - Validate against RFC 8032 test vectors

### bip39.lua

BIP39 mnemonic phrase and SLIP-0010 key derivation implementation following Solana standards.

**Main Functions:**
- `BIP39.generateMnemonic(wordCount)` - Generate 12 or 24 word mnemonic
- `BIP39.mnemonicToSeed(mnemonic, passphrase)` - Derive 64-byte seed via PBKDF2
- `BIP39.mnemonicToKeypair(mnemonic, passphrase)` - Full pipeline: mnemonic to keypair
- `BIP39.isValidMnemonic(mnemonic)` - Validate mnemonic format

**Derivation Path:** `m/44'/501'/0'/0'` (Solana standard, compatible with Phantom/Solflare)

### programs.lua

Instruction encoding builder for Solana on-chain programs.

**Supported Programs:**

| Program | ID | Functions |
|---------|-----|--------|
| **SystemProgram** | `1111...1111` | `transfer`, `createAccount`, `allocate`, `assign` |
| **TokenProgram** | `TokenkegQ...` | `transfer`, `approve`, `revoke`, `burn`, `closeAccount` |
| **AssociatedTokenProgram** | `ATokenGP...` | `findAddress`, `createIdempotent` |
| **MemoProgram** | `MemoSq4g...` | `memo` |
| **CustomProgram** | Any | `instruction`, `anchorInstruction` |

### transaction.lua

Build, sign, and serialize Solana transactions (legacy format, version 0).

**Main Functions:**
- `SolTransaction.new()` - Create an empty transaction
- `tx:setRecentBlockhash(blockhash)` - Set blockhash
- `tx:setFeePayer(address)` - Set fee payer
- `tx:addInstruction(instruction)` - Add instruction
- `tx:signAndEncode()` - Sign and return base64 (ready for RPC)

### solana_rpc.lua

Async JSON-RPC client for Solana network communication via MTA's `fetchRemote`.

**Method Categories:**
- **Account:** `getBalance`, `getAccountInfo`, `getTokenAccountsByOwner`, etc.
- **Transaction:** `sendTransaction`, `getTransaction`, `simulateTransaction`, etc.
- **Block & Slot:** `getLatestBlockhash`, `getBlockHeight`, `getSlot`, etc.
- **Network:** `getHealth`, `getVersion`, `getEpochInfo`, etc.

### wallet.lua

In-memory wallet management: import/export in various formats and key signing.

**Supported Formats:**
- **Hex** - 64-character hex string (32-byte seed)
- **Base58** - 64 bytes encoded (compatible with Phantom/Solflare)
- **JSON** - Solana CLI array format `[1,2,...,64]`
- **BIP39** - 12/24-word mnemonic phrase

### solana_client.lua

High-level convenience API that exports all functions for use by other resources.

**Exported Function Categories:**

- **Initialization:** `initClient`, `getClientStatus`, `destroyClient`
- **Wallet:** `createWallet`, `importWallet`, `generateMnemonic`, `importFromMnemonic`, etc.
- **Balance & Account:** `fetchBalance`, `fetchAccount`, `getTokenBalance`, `getTokensByOwner`
- **Transactions:** `transferSOL`, `transferToken`, `transferTokenToWallet`, `sendCustomTransaction`
- **Token Operations:** `approveToken`, `revokeToken`, `burnToken`, `closeTokenAccount`
- **Network Info:** `getSlot`, `getBlockHeight`, `getEpochInfo`, `getHealth`, `getVersion`
- **Watchers:** `watchBalance`, `watchSignature`, `stopWatcher`
- **Utilities:** `runSelfTest`, `lamportsToSol`, `solToLamports`, `isValidAddress`

### token_registry.lua

Offline token metadata lookup (no external API required).

**Available Tokens:**
- **Devnet:** USDC-Dev, SOL, USDC-Dev2
- **Mainnet:** SOL, USDC, USDT, ETH, mSOL, stSOL, BONK, JUP, WIF, RNDR, PYTH, JTO, TNSR, W, MEW, WEN
- **Testnet:** SOL

## Usage

### Initialize Client

```lua
exports["solana-sdk"]:initClient({
  endpoint = "devnet",       -- or "mainnet-beta", "testnet", custom URL
  commitment = "confirmed",
  timeout = 10000
})
```

### Create Wallet

```lua
-- Random wallet (testing only)
local address = exports["solana-sdk"]:createWallet()

-- From mnemonic (recommended)
local address = exports["solana-sdk"]:importFromMnemonic("word1 word2 ... word12")

-- Generate new mnemonic
local mnemonic, address = exports["solana-sdk"]:generateMnemonic(12)
```

### Query Balance

```lua
exports["solana-sdk"]:fetchBalance(address, "onBalance", resourceRoot)

addEvent("onBalance", true)
addEventHandler("onBalance", resourceRoot, function(result, err)
  if err then
    print("Error: " .. err)
  else
    print("Balance: " .. result.sol .. " SOL")
    print("Lamports: " .. result.lamports)
  end
end)
```

### Transfer SOL

```lua
exports["solana-sdk"]:transferSOL(fromAddress, toAddress, 0.5, "onTransfer", resourceRoot)

addEvent("onTransfer", true)
addEventHandler("onTransfer", resourceRoot, function(result, err)
  if err then
    print("Transfer failed: " .. err)
  else
    print("Signature: " .. result.signature)
  end
end)
```

### Transfer SPL Token

```lua
exports["solana-sdk"]:transferTokenToWallet(
  fromWallet, srcTokenAccount, dstWallet, mintAddress,
  amount, "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
  "onTokenTransfer", resourceRoot
)
```

## Security Notes

1. **Random Generation:** NOT cryptographically secure (uses `getTickCount()`, `math.random()`). For dev/test only.
2. **In-Memory Storage:** Wallets are stored in Lua tables, not persisted to disk or encrypted.
3. **Signing Speed:** ~0.3-0.5 seconds per signature (normal for pure Lua).
4. **Best Practice:** Import keys from established wallets (Phantom, Solflare) for mainnet. Do not generate keys with this SDK for real funds.

## Dependencies

No external dependencies. All cryptography is implemented in pure Lua.

## Version

| Version | Changes |
|---------|---------|
| 2.0.0 | Current version with 50+ exported functions |
