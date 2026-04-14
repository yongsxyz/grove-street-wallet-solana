-- https://github.com/yongsxyz
--[[
    Grove Street Wallet - Client Exports
    Async result dikirim via triggerEvent (bukan callback function)

    Usage from other resources:
        exports["solana-sdk"]:fetchBalance(address, "onMyEvent", resourceRoot)

        addEvent("onMyEvent", true)
        addEventHandler("onMyEvent", resourceRoot, function(result, err) ... end)
]]

-- ---
-- Internal State
-- ---
local _rpc = nil
local _status = "not_initialized"
local _endpoint = nil
local _commitment = "confirmed"
local _activeWatchers = {}
local _watcherIdCounter = 0

-- ---
-- Trigger async result back to caller
-- ---
local function fireCallback(eventName, eventSource, ...)
    if eventName and eventSource then
        triggerEvent(eventName, eventSource, ...)
    end
end

-- ---
-- Init / Config
-- ---

function initClient(config)
    config = config or {}
    local endpoint = config.endpoint or config.cluster or "devnet"
    _commitment = config.commitment or "confirmed"

    _rpc = SolanaRPC.new(endpoint, {
        commitment = _commitment,
        timeout = config.timeout,
    })
    _endpoint = _rpc.endpoint
    _status = "connecting"

    _rpc:getLatestBlockhash(function(result, err)
        if err then
            _status = "error"
            outputDebugString("[solana-sdk] Connection failed: " .. tostring(err), 1)
        else
            _status = "ready"
            outputDebugString("[solana-sdk] Connected to " .. _endpoint)
        end
    end)

    return true
end

function getClientStatus()
    return _status, _endpoint, _commitment
end

function destroyClient()
    for id, data in pairs(_activeWatchers) do
        if data.timer and isTimer(data.timer) then
            killTimer(data.timer)
        end
    end
    _activeWatchers = {}
    _rpc = nil
    _status = "not_initialized"
    outputDebugString("[solana-sdk] Client destroyed")
    return true
end

local function ensureReady(eventName, eventSource)
    if not _rpc then
        fireCallback(eventName, eventSource, nil, "Client not initialized. Call initClient() first.")
        return false
    end
    return true
end

-- ---
-- Account Actions
-- ---

function fetchBalance(address, eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end

    if not Base58.isValid(address) then
        fireCallback(eventName, eventSource, nil, "Invalid Solana address")
        return
    end

    _rpc:getBalance(address, function(result, rpcErr)
        if rpcErr then
            fireCallback(eventName, eventSource, nil, rpcErr)
            return
        end
        fireCallback(eventName, eventSource, {
            lamports = result.value,
            sol = SolanaRPC.lamportsToSol(result.value),
            slot = result.context and result.context.slot,
        })
    end)
end

function fetchAccount(address, eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end

    if not Base58.isValid(address) then
        fireCallback(eventName, eventSource, nil, "Invalid Solana address")
        return
    end

    _rpc:getAccountInfo(address, function(result, rpcErr)
        if rpcErr then
            fireCallback(eventName, eventSource, nil, rpcErr)
            return
        end

        local value = result.value
        if not value then
            fireCallback(eventName, eventSource, nil, "Account not found")
            return
        end

        fireCallback(eventName, eventSource, {
            lamports = value.lamports,
            sol = SolanaRPC.lamportsToSol(value.lamports),
            owner = value.owner,
            executable = value.executable,
            rentEpoch = value.rentEpoch,
            slot = result.context and result.context.slot,
        })
    end)
end

function getTokenBalance(tokenAccount, eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end

    _rpc:getTokenAccountBalance(tokenAccount, function(result, rpcErr)
        if rpcErr then
            fireCallback(eventName, eventSource, nil, rpcErr)
            return
        end
        fireCallback(eventName, eventSource, {
            amount = result.value.amount,
            decimals = result.value.decimals,
            uiAmount = result.value.uiAmount,
            uiAmountString = result.value.uiAmountString,
        })
    end)
end

function getTokensByOwner(owner, mintOrProgram, eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end

    TokenRegistry.fetchJupiterList()

    local net = _endpoint and (_endpoint:find("mainnet") and "mainnet-beta" or (_endpoint:find("testnet") and "testnet" or "devnet")) or "devnet"

    local function parseTokens(result, programId)
        local out = {}
        if result and result.value then
            for _, account in ipairs(result.value) do
                local parsed = account.account
                    and account.account.data
                    and account.account.data.parsed
                    and account.account.data.parsed.info
                if parsed then
                    local mint = parsed.mint
                    local info = TokenRegistry.lookup(mint, net)
                    out[#out + 1] = {
                        pubkey = account.pubkey,
                        mint = mint,
                        symbol = info and info.symbol or nil,
                        name = info and info.name or nil,
                        icon = info and info.icon or nil,
                        owner = parsed.owner,
                        tokenProgram = programId,
                        amount = parsed.tokenAmount and parsed.tokenAmount.amount,
                        decimals = parsed.tokenAmount and parsed.tokenAmount.decimals,
                        uiAmount = parsed.tokenAmount and parsed.tokenAmount.uiAmount,
                    }
                end
            end
        end
        return out
    end

    -- If specific mint, query just that
    if mintOrProgram and #mintOrProgram > 30 then
        _rpc:getTokenAccountsByOwner(owner, { mint = mintOrProgram }, function(result, rpcErr)
            if rpcErr then fireCallback(eventName, eventSource, nil, rpcErr); return end
            fireCallback(eventName, eventSource, parseTokens(result, ""))
        end)
        return
    end

    -- Query BOTH Token Program AND Token-2022, merge results
    local allTokens = {}
    local done = 0

    _rpc:getTokenAccountsByOwner(owner, { programId = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA" }, function(result, rpcErr)
        if not rpcErr then
            for _, t in ipairs(parseTokens(result, "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")) do
                allTokens[#allTokens + 1] = t
            end
        end
        done = done + 1
        if done == 2 then fireCallback(eventName, eventSource, allTokens) end
    end)

    _rpc:getTokenAccountsByOwner(owner, { programId = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb" }, function(result, rpcErr)
        if not rpcErr then
            for _, t in ipairs(parseTokens(result, "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb")) do
                allTokens[#allTokens + 1] = t
            end
        end
        done = done + 1
        if done == 2 then fireCallback(eventName, eventSource, allTokens) end
    end)
end

-- ---
-- Transaction Actions
-- ---

function getTransactionHistory(address, options, eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end

    options = options or {}
    _rpc:getSignaturesForAddress(address, function(result, rpcErr)
        if rpcErr then
            fireCallback(eventName, eventSource, nil, rpcErr)
            return
        end
        fireCallback(eventName, eventSource, result)
    end, {
        limit = options.limit or 10,
        before = options.before,
    })
end

function getTransaction(signature, eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end

    _rpc:getTransaction(signature, function(result, rpcErr)
        if rpcErr then
            fireCallback(eventName, eventSource, nil, rpcErr)
            return
        end
        fireCallback(eventName, eventSource, result)
    end)
end

function sendTransaction(signedTxBase64, options, eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end

    _rpc:sendTransaction(signedTxBase64, function(result, rpcErr)
        if rpcErr then
            fireCallback(eventName, eventSource, nil, rpcErr)
            return
        end
        fireCallback(eventName, eventSource, result)
    end, options)
end

function getLatestBlockhash(eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end

    _rpc:getLatestBlockhash(function(result, rpcErr)
        if rpcErr then
            fireCallback(eventName, eventSource, nil, rpcErr)
            return
        end
        fireCallback(eventName, eventSource, {
            blockhash = result.value.blockhash,
            lastValidBlockHeight = result.value.lastValidBlockHeight,
        })
    end)
end

-- ---
-- Network / Cluster Info
-- ---

function getSlot(eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end
    _rpc:getSlot(function(result, rpcErr)
        if rpcErr then
            fireCallback(eventName, eventSource, nil, rpcErr)
            return
        end
        fireCallback(eventName, eventSource, result)
    end)
end

function getBlockHeight(eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end
    _rpc:getBlockHeight(function(result, rpcErr)
        if rpcErr then
            fireCallback(eventName, eventSource, nil, rpcErr)
            return
        end
        fireCallback(eventName, eventSource, result)
    end)
end

function getEpochInfo(eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end
    _rpc:getEpochInfo(function(result, rpcErr)
        if rpcErr then
            fireCallback(eventName, eventSource, nil, rpcErr)
            return
        end
        fireCallback(eventName, eventSource, result)
    end)
end

function getHealth(eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end
    _rpc:getHealth(function(result, rpcErr)
        if rpcErr then
            fireCallback(eventName, eventSource, nil, rpcErr)
            return
        end
        fireCallback(eventName, eventSource, result)
    end)
end

function getVersion(eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end
    _rpc:getVersion(function(result, rpcErr)
        if rpcErr then
            fireCallback(eventName, eventSource, nil, rpcErr)
            return
        end
        fireCallback(eventName, eventSource, result)
    end)
end

-- ---
-- Airdrop (devnet/testnet)
-- ---

function requestAirdrop(address, solAmount, eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end

    local lamports = SolanaRPC.solToLamports(solAmount)
    _rpc:requestAirdrop(address, lamports, function(result, rpcErr)
        if rpcErr then
            fireCallback(eventName, eventSource, nil, rpcErr)
            return
        end
        fireCallback(eventName, eventSource, result)
    end)
end

-- ---
-- Watchers (polling via triggerEvent)
-- ---

function watchBalance(address, intervalMs, eventName, eventSource)
    if not _rpc then return nil end

    intervalMs = intervalMs or 5000
    _watcherIdCounter = _watcherIdCounter + 1
    local watcherId = "balance_" .. tostring(_watcherIdCounter)

    local function poll()
        _rpc:getBalance(address, function(result, rpcErr)
            if rpcErr then
                fireCallback(eventName, eventSource, nil, rpcErr)
                return
            end
            fireCallback(eventName, eventSource, {
                lamports = result.value,
                sol = SolanaRPC.lamportsToSol(result.value),
                slot = result.context and result.context.slot,
            })
        end)
    end

    local timer = setTimer(poll, intervalMs, 0)
    poll()

    _activeWatchers[watcherId] = {
        timer = timer,
        type = "balance",
        address = address,
    }

    return watcherId
end

function watchSignature(sig, intervalMs, eventName, eventSource)
    if not _rpc then return nil end

    intervalMs = intervalMs or 2000
    _watcherIdCounter = _watcherIdCounter + 1
    local watcherId = "sig_" .. tostring(_watcherIdCounter)

    local timer
    local function poll()
        _rpc:getSignatureStatuses({ sig }, function(result, rpcErr)
            if rpcErr then
                fireCallback(eventName, eventSource, nil, rpcErr)
                return
            end
            local status = result and result.value and result.value[1]
            if status then
                fireCallback(eventName, eventSource, status)
                if status.confirmationStatus == "confirmed" or status.confirmationStatus == "finalized" then
                    stopWatcher(watcherId)
                end
            end
        end, { searchTransactionHistory = true })
    end

    timer = setTimer(poll, intervalMs, 0)
    poll()

    _activeWatchers[watcherId] = {
        timer = timer,
        type = "signature",
        signature = sig,
    }

    return watcherId
end

function stopWatcher(watcherId)
    if not watcherId then return false end
    local watcher = _activeWatchers[watcherId]
    if watcher then
        if watcher.timer and isTimer(watcher.timer) then
            killTimer(watcher.timer)
        end
        _activeWatchers[watcherId] = nil
        return true
    end
    return false
end

-- ---
-- Utility (sync, returns immediately)
-- ---

function runSelfTest()
    return Ed25519.selfTest()
end

function lamportsToSol(lamports)
    return SolanaRPC.lamportsToSol(lamports)
end

function solToLamports(sol)
    return SolanaRPC.solToLamports(sol)
end

function isValidAddress(address)
    return Base58.isValidSolanaAddress(address)
end

-- ---
-- High-Level Transaction Functions
-- Build + sign + send in one call
-- ---

-- Transfer SOL to destination address
-- fromAddress = imported wallet address
-- toAddress = destination base58 address
-- solAmount = SOL amount (e.g. 0.5)
-- eventName, eventSource = for async result callback
function transferSOL(fromAddress, toAddress, solAmount, eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end

    if not hasWallet(fromAddress) then
        fireCallback(eventName, eventSource, nil, "Wallet not found: " .. tostring(fromAddress))
        return
    end

    local lamports = SolanaRPC.solToLamports(solAmount)

    -- Step 1: Get recent blockhash
    _rpc:getLatestBlockhash(function(result, err)
        if err then
            fireCallback(eventName, eventSource, nil, "Failed to get blockhash: " .. tostring(err))
            return
        end

        local blockhash = result.value.blockhash

        -- Step 2: Build, sign, encode transaction
        local encoded, txErr = buildAndSignTransfer(fromAddress, toAddress, lamports, blockhash)
        if not encoded then
            fireCallback(eventName, eventSource, nil, "Failed to build tx: " .. tostring(txErr))
            return
        end

        -- Step 3: Send transaction
        _rpc:sendTransaction(encoded, function(sendResult, sendErr)
            if sendErr then
                fireCallback(eventName, eventSource, nil, "Failed to send tx: " .. tostring(sendErr))
                return
            end
            fireCallback(eventName, eventSource, {
                signature = sendResult,
                from = fromAddress,
                to = toAddress,
                amount = solAmount,
                lamports = lamports,
            })
        end)
    end)
end

-- Transfer SPL Token
function transferToken(fromWallet, sourceTokenAccount, destTokenAccount, amount, eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end

    if not hasWallet(fromWallet) then
        fireCallback(eventName, eventSource, nil, "Wallet not found: " .. tostring(fromWallet))
        return
    end

    _rpc:getLatestBlockhash(function(result, err)
        if err then
            fireCallback(eventName, eventSource, nil, "Failed to get blockhash: " .. tostring(err))
            return
        end

        local blockhash = result.value.blockhash

        local tx = SolTransaction.new()
        tx:setFeePayer(fromWallet)
        tx:setRecentBlockhash(blockhash)
        tx:addSigner(fromWallet)
        tx:addInstruction(TokenProgram.transfer(sourceTokenAccount, destTokenAccount, fromWallet, amount))

        local encoded, txErr = tx:signAndEncode()
        if not encoded then
            fireCallback(eventName, eventSource, nil, "Failed to build tx: " .. tostring(txErr))
            return
        end

        _rpc:sendTransaction(encoded, function(sendResult, sendErr)
            if sendErr then
                fireCallback(eventName, eventSource, nil, "Failed to send tx: " .. tostring(sendErr))
                return
            end
            fireCallback(eventName, eventSource, {
                signature = sendResult,
            })
        end)
    end)
end

-- Transfer SPL token to ANY wallet (auto-create ATA if needed)
-- Step 1: Check if dest wallet already has ATA for this mint (via RPC)
-- Step 2: If yes, use that ATA. If no, derive ATA and create it.
function transferTokenToWallet(fromWallet, sourceTokenAccount, destWallet, mint, amount, tokenProgramId, eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end
    if not hasWallet(fromWallet) then
        fireCallback(eventName, eventSource, nil, "Wallet not found: " .. tostring(fromWallet))
        return
    end
    tokenProgramId = tokenProgramId or TokenProgram.PROGRAM_ID

    -- Build transfer data (shared by both paths)
    local transferData = {3}
    local amt = math.floor(tonumber(amount) or 0)
    for i = 1, 8 do
        transferData[1 + i] = math.floor(amt % 256)
        amt = math.floor(amt / 256)
    end

    -- First: try to find existing ATA via RPC
    _rpc:getTokenAccountsByOwner(destWallet, { mint = mint }, function(ataResult, ataErr)
        local existingATA = nil
        if not ataErr and ataResult and ataResult.value and #ataResult.value > 0 then
            existingATA = ataResult.value[1].pubkey
            outputDebugString("[solana-sdk] Found existing dest ATA: " .. tostring(existingATA))
        end

        _rpc:getLatestBlockhash(function(bhResult, bhErr)
            if bhErr then
                fireCallback(eventName, eventSource, nil, "Failed to get blockhash: " .. tostring(bhErr))
                return
            end

            local tx = SolTransaction.new()
            tx:setFeePayer(fromWallet)
            tx:setRecentBlockhash(bhResult.value.blockhash)
            tx:addSigner(fromWallet)

            local destATA
            if existingATA then
                destATA = existingATA
            else
                -- No existing ATA — derive using RPC simulation to find correct bump
                -- getAssociatedTokenAddress equivalent: the ATA program itself will
                -- derive the correct address. We need to pass the RIGHT address.
                -- Strategy: call getAccountInfo on each candidate until we find one
                -- that returns "account not found" (= valid PDA, not on curve)
                -- For speed: just simulate with each bump
                local candidates = AssociatedTokenProgram.findAddress(destWallet, mint, tokenProgramId)
                if not candidates or #candidates == 0 then
                    fireCallback(eventName, eventSource, nil, "Failed to derive ATA")
                    return
                end

                -- Try to send TX with each bump candidate until one succeeds
                local function tryBump(idx)
                    if idx > #candidates then
                        fireCallback(eventName, eventSource, nil, "All ATA bump candidates failed")
                        return
                    end
                    local cand = candidates[idx]
                    destATA = cand.address
                    outputDebugString("[solana-sdk] Trying ATA bump=" .. cand.bump .. " addr=" .. destATA:sub(1, 12))

                    local txN = SolTransaction.new()
                    txN:setFeePayer(fromWallet)
                    txN:setRecentBlockhash(bhResult.value.blockhash)
                    txN:addSigner(fromWallet)
                    txN:addInstruction(AssociatedTokenProgram.createIdempotentIx(
                        fromWallet, destATA, destWallet, mint, tokenProgramId))
                    txN:addInstruction({
                        programId = tokenProgramId,
                        keys = {
                            { pubkey = sourceTokenAccount, isSigner = false, isWritable = true },
                            { pubkey = destATA, isSigner = false, isWritable = true },
                            { pubkey = fromWallet, isSigner = true, isWritable = false },
                        },
                        data = transferData,
                    })
                    local enc, encErr = txN:signAndEncode()
                    if not enc then
                        tryBump(idx + 1)
                        return
                    end
                    _rpc:sendTransaction(enc, function(r, e)
                        if e then
                            -- This bump failed, try next
                            tryBump(idx + 1)
                        else
                            fireCallback(eventName, eventSource, { signature = r })
                        end
                    end)
                end
                tryBump(1)
                return
            end

            -- Direct transfer (existing ATA found)
            tx:addInstruction({
                programId = tokenProgramId,
                keys = {
                    { pubkey = sourceTokenAccount, isSigner = false, isWritable = true },
                    { pubkey = destATA, isSigner = false, isWritable = true },
                    { pubkey = fromWallet, isSigner = true, isWritable = false },
                },
                data = transferData,
            })
            local encoded, txErr = tx:signAndEncode()
            if not encoded then
                fireCallback(eventName, eventSource, nil, "Failed to build tx: " .. tostring(txErr))
                return
            end
            _rpc:sendTransaction(encoded, function(sendResult, sendErr)
                if sendErr then
                    fireCallback(eventName, eventSource, nil, "Failed: " .. tostring(sendErr))
                    return
                end
                fireCallback(eventName, eventSource, { signature = sendResult })
            end)
        end)
    end, { encoding = "jsonParsed" })
end

-- Approve delegate to spend your tokens
function approveToken(ownerWallet, tokenAccount, delegateAddress, amount, eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end

    if not hasWallet(ownerWallet) then
        fireCallback(eventName, eventSource, nil, "Wallet not found: " .. tostring(ownerWallet))
        return
    end

    _rpc:getLatestBlockhash(function(result, err)
        if err then
            fireCallback(eventName, eventSource, nil, "Failed to get blockhash: " .. tostring(err))
            return
        end

        local tx = SolTransaction.new()
        tx:setFeePayer(ownerWallet)
        tx:setRecentBlockhash(result.value.blockhash)
        tx:addSigner(ownerWallet)
        tx:addInstruction(TokenProgram.approve(tokenAccount, delegateAddress, ownerWallet, amount))

        local encoded, txErr = tx:signAndEncode()
        if not encoded then
            fireCallback(eventName, eventSource, nil, "Failed to build tx: " .. tostring(txErr))
            return
        end

        _rpc:sendTransaction(encoded, function(sendResult, sendErr)
            if sendErr then
                fireCallback(eventName, eventSource, nil, "Failed to send tx: " .. tostring(sendErr))
                return
            end
            fireCallback(eventName, eventSource, { signature = sendResult })
        end)
    end)
end

-- Revoke delegate (Revoke token approval)
function revokeToken(ownerWallet, tokenAccount, eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end

    if not hasWallet(ownerWallet) then
        fireCallback(eventName, eventSource, nil, "Wallet not found: " .. tostring(ownerWallet))
        return
    end

    _rpc:getLatestBlockhash(function(result, err)
        if err then
            fireCallback(eventName, eventSource, nil, "Failed to get blockhash: " .. tostring(err))
            return
        end

        local tx = SolTransaction.new()
        tx:setFeePayer(ownerWallet)
        tx:setRecentBlockhash(result.value.blockhash)
        tx:addSigner(ownerWallet)
        tx:addInstruction(TokenProgram.revoke(tokenAccount, ownerWallet))

        local encoded, txErr = tx:signAndEncode()
        if not encoded then
            fireCallback(eventName, eventSource, nil, "Failed to build tx: " .. tostring(txErr))
            return
        end

        _rpc:sendTransaction(encoded, function(sendResult, sendErr)
            if sendErr then
                fireCallback(eventName, eventSource, nil, "Failed to send tx: " .. tostring(sendErr))
                return
            end
            fireCallback(eventName, eventSource, { signature = sendResult })
        end)
    end)
end

-- Burn tokens
function burnToken(ownerWallet, tokenAccount, mintAddress, amount, eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end

    if not hasWallet(ownerWallet) then
        fireCallback(eventName, eventSource, nil, "Wallet not found: " .. tostring(ownerWallet))
        return
    end

    _rpc:getLatestBlockhash(function(result, err)
        if err then
            fireCallback(eventName, eventSource, nil, "Failed to get blockhash: " .. tostring(err))
            return
        end

        local tx = SolTransaction.new()
        tx:setFeePayer(ownerWallet)
        tx:setRecentBlockhash(result.value.blockhash)
        tx:addSigner(ownerWallet)
        tx:addInstruction(TokenProgram.burn(tokenAccount, mintAddress, ownerWallet, amount))

        local encoded, txErr = tx:signAndEncode()
        if not encoded then
            fireCallback(eventName, eventSource, nil, "Failed to build tx: " .. tostring(txErr))
            return
        end

        _rpc:sendTransaction(encoded, function(sendResult, sendErr)
            if sendErr then
                fireCallback(eventName, eventSource, nil, "Failed to send tx: " .. tostring(sendErr))
                return
            end
            fireCallback(eventName, eventSource, { signature = sendResult })
        end)
    end)
end

-- Close token account (reclaim rent SOL)
function closeTokenAccount(ownerWallet, tokenAccount, eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end

    if not hasWallet(ownerWallet) then
        fireCallback(eventName, eventSource, nil, "Wallet not found: " .. tostring(ownerWallet))
        return
    end

    _rpc:getLatestBlockhash(function(result, err)
        if err then
            fireCallback(eventName, eventSource, nil, "Failed to get blockhash: " .. tostring(err))
            return
        end

        local tx = SolTransaction.new()
        tx:setFeePayer(ownerWallet)
        tx:setRecentBlockhash(result.value.blockhash)
        tx:addSigner(ownerWallet)
        tx:addInstruction(TokenProgram.closeAccount(tokenAccount, ownerWallet, ownerWallet))

        local encoded, txErr = tx:signAndEncode()
        if not encoded then
            fireCallback(eventName, eventSource, nil, "Failed to build tx: " .. tostring(txErr))
            return
        end

        _rpc:sendTransaction(encoded, function(sendResult, sendErr)
            if sendErr then
                fireCallback(eventName, eventSource, nil, "Failed to send tx: " .. tostring(sendErr))
                return
            end
            fireCallback(eventName, eventSource, { signature = sendResult })
        end)
    end)
end

-- Send custom transaction (with arbitrary instructions)
-- instructions = array of instruction tables (SystemProgram, TokenProgram, CustomProgram, etc)
-- signerAddresses = array of wallet addresses that need to sign
function sendCustomTransaction(feePayerAddress, instructions, signerAddresses, eventName, eventSource)
    if not ensureReady(eventName, eventSource) then return end

    _rpc:getLatestBlockhash(function(result, err)
        if err then
            fireCallback(eventName, eventSource, nil, "Failed to get blockhash: " .. tostring(err))
            return
        end

        local blockhash = result.value.blockhash

        local tx = SolTransaction.new()
        tx:setFeePayer(feePayerAddress)
        tx:setRecentBlockhash(blockhash)

        -- Add all signers
        for _, addr in ipairs(signerAddresses or {feePayerAddress}) do
            local _, sigErr = tx:addSigner(addr)
            if sigErr then
                fireCallback(eventName, eventSource, nil, sigErr)
                return
            end
        end

        -- Add all instructions
        for _, ix in ipairs(instructions) do
            tx:addInstruction(ix)
        end

        local encoded, txErr = tx:signAndEncode()
        if not encoded then
            fireCallback(eventName, eventSource, nil, "Failed to build tx: " .. tostring(txErr))
            return
        end

        _rpc:sendTransaction(encoded, function(sendResult, sendErr)
            if sendErr then
                fireCallback(eventName, eventSource, nil, "Failed to send tx: " .. tostring(sendErr))
                return
            end
            fireCallback(eventName, eventSource, {
                signature = sendResult,
            })
        end)
    end)
end
