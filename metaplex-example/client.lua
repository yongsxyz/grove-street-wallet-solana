-- https://github.com/yongsxyz
-- metaplex-example/client.lua
-- All blockchain work happens server-side; this client is a placeholder
-- so MTA:SA recognises the resource as having a client component if you
-- ever want to extend it (HUD, GUI, etc.).
addEventHandler("onClientResourceStart", resourceRoot, function()
    outputChatBox("#9b6dff[metaplex-example] #ffffffLoaded. Type /mphelp to see commands.",
        255, 255, 255, true)
end)
