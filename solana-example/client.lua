-- https://github.com/yongsxyz
--[[
    Solana Example Resource - Client Side
    Menampilkan info Solana di HUD player (optional)
]]

-- Client-side placeholder for UI display
-- RPC calls should be done server-side only
-- Client only displays data from server

-- Receives data from server and displays it
addEvent("onSolanaBalanceUpdate", true)
addEventHandler("onSolanaBalanceUpdate", root, function(data)
    if data and data.sol then
        outputChatBox("#00FF00[Solana] #FFFFFFBalance kamu: " .. tostring(data.sol) .. " SOL", 255, 255, 255, true)
    end
end)
