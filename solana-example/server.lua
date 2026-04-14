-- https://github.com/yongsxyz
--[[
    ---
    SOLANA SDK - COMPLETE EXAMPLE RESOURCE
    ---
    Grove Street Wallet - Example usage for MTA:SA

    COMMANDS:
    ── NETWORK ──────────────────────────────────────────
    /solhealth                          Check cluster health + version
    /solslot                            Check slot, epoch, block height

    ── READ DATA ────────────────────────────────────────
    /solbalance <address>               Check SOL balance
    /solaccount <address>               Detail account info
    /soltokens <address>                List all SPL tokens
    /soltxhistory <address> [limit]     Transaction history
    /solwatch <address>                 Toggle watch balance (5 seconds)

    ── WALLET ───────────────────────────────────────────
    /solwallet create                   Create new wallet
    /solwallet import <hex_key>         Import private key (hex 64 chars)
    /solwallet list                     List all wallets
    /solwallet export <address>         Export private key
    /solwallet remove <address>         Remove wallet

    ── DEVNET ───────────────────────────────────────────
    /solairdrop <address> [amount]      Request airdrop (devnet only)

    ── SOL TRANSFER ─────────────────────────────────────
    /solsend <from> <to> <sol_amount>   Transfer SOL

    ── TOKEN OPERATIONS ─────────────────────────────────
    /soltokensend <wallet> <src_ata> <dst_ata> <amount>   Transfer SPL token
    /solapprove <wallet> <token_acc> <delegate> <amount>  Approve delegate
    /solrevoke <wallet> <token_acc>                       Revoke approve
    /solburn <wallet> <token_acc> <mint> <amount>         Burn tokens
    /solcloseacc <wallet> <token_acc>                     Close token account

    ── CONTRACT / CUSTOM PROGRAM ────────────────────────
    /solcustom <wallet> <program_id> <hex_data>           Call custom program
    /solanchor <wallet> <program_id> <method> [hex_args]  Call Anchor program
    /solmemo <wallet> <text>                              Send memo on-chain
    /solmultitx <wallet>                                  Multi-instruction TX demo
    ---
]]

local sol = exports["solana-sdk"]

-- ---
-- INIT
-- ---
addEventHandler("onResourceStart", resourceRoot, function()
    sol:initClient({
        cluster = "devnet",
        commitment = "confirmed",
    })
end)

addEventHandler("onResourceStop", resourceRoot, function()
    sol:destroyClient()
end)

-- ---
-- /soltest - Run Ed25519 self-test (output ke debugscript 3)
-- ---
addCommandHandler("soltest", function(player)
    outputChatBox("#FF6600[Test] #FFFFFFRunning Ed25519 self-test... cek debugscript 3", player, 255, 255, 255, true)
    local results = sol:runSelfTest()
    if results then
        for _, line in ipairs(results) do
            if line:find("PASS") then
                outputChatBox("#00FF00[Test] " .. line, player, 255, 255, 255, true)
            elseif line:find("FAIL") then
                outputChatBox("#FF0000[Test] " .. line, player, 255, 255, 255, true)
            end
        end
    end
end)

-- ---
-- REQUEST QUEUE (tracks player per async request)
-- ---
local _pendingRequests = {}

local function savePlayer(key, player)
    _pendingRequests[key] = _pendingRequests[key] or {}
    table.insert(_pendingRequests[key], player)
end

local function getPlayer(key)
    if _pendingRequests[key] and #_pendingRequests[key] > 0 then
        return table.remove(_pendingRequests[key], 1)
    end
    return nil
end

-- ---
-- --- 1. NETWORK INFO ---
-- ---

-- /solhealth
addEvent("onSolHealthResult", true)
addEventHandler("onSolHealthResult", resourceRoot, function(result, err)
    local player = getPlayer("health")
    if not player then return end
    if err then
        outputChatBox("#FF0000[Solana] #FFFFFFCluster unhealthy: " .. tostring(err), player, 255, 255, 255, true)
        return
    end
    outputChatBox("#00FF00[Solana] #FFFFFFCluster health: " .. tostring(result), player, 255, 255, 255, true)
end)

addEvent("onSolVersionResult", true)
addEventHandler("onSolVersionResult", resourceRoot, function(result, err)
    local player = getPlayer("version")
    if not player then return end
    if err then return end
    outputChatBox("#00FF00[Solana] #FFFFFFVersion: " .. tostring(result["solana-core"]), player, 255, 255, 255, true)
end)

addCommandHandler("solhealth", function(player)
    savePlayer("health", player)
    savePlayer("version", player)
    sol:getHealth("onSolHealthResult", resourceRoot)
    sol:getVersion("onSolVersionResult", resourceRoot)
end)

-- /solslot
addEvent("onSolSlotResult", true)
addEventHandler("onSolSlotResult", resourceRoot, function(result, err)
    local player = getPlayer("slot")
    if not player then return end
    if err then
        outputChatBox("#FF0000[Solana] #FFFFFFError: " .. tostring(err), player, 255, 255, 255, true)
        return
    end
    outputChatBox("#00FF00[Solana] #FFFFFFCurrent Slot: " .. tostring(result), player, 255, 255, 255, true)
end)

addEvent("onSolEpochResult", true)
addEventHandler("onSolEpochResult", resourceRoot, function(info, err)
    local player = getPlayer("epoch")
    if not player then return end
    if err then return end
    outputChatBox("#00FF00[Solana] #FFFFFFEpoch: " .. tostring(info.epoch), player, 255, 255, 255, true)
    outputChatBox("#AAAAAA  Slot in Epoch: " .. tostring(info.slotIndex) .. "/" .. tostring(info.slotsInEpoch), player, 255, 255, 255, true)
    outputChatBox("#AAAAAA  Block Height: " .. tostring(info.blockHeight), player, 255, 255, 255, true)
end)

addCommandHandler("solslot", function(player)
    savePlayer("slot", player)
    savePlayer("epoch", player)
    sol:getSlot("onSolSlotResult", resourceRoot)
    sol:getEpochInfo("onSolEpochResult", resourceRoot)
end)

-- ---
-- --- 2. READ DATA ---
-- ---

-- /solbalance <address>
addEvent("onSolBalanceResult", true)
addEventHandler("onSolBalanceResult", resourceRoot, function(result, err)
    local player = getPlayer("balance")
    if not player then return end
    if err then
        outputChatBox("#FF0000[Solana] #FFFFFFError: " .. tostring(err), player, 255, 255, 255, true)
        return
    end
    outputChatBox("#00FF00[Solana] #FFFFFFBalance: " .. tostring(result.sol) .. " SOL", player, 255, 255, 255, true)
    outputChatBox("#00FF00[Solana] #FFFFFFLamports: " .. tostring(result.lamports), player, 255, 255, 255, true)
    outputChatBox("#00FF00[Solana] #FFFFFFSlot: " .. tostring(result.slot), player, 255, 255, 255, true)
end)

addCommandHandler("solbalance", function(player, cmd, address)
    if not address or address == "" then
        outputChatBox("#FF6600[Solana] #FFFFFFUsage: /solbalance <address>", player, 255, 255, 255, true)
        return
    end
    outputChatBox("#FF6600[Solana] #FFFFFFFetching balance...", player, 255, 255, 255, true)
    savePlayer("balance", player)
    sol:fetchBalance(address, "onSolBalanceResult", resourceRoot)
end)

-- /solaccount <address>
addEvent("onSolAccountResult", true)
addEventHandler("onSolAccountResult", resourceRoot, function(result, err)
    local player = getPlayer("account")
    if not player then return end
    if err then
        outputChatBox("#FF0000[Solana] #FFFFFFError: " .. tostring(err), player, 255, 255, 255, true)
        return
    end
    outputChatBox("#00FF00[Solana] #FFFFFFAccount Info:", player, 255, 255, 255, true)
    outputChatBox("#AAAAAA  Balance: " .. tostring(result.sol) .. " SOL", player, 255, 255, 255, true)
    outputChatBox("#AAAAAA  Owner: " .. tostring(result.owner), player, 255, 255, 255, true)
    outputChatBox("#AAAAAA  Executable: " .. tostring(result.executable), player, 255, 255, 255, true)
    outputChatBox("#AAAAAA  Slot: " .. tostring(result.slot), player, 255, 255, 255, true)
end)

addCommandHandler("solaccount", function(player, cmd, address)
    if not address or address == "" then
        outputChatBox("#FF6600[Solana] #FFFFFFUsage: /solaccount <address>", player, 255, 255, 255, true)
        return
    end
    outputChatBox("#FF6600[Solana] #FFFFFFFetching account info...", player, 255, 255, 255, true)
    savePlayer("account", player)
    sol:fetchAccount(address, "onSolAccountResult", resourceRoot)
end)

-- /soltokens <address>
addEvent("onSolTokensResult", true)
addEventHandler("onSolTokensResult", resourceRoot, function(tokens, err)
    local player = getPlayer("tokens")
    if not player then return end
    if err then
        outputChatBox("#FF0000[Solana] #FFFFFFError: " .. tostring(err), player, 255, 255, 255, true)
        return
    end
    if #tokens == 0 then
        outputChatBox("#FFFF00[Solana] #FFFFFFNo tokens found.", player, 255, 255, 255, true)
        return
    end
    outputChatBox("#00FF00[Solana] #FFFFFFFound " .. #tokens .. " tokens:", player, 255, 255, 255, true)
    for i, token in ipairs(tokens) do
        if i > 10 then
            outputChatBox("#FFFF00[Solana] #FFFFFF... and " .. (#tokens - 10) .. " more", player, 255, 255, 255, true)
            break
        end
        local tkName = token.symbol or token.name or token.mint
        outputChatBox("#AAAAAA  " .. tkName .. ": " .. tostring(token.uiAmount or token.amount), player, 255, 255, 255, true)
    end
end)

addCommandHandler("soltokens", function(player, cmd, address)
    if not address or address == "" then
        outputChatBox("#FF6600[Solana] #FFFFFFUsage: /soltokens <address>", player, 255, 255, 255, true)
        return
    end
    outputChatBox("#FF6600[Solana] #FFFFFFFetching tokens...", player, 255, 255, 255, true)
    savePlayer("tokens", player)
    sol:getTokensByOwner(address, nil, "onSolTokensResult", resourceRoot)
end)

-- /soltxhistory <address> [limit]
addEvent("onSolTxHistoryResult", true)
addEventHandler("onSolTxHistoryResult", resourceRoot, function(txs, err)
    local player = getPlayer("txhistory")
    if not player then return end
    if err then
        outputChatBox("#FF0000[Solana] #FFFFFFError: " .. tostring(err), player, 255, 255, 255, true)
        return
    end
    if not txs or #txs == 0 then
        outputChatBox("#FFFF00[Solana] #FFFFFFNo transactions.", player, 255, 255, 255, true)
        return
    end
    outputChatBox("#00FF00[Solana] #FFFFFF" .. #txs .. " recent transactions:", player, 255, 255, 255, true)
    for i, tx in ipairs(txs) do
        local sig = tx.signature
        local shortSig = sig:sub(1, 8) .. "..." .. sig:sub(-8)
        local status = tx.confirmationStatus or "unknown"
        local errMsg = tx.err and " (FAILED)" or ""
        outputChatBox("#AAAAAA  " .. i .. ". " .. shortSig .. " - " .. status .. errMsg, player, 255, 255, 255, true)
    end
end)

addCommandHandler("soltxhistory", function(player, cmd, address, limit)
    if not address or address == "" then
        outputChatBox("#FF6600[Solana] #FFFFFFUsage: /soltxhistory <address> [limit]", player, 255, 255, 255, true)
        return
    end
    limit = tonumber(limit) or 10
    outputChatBox("#FF6600[Solana] #FFFFFFFetching transactions...", player, 255, 255, 255, true)
    savePlayer("txhistory", player)
    sol:getTransactionHistory(address, { limit = limit }, "onSolTxHistoryResult", resourceRoot)
end)

-- /solwatch <address> (toggle on/off)
local activePlayerWatchers = {}

addEvent("onSolWatchBalanceResult", true)
addEventHandler("onSolWatchBalanceResult", resourceRoot, function(result, err)
    for playerName, _ in pairs(activePlayerWatchers) do
        local player = getPlayerFromName(playerName)
        if player then
            if err then
                outputChatBox("#FF0000[Watch] #FFFFFFError: " .. tostring(err), player, 255, 255, 255, true)
            elseif result then
                outputChatBox("#00CCFF[Watch] #FFFFFF" .. tostring(result.sol) .. " SOL (slot " .. tostring(result.slot) .. ")", player, 255, 255, 255, true)
            end
        end
    end
end)

addCommandHandler("solwatch", function(player, cmd, address)
    local playerName = getPlayerName(player)
    if activePlayerWatchers[playerName] then
        sol:stopWatcher(activePlayerWatchers[playerName])
        activePlayerWatchers[playerName] = nil
        outputChatBox("#FFFF00[Solana] #FFFFFFWatcher stopped.", player, 255, 255, 255, true)
        return
    end
    if not address or address == "" then
        outputChatBox("#FF6600[Solana] #FFFFFFUsage: /solwatch <address> (type again to stop)", player, 255, 255, 255, true)
        return
    end
    outputChatBox("#00FF00[Solana] #FFFFFFWatching balance... (/solwatch to stop))", player, 255, 255, 255, true)
    local watcherId = sol:watchBalance(address, 5000, "onSolWatchBalanceResult", resourceRoot)
    activePlayerWatchers[playerName] = watcherId
end)

addEventHandler("onPlayerQuit", root, function()
    local playerName = getPlayerName(source)
    if activePlayerWatchers[playerName] then
        sol:stopWatcher(activePlayerWatchers[playerName])
        activePlayerWatchers[playerName] = nil
    end
end)

-- ---
-- --- 3. WALLET MANAGEMENT ---
-- ---

addCommandHandler("solwallet", function(player, cmd, action, arg1)
    if not action then
        outputChatBox("#FF6600[Wallet] #FFFFFFCommands:", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  /solwallet create        - Create wallet (random key)", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  /solwallet phrase        - Create wallet + mnemonic 12 words", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  /solwallet import <key>  - Import dari hex/base58 key", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  /solwallet list          - List all wallets", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  /solwallet export <addr> - Export all formats", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  /solwallet remove <addr> - Remove wallet", player, 255, 255, 255, true)
        outputChatBox("#FF6600[Mnemonic] #FFFFFFCommands:", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  /solphrase               - Generate 12-word mnemonic", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  /solimport <12 words>    - Import dari mnemonic phrase", player, 255, 255, 255, true)
        return
    end

    if action == "create" then
        local address = sol:createWallet()
        if address then
            outputChatBox("#00FF00[Wallet] #FFFFFFCreated! Address: " .. address, player, 255, 255, 255, true)
        else
            outputChatBox("#FF0000[Wallet] #FFFFFFFailed to create wallet.", player, 255, 255, 255, true)
        end

    elseif action == "phrase" then
        outputChatBox("#FFFF00[Wallet] #FFFFFFGenerating mnemonic + deriving key (~2 seconds)...", player, 255, 255, 255, true)
        local mnemonic, address = sol:generateMnemonic(12)
        if mnemonic and address then
            outputChatBox("#00FF00[Wallet] #FFFFFFWallet created with mnemonic!", player, 255, 255, 255, true)
            outputChatBox("#00FF00[Wallet] #FFFFFFAddress: " .. address, player, 255, 255, 255, true)
            outputChatBox("#FF6600[Wallet] #FFFFFFMnemonic Phrase (SIMPAN BAIK-BAIK!):", player, 255, 255, 255, true)
            outputChatBox("#FFFFFF" .. mnemonic, player, 255, 255, 255, true)
            outputChatBox("#FF0000[Wallet] #FFFFFFPhrase ini bisa import ke Phantom/Solflare!", player, 255, 255, 255, true)
        else
            outputChatBox("#FF0000[Wallet] #FFFFFFFailed to generate mnemonic.", player, 255, 255, 255, true)
        end

    elseif action == "import" then
        if not arg1 or arg1 == "" then
            outputChatBox("#FF6600[Wallet] #FFFFFFUsage: /solwallet import <base58_or_hex_key>", player, 255, 255, 255, true)
            return
        end
        local address, err = sol:importWallet(arg1)
        if address then
            outputChatBox("#00FF00[Wallet] #FFFFFFImported! Address: " .. address, player, 255, 255, 255, true)
        else
            outputChatBox("#FF0000[Wallet] #FFFFFFFailed: " .. tostring(err), player, 255, 255, 255, true)
        end

    elseif action == "list" then
        local wallets = sol:listWallets()
        if not wallets or #wallets == 0 then
            outputChatBox("#FFFF00[Wallet] #FFFFFFNo wallets.", player, 255, 255, 255, true)
            return
        end
        outputChatBox("#00FF00[Wallet] #FFFFFF" .. #wallets .. " wallet:", player, 255, 255, 255, true)
        for i, addr in ipairs(wallets) do
            outputChatBox("#AAAAAA  " .. i .. ". " .. addr, player, 255, 255, 255, true)
        end

    elseif action == "export" then
        if not arg1 then
            outputChatBox("#FF6600[Wallet] #FFFFFFUsage: /solwallet export <address>", player, 255, 255, 255, true)
            return
        end
        -- Show ALL formats
        outputChatBox("#FF6600[Export] #FFFFFF=== ALL FORMATS ===", player, 255, 255, 255, true)

        -- Mnemonic (if available)
        local mnemonic = sol:exportMnemonic(arg1)
        if mnemonic then
            outputChatBox("#00FF00[Mnemonic] #FFFFFFPhrase (Phantom/Solflare import):", player, 255, 255, 255, true)
            outputChatBox("#FFFFFF" .. mnemonic, player, 255, 255, 255, true)
        end

        -- Base58 format (Phantom)
        local phantomKey, err = sol:exportWalletPhantom(arg1)
        if phantomKey then
            outputChatBox("#00FF00[Base58] #FFFFFFPhantom/Solflare Import Private Key:", player, 255, 255, 255, true)
            outputChatBox("#FFFFFF" .. phantomKey, player, 255, 255, 255, true)
        end

        -- JSON array (Solana CLI)
        local cliKey = sol:exportWalletCLI(arg1)
        if cliKey then
            outputChatBox("#00FF00[JSON] #FFFFFFSolana CLI format (id.json):", player, 255, 255, 255, true)
            outputChatBox("#FFFFFF" .. cliKey, player, 255, 255, 255, true)
        end

        -- Hex
        local hexKey = sol:exportWalletHex(arg1)
        if hexKey then
            outputChatBox("#00FF00[Hex] #FFFFFFSeed hex (32 bytes):", player, 255, 255, 255, true)
            outputChatBox("#FFFFFF" .. hexKey, player, 255, 255, 255, true)
        end

        if not phantomKey and not hexKey then
            outputChatBox("#FF0000[Export] #FFFFFFError: " .. tostring(err), player, 255, 255, 255, true)
        else
            outputChatBox("#FF0000[Export] #FFFFFFDO NOT share key/phrase with anyone!", player, 255, 255, 255, true)
        end

    elseif action == "remove" then
        if not arg1 then
            outputChatBox("#FF6600[Wallet] #FFFFFFUsage: /solwallet remove <address>", player, 255, 255, 255, true)
            return
        end
        if sol:removeWallet(arg1) then
            outputChatBox("#00FF00[Wallet] #FFFFFFRemoved.", player, 255, 255, 255, true)
        else
            outputChatBox("#FF0000[Wallet] #FFFFFFWallet not found.", player, 255, 255, 255, true)
        end
    end
end)

-- ---
-- /solphrase - Generate mnemonic wallet (shortcut)
-- ---
addCommandHandler("solphrase", function(player, cmd, wordCount)
    wordCount = tonumber(wordCount) or 12
    if wordCount ~= 12 and wordCount ~= 24 then
        outputChatBox("#FF6600[Mnemonic] #FFFFFFUsage: /solphrase [12|24]", player, 255, 255, 255, true)
        return
    end
    outputChatBox("#FFFF00[Mnemonic] #FFFFFFGenerating " .. wordCount .. "-word mnemonic (~2 seconds)...", player, 255, 255, 255, true)
    local mnemonic, address = sol:generateMnemonic(wordCount)
    if mnemonic and address then
        outputChatBox("#00FF00[Mnemonic] #FFFFFFAddress: " .. address, player, 255, 255, 255, true)
        outputChatBox("#FF6600[Mnemonic] #FFFFFFPhrase (SIMPAN!):", player, 255, 255, 255, true)
        outputChatBox("#FFFFFF" .. mnemonic, player, 255, 255, 255, true)
        outputChatBox("#FFFF00[Mnemonic] #FFFFFFImport ke Phantom: Settings > Import Wallet > Recovery Phrase", player, 255, 255, 255, true)
    else
        outputChatBox("#FF0000[Mnemonic] #FFFFFFFailed.", player, 255, 255, 255, true)
    end
end)

-- ---
-- /solimport <12 or 24 words> - Import from mnemonic phrase
-- ---
addCommandHandler("solimport", function(player, cmd, ...)
    local words = {...}
    if #words < 12 then
        outputChatBox("#FF6600[Mnemonic] #FFFFFFUsage: /solimport word1 word2 word3 ... word12", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  Paste 12 or 24 words from Phantom/Solflare", player, 255, 255, 255, true)
        return
    end

    local mnemonic = table.concat(words, " ")
    outputChatBox("#FFFF00[Mnemonic] #FFFFFFDeriving wallet dari phrase (~2 seconds)...", player, 255, 255, 255, true)

    local address, _, err = sol:importFromMnemonic(mnemonic)
    if address then
        outputChatBox("#00FF00[Mnemonic] #FFFFFFImported! Address: " .. address, player, 255, 255, 255, true)
        outputChatBox("#FFFF00[Mnemonic] #FFFFFFAddress should match Phantom/Solflare", player, 255, 255, 255, true)
    else
        outputChatBox("#FF0000[Mnemonic] #FFFFFFFailed: " .. tostring(err), player, 255, 255, 255, true)
    end
end)

-- ---
-- --- 4. AIRDROP (DEVNET) ---
-- ---

addEvent("onSolAirdropResult", true)
addEventHandler("onSolAirdropResult", resourceRoot, function(result, err)
    local player = getPlayer("airdrop")
    if not player then return end
    if err then
        outputChatBox("#FF0000[Airdrop] #FFFFFFFailed: " .. tostring(err), player, 255, 255, 255, true)
        return
    end
    outputChatBox("#00FF00[Airdrop] #FFFFFFSuccess! Sig: " .. tostring(result), player, 255, 255, 255, true)
end)

addCommandHandler("solairdrop", function(player, cmd, address, amount)
    if not address or address == "" then
        outputChatBox("#FF6600[Airdrop] #FFFFFFUsage: /solairdrop <address> [sol_amount]", player, 255, 255, 255, true)
        return
    end
    amount = tonumber(amount) or 1
    outputChatBox("#FF6600[Airdrop] #FFFFFFRequesting " .. amount .. " SOL...", player, 255, 255, 255, true)
    savePlayer("airdrop", player)
    sol:requestAirdrop(address, amount, "onSolAirdropResult", resourceRoot)
end)

-- ---
-- --- 5. SOL TRANSFER (SIGN + SEND) ---
-- ---

addEvent("onSolTransferResult", true)
addEventHandler("onSolTransferResult", resourceRoot, function(result, err)
    local player = getPlayer("transfer")
    if not player then return end
    if err then
        outputChatBox("#FF0000[Transfer] #FFFFFFFailed: " .. tostring(err), player, 255, 255, 255, true)
        return
    end
    outputChatBox("#00FF00[Transfer] #FFFFFFSuccess!", player, 255, 255, 255, true)
    outputChatBox("#00FF00[Transfer] #FFFFFFSignature: " .. tostring(result.signature), player, 255, 255, 255, true)
    outputChatBox("#AAAAAA  " .. tostring(result.from) .. " -> " .. tostring(result.to), player, 255, 255, 255, true)
    outputChatBox("#AAAAAA  Amount: " .. tostring(result.amount) .. " SOL", player, 255, 255, 255, true)
end)

addCommandHandler("solsend", function(player, cmd, fromAddr, toAddr, amount)
    if not fromAddr or not toAddr or not amount then
        outputChatBox("#FF6600[Transfer] #FFFFFFUsage: /solsend <from_wallet> <to_address> <sol_amount>", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  Example: /solsend AbC123... XyZ789... 0.5", player, 255, 255, 255, true)
        return
    end
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        outputChatBox("#FF0000[Transfer] #FFFFFFAmount must be > 0", player, 255, 255, 255, true)
        return
    end
    outputChatBox("#FF6600[Transfer] #FFFFFFSigning " .. amount .. " SOL... (~0.5 seconds)", player, 255, 255, 255, true)
    savePlayer("transfer", player)
    sol:transferSOL(fromAddr, toAddr, amount, "onSolTransferResult", resourceRoot)
end)

-- ---
-- --- 6. TOKEN OPERATIONS ---
-- ---

-- Generic event handler for all token operations
addEvent("onSolTokenOpResult", true)
addEventHandler("onSolTokenOpResult", resourceRoot, function(result, err)
    local player = getPlayer("tokenop")
    if not player then return end
    if err then
        outputChatBox("#FF0000[Token] #FFFFFFFailed: " .. tostring(err), player, 255, 255, 255, true)
        return
    end
    outputChatBox("#00FF00[Token] #FFFFFFSuccess! Sig: " .. tostring(result.signature), player, 255, 255, 255, true)
end)

-- /soltokensend <wallet> <source_token_account> <dest_token_account> <raw_amount>
addCommandHandler("soltokensend", function(player, cmd, wallet, srcAta, dstAta, amount)
    if not wallet or not srcAta or not dstAta or not amount then
        outputChatBox("#FF6600[Token] #FFFFFFUsage: /soltokensend <wallet> <src_token_acc> <dst_token_acc> <raw_amount>", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  raw_amount = tanpa decimals. Untuk 1 token (6 decimals) = 1000000", player, 255, 255, 255, true)
        return
    end
    amount = tonumber(amount)
    if not amount then
        outputChatBox("#FF0000[Token] #FFFFFFAmount must be a number", player, 255, 255, 255, true)
        return
    end
    outputChatBox("#FF6600[Token] #FFFFFFSending token... (~0.5 seconds)", player, 255, 255, 255, true)
    savePlayer("tokenop", player)
    sol:transferToken(wallet, srcAta, dstAta, amount, "onSolTokenOpResult", resourceRoot)
end)

-- /solapprove <wallet> <token_account> <delegate_address> <raw_amount>
addCommandHandler("solapprove", function(player, cmd, wallet, tokenAcc, delegate, amount)
    if not wallet or not tokenAcc or not delegate or not amount then
        outputChatBox("#FF6600[Token] #FFFFFFUsage: /solapprove <wallet> <token_acc> <delegate> <raw_amount>", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  Izinkan delegate untuk spend token kamu sampai raw_amount", player, 255, 255, 255, true)
        return
    end
    amount = tonumber(amount)
    if not amount then
        outputChatBox("#FF0000[Token] #FFFFFFAmount must be a number", player, 255, 255, 255, true)
        return
    end
    outputChatBox("#FF6600[Token] #FFFFFFApproving delegate... (~0.5 seconds)", player, 255, 255, 255, true)
    savePlayer("tokenop", player)
    sol:approveToken(wallet, tokenAcc, delegate, amount, "onSolTokenOpResult", resourceRoot)
end)

-- /solrevoke <wallet> <token_account>
addCommandHandler("solrevoke", function(player, cmd, wallet, tokenAcc)
    if not wallet or not tokenAcc then
        outputChatBox("#FF6600[Token] #FFFFFFUsage: /solrevoke <wallet> <token_acc>", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  Revoke all approvals from token account", player, 255, 255, 255, true)
        return
    end
    outputChatBox("#FF6600[Token] #FFFFFFRevoking... (~0.5 seconds)", player, 255, 255, 255, true)
    savePlayer("tokenop", player)
    sol:revokeToken(wallet, tokenAcc, "onSolTokenOpResult", resourceRoot)
end)

-- /solburn <wallet> <token_account> <mint> <raw_amount>
addCommandHandler("solburn", function(player, cmd, wallet, tokenAcc, mint, amount)
    if not wallet or not tokenAcc or not mint or not amount then
        outputChatBox("#FF6600[Token] #FFFFFFUsage: /solburn <wallet> <token_acc> <mint> <raw_amount>", player, 255, 255, 255, true)
        return
    end
    amount = tonumber(amount)
    if not amount then
        outputChatBox("#FF0000[Token] #FFFFFFAmount must be a number", player, 255, 255, 255, true)
        return
    end
    outputChatBox("#FF6600[Token] #FFFFFFBurning tokens... (~0.5 seconds)", player, 255, 255, 255, true)
    savePlayer("tokenop", player)
    sol:burnToken(wallet, tokenAcc, mint, amount, "onSolTokenOpResult", resourceRoot)
end)

-- /solcloseacc <wallet> <token_account>
addCommandHandler("solcloseacc", function(player, cmd, wallet, tokenAcc)
    if not wallet or not tokenAcc then
        outputChatBox("#FF6600[Token] #FFFFFFUsage: /solcloseacc <wallet> <token_acc>", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  Close token account, reclaim rent SOL", player, 255, 255, 255, true)
        return
    end
    outputChatBox("#FF6600[Token] #FFFFFFClosing account... (~0.5 seconds)", player, 255, 255, 255, true)
    savePlayer("tokenop", player)
    sol:closeTokenAccount(wallet, tokenAcc, "onSolTokenOpResult", resourceRoot)
end)

-- ---
-- --- 7. CONTRACT / CUSTOM PROGRAM ---
-- ---

addEvent("onSolCustomTxResult", true)
addEventHandler("onSolCustomTxResult", resourceRoot, function(result, err)
    local player = getPlayer("customtx")
    if not player then return end
    if err then
        outputChatBox("#FF0000[Contract] #FFFFFFFailed: " .. tostring(err), player, 255, 255, 255, true)
        return
    end
    outputChatBox("#00FF00[Contract] #FFFFFFSuccess! Sig: " .. tostring(result.signature), player, 255, 255, 255, true)
end)

-- /solcustom <wallet> <program_id> <hex_data>
-- Example: /solcustom AbC123... MyProgram123... 0102030405
addCommandHandler("solcustom", function(player, cmd, wallet, programId, hexData)
    if not wallet or not programId then
        outputChatBox("#FF6600[Contract] #FFFFFFUsage: /solcustom <wallet> <program_id> [hex_data]", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  Send instruction to any program", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  Example: /solcustom WalletAddr ProgramId 0102030405", player, 255, 255, 255, true)
        return
    end

    -- Parse hex data ke byte array
    local data = {}
    if hexData and hexData ~= "" then
        for i = 1, #hexData, 2 do
            local byte = tonumber(hexData:sub(i, i + 1), 16)
            if byte then
                data[#data + 1] = byte
            end
        end
    end

    -- Build instruction: wallet sebagai signer + writable account
    local instructions = {
        CustomProgram.instruction(programId, {
            {wallet, true, true},  -- signer, writable
        }, data)
    }

    outputChatBox("#FF6600[Contract] #FFFFFFSending custom instruction... (~0.5 seconds)", player, 255, 255, 255, true)
    savePlayer("customtx", player)
    sol:sendCustomTransaction(wallet, instructions, {wallet}, "onSolCustomTxResult", resourceRoot)
end)

-- /solanchor <wallet> <program_id> <method_name> [hex_args]
-- Example: /solanchor AbC123... MyAnchor123... initialize 0a00000000000000
addCommandHandler("solanchor", function(player, cmd, wallet, programId, methodName, hexArgs)
    if not wallet or not programId or not methodName then
        outputChatBox("#FF6600[Contract] #FFFFFFUsage: /solanchor <wallet> <program_id> <method_name> [hex_args]", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  Call method on Anchor program", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  Discriminator di-hash otomatis dari nama method", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  Example: /solanchor WalletAddr ProgramId initialize", player, 255, 255, 255, true)
        return
    end

    -- Parse hex args
    local argBytes = nil
    if hexArgs and hexArgs ~= "" then
        argBytes = {}
        for i = 1, #hexArgs, 2 do
            local byte = tonumber(hexArgs:sub(i, i + 1), 16)
            if byte then argBytes[#argBytes + 1] = byte end
        end
    end

    local instructions = {
        CustomProgram.anchorInstruction(programId, {
            {wallet, true, true},
        }, methodName, argBytes)
    }

    outputChatBox("#FF6600[Contract] #FFFFFFCalling " .. methodName .. "()... (~0.5 seconds)", player, 255, 255, 255, true)
    savePlayer("customtx", player)
    sol:sendCustomTransaction(wallet, instructions, {wallet}, "onSolCustomTxResult", resourceRoot)
end)

-- /solmemo <wallet> <text...>
-- Send memo on-chain
addCommandHandler("solmemo", function(player, cmd, wallet, ...)
    local args = {...}
    if not wallet or #args == 0 then
        outputChatBox("#FF6600[Memo] #FFFFFFUsage: /solmemo <wallet> <text>", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  Send on-chain memo (stored on blockchain forever)", player, 255, 255, 255, true)
        return
    end

    local text = table.concat(args, " ")

    local instructions = {
        MemoProgram.memo(wallet, text)
    }

    outputChatBox("#FF6600[Memo] #FFFFFFSending memo: \"" .. text .. "\" (~0.5 seconds)", player, 255, 255, 255, true)
    savePlayer("customtx", player)
    sol:sendCustomTransaction(wallet, instructions, {wallet}, "onSolCustomTxResult", resourceRoot)
end)

-- /solmultitx <wallet>
-- Demo: multiple instructions in 1 transaction
-- (SOL transfer + memo in 1 atomic transaction)
addCommandHandler("solmultitx", function(player, cmd, wallet, toAddr, amount)
    if not wallet or not toAddr or not amount then
        outputChatBox("#FF6600[MultiTX] #FFFFFFUsage: /solmultitx <wallet> <to_address> <sol_amount>", player, 255, 255, 255, true)
        outputChatBox("#AAAAAA  Demo: Transfer SOL + Memo dalam 1 transaksi", player, 255, 255, 255, true)
        return
    end

    amount = tonumber(amount)
    if not amount or amount <= 0 then
        outputChatBox("#FF0000[MultiTX] #FFFFFFAmount must be > 0", player, 255, 255, 255, true)
        return
    end

    local lamports = math.floor(amount * 1000000000)

    -- 2 instructions in 1 transaction!
    local instructions = {
        -- Instruction 1: Transfer SOL
        SystemProgram.transfer(wallet, toAddr, lamports),
        -- Instruction 2: Add memo
        MemoProgram.memo(wallet, "MTA:SA Solana SDK transfer " .. tostring(amount) .. " SOL"),
    }

    outputChatBox("#FF6600[MultiTX] #FFFFFFSending multi-instruction TX... (~0.5 seconds)", player, 255, 255, 255, true)
    savePlayer("customtx", player)
    sol:sendCustomTransaction(wallet, instructions, {wallet}, "onSolCustomTxResult", resourceRoot)
end)

-- ---
-- --- 8. QUICK START GUIDE ---
-- ---

addCommandHandler("solhelp", function(player)
    outputChatBox("#FF6600--- SOLANA SDK - QUICK START ---", player, 255, 255, 255, true)
    outputChatBox("#FFFFFF", player, 255, 255, 255, true)
    outputChatBox("#00FF00Step 1: #FFFFFFCreate wallet", player, 255, 255, 255, true)
    outputChatBox("#AAAAAA  /solwallet create", player, 255, 255, 255, true)
    outputChatBox("#FFFFFF", player, 255, 255, 255, true)
    outputChatBox("#00FF00Step 2: #FFFFFFAirdrop devnet SOL", player, 255, 255, 255, true)
    outputChatBox("#AAAAAA  /solairdrop <your_address> 2", player, 255, 255, 255, true)
    outputChatBox("#FFFFFF", player, 255, 255, 255, true)
    outputChatBox("#00FF00Step 3: #FFFFFFCheck balance", player, 255, 255, 255, true)
    outputChatBox("#AAAAAA  /solbalance <your_address>", player, 255, 255, 255, true)
    outputChatBox("#FFFFFF", player, 255, 255, 255, true)
    outputChatBox("#00FF00Step 4: #FFFFFFTransfer SOL", player, 255, 255, 255, true)
    outputChatBox("#AAAAAA  /solsend <your_address> <target_address> 0.1", player, 255, 255, 255, true)
    outputChatBox("#FFFFFF", player, 255, 255, 255, true)
    outputChatBox("#00FF00Lainnya:", player, 255, 255, 255, true)
    outputChatBox("#AAAAAA  /solhealth /solslot /soltokens /soltxhistory", player, 255, 255, 255, true)
    outputChatBox("#AAAAAA  /solmemo /solmultitx /solanchor /solcustom", player, 255, 255, 255, true)
    outputChatBox("#AAAAAA  /solapprove /solrevoke /solburn /solcloseacc", player, 255, 255, 255, true)
    outputChatBox("#FF6600---", player, 255, 255, 255, true)
end)
