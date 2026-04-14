-- https://github.com/yongsxyz
--[[
    Solana Token Registry - Manual Config
    Devnet + Mainnet token list
    No external API, fully offline
]]

TokenRegistry = {}

-- ---
-- DEVNET TOKENS
-- ---
local DEVNET_TOKENS = {
    ["Gh9ZwEmdLJ8DscKNTkTqPbNwLNNBjuSzaG9Vp2KGtKJr"] = {
        symbol = "USDC-Dev",
        name   = "USD Coin Dev",
        icon   = "usdc.png",
    },
    ["So11111111111111111111111111111111111111112"] = {
        symbol = "SOL",
        name   = "Wrapped SOL",
        icon   = "sol.png",
    },
    ["4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU"] = {
        symbol = "USDC-Dev2",
        name   = "USDC Devnet",
        icon   = "usdc.png",
    },
}

-- ---
-- MAINNET TOKENS
-- ---
local MAINNET_TOKENS = {
    ["So11111111111111111111111111111111111111112"] = {
        symbol = "SOL",
        name   = "Wrapped SOL",
        icon   = "sol.png",
    },
    ["EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"] = {
        symbol = "USDC",
        name   = "USD Coin",
        icon   = "usdc.png",
    },
    ["Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"] = {
        symbol = "USDT",
        name   = "Tether USD",
        icon   = "usdt.png",
    },
    ["7vfCXTUXx5WJV5JADk17DUJ4ksgau7utNKj4b963voxs"] = {
        symbol = "ETH",
        name   = "Wrapped Ethereum",
        icon   = nil,
    },
    ["mSoLzYCxHdYgdzU16g5QSh3i5K3z3KZK7ytfqcJm7So"] = {
        symbol = "mSOL",
        name   = "Marinade Staked SOL",
        icon   = nil,
    },
    ["7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj"] = {
        symbol = "stSOL",
        name   = "Lido Staked SOL",
        icon   = nil,
    },
    ["DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"] = {
        symbol = "BONK",
        name   = "Bonk",
        icon   = nil,
    },
    ["JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN"] = {
        symbol = "JUP",
        name   = "Jupiter",
        icon   = nil,
    },
    ["EKpQGSJtjMFqKZ9KQanSqYXRcF8fBopzLHYxdM65zcjm"] = {
        symbol = "WIF",
        name   = "dogwifhat",
        icon   = nil,
    },
    ["rndrizKT3MK1iimdxRdWabcF7Zg7AR5T4nud4EkHBof"] = {
        symbol = "RNDR",
        name   = "Render Token",
        icon   = nil,
    },
    ["HZ1JovNiVvGrGNiiYvEozEVgZ58xaU3RKwX8eACQBCt3"] = {
        symbol = "PYTH",
        name   = "Pyth Network",
        icon   = nil,
    },
    ["jtojtomepa8beP8AuQc6eXt5FriJwfFMwQx2v2f9mCL"] = {
        symbol = "JTO",
        name   = "Jito",
        icon   = nil,
    },
    ["TNSRxcUxoT9xBG3de7PiJyTDYu7kskLqcpddxnEJAS6"] = {
        symbol = "TNSR",
        name   = "Tensor",
        icon   = nil,
    },
    ["85VBFQZC9TZkfaptBWjvUw7YbZjy52A6mjtPGjstQAmQ"] = {
        symbol = "W",
        name   = "Wormhole",
        icon   = nil,
    },
    ["MEW1gQWJ3nEXg2qgERiKu7FAFj79PHvQVREQUzScPP5"] = {
        symbol = "MEW",
        name   = "cat in a dogs world",
        icon   = nil,
    },
    ["WENWENvqqNya429ubCdR81ZmD69brwQaaBYY6p3LCpk"] = {
        symbol = "WEN",
        name   = "Wen",
        icon   = nil,
    },
}

-- ---
-- TESTNET TOKENS
-- ---
local TESTNET_TOKENS = {
    ["So11111111111111111111111111111111111111112"] = {
        symbol = "SOL",
        name   = "Wrapped SOL",
        icon   = "sol.png",
    },
}

-- ---
-- LOOKUP
-- ---

function TokenRegistry.lookup(mint, network)
    if not mint then return nil end
    network = network or "devnet"
    local list
    if network == "mainnet-beta" or network == "mainnet" then
        list = MAINNET_TOKENS
    elseif network == "testnet" then
        list = TESTNET_TOKENS
    else
        list = DEVNET_TOKENS
    end
    -- Check network-specific first, then fallback to mainnet
    if list[mint] then return list[mint] end
    if list ~= MAINNET_TOKENS and MAINNET_TOKENS[mint] then return MAINNET_TOKENS[mint] end
    return nil
end

function TokenRegistry.getSymbol(mint, network)
    local info = TokenRegistry.lookup(mint, network)
    return info and info.symbol or nil
end

function TokenRegistry.getName(mint, network)
    local info = TokenRegistry.lookup(mint, network)
    return info and info.name or nil
end

function TokenRegistry.getIcon(mint, network)
    local info = TokenRegistry.lookup(mint, network)
    return info and info.icon or nil
end

-- No fetchJupiterList needed
function TokenRegistry.fetchJupiterList() end
