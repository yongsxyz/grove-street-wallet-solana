-- https://github.com/yongsxyz
--[[
    Grove Street Wallet - Client UI
    Pure DX drawing with custom input system
    Supports typing + Ctrl-V paste
    F5 toggle | Escape back/close
]]

local screenW, screenH = guiGetScreenSize()
local sx, sy = screenW / 1920, screenH / 1080

local fBold = dxCreateFont(":resources/Poppins-Bold.ttf", math.floor(13 * sy)) or "default-bold"
local fTitle = dxCreateFont(":resources/Poppins-Bold.ttf", math.floor(20 * sy)) or "default-bold"
local fSmall = dxCreateFont(":resources/Poppins-Bold.ttf", math.floor(10 * sy)) or "default-bold"
local fBig = dxCreateFont(":resources/Poppins-Bold.ttf", math.floor(28 * sy)) or "default-bold"

-- Colors
local bg       = tocolor(13, 13, 22, 250)
local card     = tocolor(22, 22, 40, 255)
local cardH    = tocolor(32, 32, 55, 255)
local purple   = tocolor(153, 69, 255, 255)
local green    = tocolor(20, 241, 149, 255)
local red      = tocolor(240, 50, 50, 255)
local orange   = tocolor(255, 170, 30, 255)
local white    = tocolor(255, 255, 255, 255)
local gray     = tocolor(130, 130, 150, 255)
local dim      = tocolor(190, 190, 200, 220)
local border   = tocolor(50, 50, 80, 100)

-- Panel
local pw, ph = math.floor(400 * sx), math.floor(640 * sy)
local px, py = math.floor((screenW - pw) / 2), math.floor((screenH - ph) / 2)
local pad = math.floor(18 * sx)

-- State
local isOpen = false
local screen = "main"
local network = "devnet"
local wallets = {}
local selWallet = nil
local balance = nil
local tokens = {}
local txHistory = {}
local sendMode = "SOL"     -- "SOL" or token symbol
local sendToken = nil      -- nil for SOL, or token table {pubkey, mint, symbol, ...}
local txDetail = nil       -- selected tx for detail view
local txDetailData = nil   -- full tx data from RPC
local notif = { text = "", col = green, alpha = 0, tick = 0 }
local mnemonicPhrase = nil
local deleteConfirm = nil

-- ---
-- DX INPUT SYSTEM (no GUI elements, pure DX)
-- ---
local inputs = {}       -- id -> { text, focused, cursorPos }
local focusedInput = nil

local function resetInput(id, placeholder)
    inputs[id] = { text = "", placeholder = placeholder or "", focused = false }
end

local function getInput(id)
    return inputs[id] and inputs[id].text or ""
end

local function clearAllInputs()
    for k in pairs(inputs) do
        inputs[k].text = ""
        inputs[k].focused = false
    end
    focusedInput = nil
end

local function drawInput(id, x, y, w, h, placeholder)
    if not inputs[id] then
        inputs[id] = { text = "", placeholder = placeholder or "", focused = false }
    end
    local inp = inputs[id]
    local focused = (focusedInput == id)
    local hov = inRect(x, y, w, h)

    -- Background
    dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, 220))
    -- Border bottom
    local bc = focused and purple or (hov and tocolor(100, 100, 140, 255) or border)
    dxDrawRectangle(x, y + h - math.floor(2 * sy), w, math.floor(2 * sy), bc)

    -- Text
    local displayText = #inp.text > 0 and inp.text or inp.placeholder
    local textCol = #inp.text > 0 and green or gray

    -- Clip text to fit (show last part if too long)
    local maxChars = math.floor(w / (8 * sx))
    local shown = displayText
    if #shown > maxChars then
        shown = ".." .. shown:sub(-maxChars + 2)
    end

    dxDrawText(shown, x + math.floor(10 * sx), y, x + w - math.floor(10 * sx), y + h,
        textCol, 1, fSmall, "left", "center", true)

    -- Cursor blink
    if focused and math.floor(getTickCount() / 500) % 2 == 0 then
        local textW = dxGetTextWidth(shown, 1, fSmall)
        local curX = x + math.floor(10 * sx) + math.min(textW, w - math.floor(24 * sx))
        dxDrawRectangle(curX, y + math.floor(6 * sy), math.floor(2 * sx), h - math.floor(12 * sy), green)
    end

    -- Store hitbox for click detection
    inp._x, inp._y, inp._w, inp._h = x, y, w, h
    return hov
end

-- ---
-- HELPERS
-- ---
function inRect(x, y, w, h)
    if not isCursorShowing() then return false end
    local cx, cy = getCursorPosition()
    if not cx then return false end
    cx, cy = cx * screenW, cy * screenH
    return cx >= x and cx <= x + w and cy >= y and cy <= y + h
end

local function shortAddr(a)
    if not a or #a < 16 then return a or "?" end
    return a:sub(1, 10) .. "..." .. a:sub(-8)
end

local function btn(x, y, w, h, text, bgN, bgHov, textCol, font)
    local hov = inRect(x, y, w, h)
    dxDrawRectangle(x, y, w, h, hov and bgHov or bgN)
    dxDrawText(text, x, y, x + w, y + h, textCol or white, 1, font or fBold, "center", "center")
    return hov
end

-- Button with icon on left
local function btnIcon(x, y, w, h, text, icon, bgN, bgHov, textCol, font)
    local hov = inRect(x, y, w, h)
    dxDrawRectangle(x, y, w, h, hov and bgHov or bgN)
    local icoSz = math.floor(h * 0.5)
    local totalW = icoSz + math.floor(8 * sx) + dxGetTextWidth(text, 1, font or fBold)
    local startX = x + math.floor((w - totalW) / 2)
    if icon and fileExists(icon) then
        dxDrawImage(startX, y + math.floor((h - icoSz) / 2), icoSz, icoSz, icon)
        dxDrawText(text, startX + icoSz + math.floor(8 * sx), y, x + w, y + h, textCol or white, 1, font or fBold, "left", "center")
    else
        dxDrawText(text, x, y, x + w, y + h, textCol or white, 1, font or fBold, "center", "center")
    end
    return hov
end

local function showNotif(text, t)
    notif = { text = text, col = t == "error" and red or t == "warn" and orange or green, alpha = 255, tick = getTickCount() }
end

-- ---
-- SCREENS (each returns table of clickable buttons {y, h, action})
-- ---
local clickZones = {}

local function addClick(id, x, y, w, h)
    clickZones[id] = {x = x, y = y, w = w, h = h}
end

-- Currency state: SOL (default, with icon) -> USD -> IDR -> SOL
local currency = "SOL"
local livePrices = { sol_usd = 0, sol_idr = 0, usdc_usd = 1, usdc_idr = 16200 }

local function toFiat(solAmount)
    if not solAmount or solAmount == 0 then return "" end
    if currency == "IDR" then
        if livePrices.sol_idr == 0 then return "..." end
        local idr = solAmount * livePrices.sol_idr
        if idr >= 1000000 then return string.format("Rp %.1fM", idr / 1000000)
        elseif idr >= 1000 then return string.format("Rp %.0fK", idr / 1000)
        else return string.format("Rp %.0f", idr) end
    else
        if livePrices.sol_usd == 0 then return "..." end
        return string.format("$%.2f", solAmount * livePrices.sol_usd)
    end
end

local function tokenFiat(uiAmount, symbol)
    if not uiAmount or uiAmount == 0 then return "" end
    local isStable = (symbol == "USDC" or symbol == "USDC-Dev" or symbol == "USDC-Dev2" or symbol == "USDT")
    if isStable then
        if currency == "IDR" then
            if livePrices.usdc_idr == 0 then return "..." end
            local idr = uiAmount * livePrices.usdc_idr
            if idr >= 1000000 then return string.format("Rp %.1fM", idr / 1000000) end
            return string.format("Rp %.0f", idr)
        else
            return string.format("$%.2f", uiAmount * livePrices.usdc_usd)
        end
    end
    -- Non-stablecoin SPL token — no fiat price available
    return ""
end

-- MAIN
local function drawMain()
    local x, y, w = px + pad, py + math.floor(62 * sy), pw - pad * 2

    if not selWallet then
        dxDrawText("No wallet yet", x, y + math.floor(80 * sy), x + w, y + math.floor(120 * sy), gray, 1, fBold, "center", "center")
        local by = y + math.floor(150 * sy)
        btn(x + math.floor(80 * sx), by, w - math.floor(160 * sx), math.floor(48 * sy), "+ Create Wallet", purple, tocolor(180, 100, 255, 255), white, fBold)
        addClick("create", x + math.floor(80 * sx), by, w - math.floor(160 * sx), math.floor(48 * sy))
        return
    end

    -- Main balance display
    local solVal = balance and balance.sol or 0

    if currency == "SOL" then
        -- SOL mode: [icon] amount SOL
        local iconSize = math.floor(42 * sy)
        local solText = balance and string.format("%.4f", solVal) or "--"
        local balW = dxGetTextWidth(solText, 1, fBig) + math.floor(10 * sx) + dxGetTextWidth("SOL", 1, fBig)
        local totalW = iconSize + math.floor(12 * sx) + balW
        local startX = x + math.floor((w - totalW) / 2)
        if fileExists("icons/sol.png") then
            dxDrawImage(startX, y + math.floor((50 * sy - iconSize) / 2), iconSize, iconSize, "icons/sol.png")
        end
        local textX = startX + iconSize + math.floor(12 * sx)
        dxDrawText(solText, textX, y, textX + math.floor(250 * sx), y + math.floor(50 * sy), white, 1, fBig, "left", "center")
        local amtW = dxGetTextWidth(solText, 1, fBig)
        dxDrawText("SOL", textX + amtW + math.floor(8 * sx), y, textX + amtW + math.floor(80 * sx), y + math.floor(50 * sy), white, 1, fBig, "left", "center")
    else
        -- USD/IDR mode: total portfolio fiat (no icon)
        local mainText
        if currency == "IDR" then
            local totalIdr = solVal * livePrices.sol_idr
            for _, tk in ipairs(tokens) do
                local isStable = (tk.symbol == "USDC" or tk.symbol == "USDC-Dev" or tk.symbol == "USDC-Dev2" or tk.symbol == "USDT")
                if isStable and tk.uiAmount then totalIdr = totalIdr + tk.uiAmount * livePrices.usdc_idr end
            end
            if totalIdr >= 1000000 then mainText = string.format("Rp %.1fM", totalIdr / 1000000)
            elseif totalIdr >= 1000 then mainText = string.format("Rp %.0fK", totalIdr / 1000)
            else mainText = string.format("Rp %.0f", totalIdr) end
        else
            local totalUsd = solVal * livePrices.sol_usd
            for _, tk in ipairs(tokens) do
                local isStable = (tk.symbol == "USDC" or tk.symbol == "USDC-Dev" or tk.symbol == "USDC-Dev2" or tk.symbol == "USDT")
                if isStable and tk.uiAmount then totalUsd = totalUsd + tk.uiAmount * livePrices.usdc_usd end
            end
            mainText = string.format("$%.2f", totalUsd)
        end
        if not balance then mainText = "--" end
        dxDrawText(mainText, x, y, x + w, y + math.floor(50 * sy), white, 1, fBig, "center", "center")
    end
    y = y + math.floor(54 * sy)

    -- Send / Receive with icons
    local bw = math.floor((w - math.floor(12 * sx)) / 2)
    local bh = math.floor(44 * sy)
    local icoBtn = math.floor(20 * sy)
    local gap = math.floor(12 * sx)

    -- Send button
    local sendHov = inRect(x, y, bw, bh)
    dxDrawRectangle(x, y, bw, bh, sendHov and cardH or card)
    if fileExists("icons/send.png") then
        local ix = x + math.floor((bw - icoBtn - dxGetTextWidth("Send", 1, fBold) - math.floor(6 * sx)) / 2)
        dxDrawImage(ix, y + math.floor((bh - icoBtn) / 2), icoBtn, icoBtn, "icons/send.png")
        dxDrawText("Send", ix + icoBtn + math.floor(6 * sx), y, ix + icoBtn + math.floor(80 * sx), y + bh, white, 1, fBold, "left", "center")
    else
        dxDrawText("Send", x, y, x + bw, y + bh, white, 1, fBold, "center", "center")
    end
    addClick("send", x, y, bw, bh)

    -- Receive button
    local rx = x + bw + gap
    local recvHov = inRect(rx, y, bw, bh)
    dxDrawRectangle(rx, y, bw, bh, recvHov and cardH or card)
    if fileExists("icons/receive.png") then
        local ix = rx + math.floor((bw - icoBtn - dxGetTextWidth("Receive", 1, fBold) - math.floor(6 * sx)) / 2)
        dxDrawImage(ix, y + math.floor((bh - icoBtn) / 2), icoBtn, icoBtn, "icons/receive.png")
        dxDrawText("Receive", ix + icoBtn + math.floor(6 * sx), y, ix + icoBtn + math.floor(100 * sx), y + bh, white, 1, fBold, "left", "center")
    else
        dxDrawText("Receive", rx, y, rx + bw, y + bh, white, 1, fBold, "center", "center")
    end
    addClick("receive", rx, y, bw, bh)
    y = y + math.floor(54 * sy)

    -- Token list
    dxDrawRectangle(x, y, w, 1, border)
    y = y + math.floor(8 * sy)
    dxDrawText("Tokens", x, y, x + w, y + math.floor(24 * sy), white, 1, fBold, "left", "center")
    y = y + math.floor(24 * sy)

    -- SOL row (clickable -> send SOL)
    local rowH = math.floor(52 * sy)
    local icoSz = math.floor(28 * sy)
    local solHov = inRect(x, y, w, rowH)
    dxDrawRectangle(x, y, w, rowH, solHov and cardH or card)
    if fileExists("icons/sol.png") then
        dxDrawImage(x + math.floor(10 * sx), y + math.floor((rowH - icoSz) / 2), icoSz, icoSz, "icons/sol.png")
    end
    dxDrawText("Solana", x + math.floor(46 * sx), y, x + math.floor(180 * sx), y + math.floor(rowH / 2), white, 1, fBold, "left", "bottom")
    dxDrawText(toFiat(balance and balance.sol), x + math.floor(46 * sx), y + math.floor(rowH / 2), x + math.floor(180 * sx), y + rowH, gray, 1, fSmall, "left", "top")
    local sAmt = balance and string.format("%.4f", balance.sol or 0) or "..."
    dxDrawText(sAmt, x + math.floor(180 * sx), y, x + w - math.floor(10 * sx), y + rowH, white, 1, fBold, "right", "center")
    addClick("send_sol", x, y, w, rowH)
    y = y + math.floor(56 * sy)

    -- SPL tokens (clickable -> send that token, hide zero balance)
    local shown = 0
    for i, tk in ipairs(tokens) do
        if shown >= 5 then break end
        if tk.uiAmount and tk.uiAmount > 0 then
            shown = shown + 1
            local tkHov = inRect(x, y, w, rowH)
            dxDrawRectangle(x, y, w, rowH, tkHov and cardH or card)
            local hasIcon = tk.icon and fileExists("icons/" .. tk.icon)
            if hasIcon then
                dxDrawImage(x + math.floor(10 * sx), y + math.floor((rowH - icoSz) / 2), icoSz, icoSz, "icons/" .. tk.icon)
            else
                dxDrawRectangle(x, y, math.floor(3 * sx), rowH, orange)
            end
            local tL = hasIcon and (x + math.floor(46 * sx)) or (x + math.floor(14 * sx))
            local tkName = tk.name or tk.symbol or "Unknown"
            dxDrawText(tkName, tL, y, x + math.floor(180 * sx), y + math.floor(rowH / 2), white, 1, fBold, "left", "bottom")
            local fiat = tokenFiat(tk.uiAmount, tk.symbol)
            if #fiat > 0 then
                dxDrawText(fiat, tL, y + math.floor(rowH / 2), x + math.floor(180 * sx), y + rowH, gray, 1, fSmall, "left", "top")
            end
            local aText = string.format("%.4f", tk.uiAmount)
            dxDrawText(aText, x + math.floor(180 * sx), y, x + w - math.floor(10 * sx), y + rowH, white, 1, fBold, "right", "center")
            addClick("send_token_" .. i, x, y, w, rowH)
            y = y + math.floor(56 * sy)
        end
    end
end

-- SEND
local function drawSend()
    local x, y, w = px + pad, py + math.floor(62 * sy), pw - pad * 2
    local editH = math.floor(34 * sy)

    -- Title shows which token
    local sendLabel = sendMode == "SOL" and "Send SOL" or ("Send " .. sendMode)
    dxDrawText(sendLabel, x, y, x + w, y + math.floor(32 * sy), white, 1, fTitle, "left", "center")
    y = y + math.floor(38 * sy)

    -- Token badge
    if sendToken then
        local badgeH = math.floor(28 * sy)
        local icoSz = math.floor(20 * sy)
        dxDrawRectangle(x, y, w, badgeH, card)
        if sendToken.icon and fileExists("icons/" .. sendToken.icon) then
            dxDrawImage(x + math.floor(8 * sx), y + math.floor((badgeH - icoSz) / 2), icoSz, icoSz, "icons/" .. sendToken.icon)
        end
        local lbl = (sendToken.name or sendToken.symbol or "Token") .. "  |  " .. shortAddr(sendToken.mint or "")
        dxDrawText(lbl, x + math.floor(34 * sx), y, x + w, y + badgeH, gray, 1, fSmall, "left", "center")
        y = y + math.floor(34 * sy)
    end

    dxDrawText("Recipient Address", x, y, x + w, y + math.floor(18 * sy), orange, 1, fSmall, "left", "center")
    y = y + math.floor(22 * sy)
    drawInput("send_to", x, y, w, editH, "Paste address here...")
    y = y + math.floor(46 * sy)

    local amtLabel = sendMode == "SOL" and "Amount (SOL)" or ("Amount (" .. sendMode .. ")")
    dxDrawText(amtLabel, x, y, x + w, y + math.floor(18 * sy), gray, 1, fSmall, "left", "center")
    y = y + math.floor(22 * sy)
    drawInput("send_amt", x, y, w, editH, "0.0")
    y = y + math.floor(50 * sy)

    -- Balance info
    if sendMode == "SOL" and balance then
        dxDrawText("Balance: " .. string.format("%.4f SOL", balance.sol or 0), x, y, x + w, y + math.floor(18 * sy), gray, 1, fSmall, "left", "center")
        y = y + math.floor(28 * sy)
    elseif sendToken and sendToken.uiAmount then
        dxDrawText("Balance: " .. string.format("%.4f %s", sendToken.uiAmount, sendMode), x, y, x + w, y + math.floor(18 * sy), gray, 1, fSmall, "left", "center")
        y = y + math.floor(28 * sy)
    end

    btnIcon(x, y, w, math.floor(44 * sy), "Confirm Send", "icons/confirm.png", purple, tocolor(180, 100, 255, 255), white, fBold)
    addClick("confirm_send", x, y, w, math.floor(44 * sy))
    y = y + math.floor(62 * sy)
    btnIcon(x, y, w, math.floor(36 * sy), "Back", "icons/back.png", card, cardH, gray, fSmall)
    addClick("back", x, y, w, math.floor(38 * sy))
end

-- RECEIVE
local function drawReceive()
    local x, y, w = px + pad, py + math.floor(62 * sy), pw - pad * 2

    dxDrawText("Receive", x, y, x + w, y + math.floor(32 * sy), white, 1, fTitle, "left", "center")
    y = y + math.floor(50 * sy)
    dxDrawText("Your Address", x, y, x + w, y + math.floor(18 * sy), gray, 1, fSmall, "center", "center")
    y = y + math.floor(28 * sy)

    if selWallet then
        dxDrawRectangle(x, y, w, math.floor(72 * sy), card)
        dxDrawRectangle(x, y, w, math.floor(3 * sy), purple)
        dxDrawText(selWallet.address, x + math.floor(8 * sx), y + math.floor(10 * sy),
            x + w - math.floor(8 * sx), y + math.floor(62 * sy), white, 1, fSmall, "center", "center", true, true)
        y = y + math.floor(86 * sy)
        btn(x + math.floor(80 * sx), y, w - math.floor(160 * sx), math.floor(42 * sy), "Copy Address", purple, tocolor(180, 100, 255, 255), white, fBold)
        addClick("copy_addr", x + math.floor(80 * sx), y, w - math.floor(160 * sx), math.floor(42 * sy))
    end
    y = y + math.floor(60 * sy)
    dxDrawText("Network: " .. (network == "devnet" and "Devnet" or "Mainnet"), x, y, x + w, y + math.floor(20 * sy),
        network == "devnet" and orange or green, 1, fSmall, "center", "center")
    y = y + math.floor(40 * sy)
    btnIcon(x, y, w, math.floor(36 * sy), "Back", "icons/back.png", card, cardH, gray, fSmall)
    addClick("back", x, y, w, math.floor(38 * sy))
end

-- TOKENS
local function drawTokens()
    local x, y, w = px + pad, py + math.floor(62 * sy), pw - pad * 2

    dxDrawText("Tokens", x, y, x + w, y + math.floor(32 * sy), white, 1, fTitle, "left", "center")
    y = y + math.floor(44 * sy)

    dxDrawRectangle(x, y, w, math.floor(48 * sy), card)
    dxDrawRectangle(x, y, math.floor(3 * sx), math.floor(48 * sy), purple)
    dxDrawText("SOL", x + math.floor(16 * sx), y, x + w, y + math.floor(48 * sy), purple, 1, fBold, "left", "center")
    dxDrawText(balance and string.format("%.4f", balance.sol or 0) or "...", x, y, x + w - math.floor(16 * sx), y + math.floor(48 * sy), white, 1, fBold, "right", "center")
    y = y + math.floor(56 * sy)

    if #tokens == 0 then
        dxDrawText("No SPL tokens found", x, y, x + w, y + math.floor(36 * sy), gray, 1, fSmall, "center", "center")
        y = y + math.floor(44 * sy)
    else
        for i, tk in ipairs(tokens) do
            if i > 7 then break end
            local rowH = math.floor(52 * sy)
            local iconSize = math.floor(32 * sy)
            local textLeft = x + math.floor(14 * sx)

            dxDrawRectangle(x, y, w, rowH, card)

            -- Icon (if available)
            if tk.icon then
                local iconPath = "icons/" .. tk.icon
                if fileExists(iconPath) then
                    dxDrawImage(x + math.floor(8 * sx), y + math.floor((rowH - iconSize) / 2), iconSize, iconSize, iconPath)
                    textLeft = x + math.floor(14 * sx) + iconSize + math.floor(6 * sx)
                else
                    dxDrawRectangle(x, y, math.floor(3 * sx), rowH, orange)
                end
            else
                dxDrawRectangle(x, y, math.floor(3 * sx), rowH, orange)
            end

            -- Symbol
            local symbol = tk.symbol or "???"
            dxDrawText(symbol, textLeft, y + math.floor(4 * sy),
                x + math.floor(180 * sx), y + math.floor(28 * sy), white, 1, fBold, "left", "center")

            -- Name
            local name = tk.name or shortAddr(tk.mint or "?")
            dxDrawText(name, textLeft, y + math.floor(26 * sy),
                x + math.floor(220 * sx), y + math.floor(46 * sy), gray, 1, fSmall, "left", "center", true)

            -- Amount
            local amtText = tk.uiAmount and string.format("%.4f", tk.uiAmount) or tostring(tk.amount or "0")
            dxDrawText(amtText, x + math.floor(180 * sx), y + math.floor(4 * sy),
                x + w - math.floor(12 * sx), y + math.floor(28 * sy), white, 1, fBold, "right", "center")

            -- Mint short
            dxDrawText(shortAddr(tk.mint or ""), x + math.floor(180 * sx), y + math.floor(26 * sy),
                x + w - math.floor(12 * sx), y + math.floor(46 * sy), tocolor(80, 80, 100, 255), 1, fSmall, "right", "center")

            y = y + math.floor(58 * sy)
        end
    end

    btn(x, y, w, math.floor(38 * sy), "Refresh", card, cardH, gray, fSmall)
    addClick("refresh", x, y, w, math.floor(38 * sy))
    y = y + math.floor(48 * sy)
    btnIcon(x, y, w, math.floor(36 * sy), "Back", "icons/back.png", card, cardH, gray, fSmall)
    addClick("back", x, y, w, math.floor(38 * sy))
end

-- WALLETS
local function drawWallets()
    local x, y, w = px + pad, py + math.floor(62 * sy), pw - pad * 2

    dxDrawText("My Wallets", x, y, x + w, y + math.floor(32 * sy), white, 1, fTitle, "left", "center")
    y = y + math.floor(44 * sy)

    local btnSz = math.floor(28 * sy)
    local btnGap = math.floor(4 * sx)

    for i, wl in ipairs(wallets) do
        if i > 5 then break end
        local sel = selWallet and selWallet.address == wl.address
        local ch = math.floor(58 * sy)
        local clickW = w - math.floor(76 * sx)  -- area klik select (kiri)
        local hov = inRect(x, y, clickW, ch)
        dxDrawRectangle(x, y, w, ch, hov and cardH or card)
        if sel then dxDrawRectangle(x, y, math.floor(4 * sx), ch, purple) end

        -- Name + address
        dxDrawText(wl.name or "Wallet", x + math.floor(16 * sx), y, x + clickW, y + math.floor(ch / 2), white, 1, fBold, "left", "bottom")
        dxDrawText(shortAddr(wl.address), x + math.floor(16 * sx), y + math.floor(ch / 2), x + clickW, y + ch, gray, 1, fSmall, "left", "top")

        -- Delete button (trash icon)
        local delX = x + w - math.floor(38 * sx)
        local delY = y + math.floor((ch - btnSz) / 2)
        local delHov = inRect(delX, delY, btnSz, btnSz)
        dxDrawRectangle(delX, delY, btnSz, btnSz, delHov and red or tocolor(60, 30, 30, 200))
        if fileExists("icons/trash.png") then
            dxDrawImage(delX + math.floor(3 * sx), delY + math.floor(3 * sy), btnSz - math.floor(6 * sx), btnSz - math.floor(6 * sy), "icons/trash.png")
        end

        addClick("select_" .. i, x, y, clickW, ch)
        addClick("delete_" .. i, delX, delY, btnSz, btnSz)
        y = y + math.floor(64 * sy)
    end

    -- Delete confirmation
    if deleteConfirm then
        dxDrawRectangle(x, y, w, math.floor(48 * sy), tocolor(60, 20, 20, 255))
        dxDrawRectangle(x, y, w, math.floor(2 * sy), red)
        dxDrawText("Delete this wallet?", x + math.floor(10 * sx), y, x + math.floor(200 * sx), y + math.floor(48 * sy), white, 1, fSmall, "left", "center")
        btn(x + w - math.floor(130 * sx), y + math.floor(8 * sy), math.floor(56 * sx), math.floor(32 * sy), "Yes", red, tocolor(255, 80, 80, 255), white, fSmall)
        addClick("confirm_del", x + w - math.floor(130 * sx), y + math.floor(8 * sy), math.floor(56 * sx), math.floor(32 * sy))
        btn(x + w - math.floor(66 * sx), y + math.floor(8 * sy), math.floor(56 * sx), math.floor(32 * sy), "Cancel", card, cardH, gray, fSmall)
        addClick("cancel_del", x + w - math.floor(66 * sx), y + math.floor(8 * sy), math.floor(56 * sx), math.floor(32 * sy))
        y = y + math.floor(56 * sy)
    end

    y = y + math.floor(6 * sy)
    btnIcon(x, y, w, math.floor(42 * sy), "Add Wallet", "icons/add.png", purple, tocolor(180, 100, 255, 255), white, fBold)
    addClick("addwallet", x, y, w, math.floor(42 * sy))
    y = y + math.floor(50 * sy)
    btnIcon(x, y, w, math.floor(36 * sy), "Back", "icons/back.png", card, cardH, gray, fSmall)
    addClick("back", x, y, w, math.floor(36 * sy))
end

-- ADD WALLET
local function drawAddWallet()
    local x, y, w = px + pad, py + math.floor(62 * sy), pw - pad * 2
    local editH = math.floor(34 * sy)

    dxDrawText("Add Wallet", x, y, x + w, y + math.floor(32 * sy), white, 1, fTitle, "left", "center")
    y = y + math.floor(46 * sy)

    btnIcon(x, y, w, math.floor(42 * sy), "Create New Wallet", "icons/add.png", purple, tocolor(180, 100, 255, 255), white, fBold)
    addClick("create_new", x, y, w, math.floor(52 * sy))
    y = y + math.floor(62 * sy)

    btnIcon(x, y, w, math.floor(42 * sy), "Generate Mnemonic", "icons/add.png", card, cardH, dim, fBold)
    addClick("gen_mnemonic", x, y, w, math.floor(52 * sy))
    y = y + math.floor(68 * sy)

    dxDrawRectangle(x, y, w, 1, border)
    y = y + math.floor(14 * sy)

    dxDrawText("Import Key (click box, then Ctrl+V)", x, y, x + w, y + math.floor(18 * sy), orange, 1, fSmall, "left", "center")
    y = y + math.floor(24 * sy)
    drawInput("import_key", x, y, w, editH, "Click here, then Ctrl+V paste key...")
    y = y + math.floor(44 * sy)

    dxDrawText("Name (optional)", x, y, x + w, y + math.floor(18 * sy), gray, 1, fSmall, "left", "center")
    y = y + math.floor(22 * sy)
    drawInput("import_name", x, y, w, editH, "Wallet name...")
    y = y + math.floor(48 * sy)

    btnIcon(x, y, w, math.floor(42 * sy), "Import Wallet", "icons/confirm.png", tocolor(30, 80, 30, 255), tocolor(40, 120, 40, 255), green, fBold)
    addClick("do_import", x, y, w, math.floor(44 * sy))
    y = y + math.floor(56 * sy)
    btnIcon(x, y, w, math.floor(36 * sy), "Back", "icons/back.png", card, cardH, gray, fSmall)
    addClick("back", x, y, w, math.floor(38 * sy))
end

-- MNEMONIC
local function drawMnemonic()
    local x, y, w = px + pad, py + math.floor(62 * sy), pw - pad * 2

    dxDrawText("Recovery Phrase", x, y, x + w, y + math.floor(32 * sy), white, 1, fTitle, "left", "center")
    y = y + math.floor(40 * sy)
    dxDrawText("SAVE THIS! Do not share.", x, y, x + w, y + math.floor(18 * sy), red, 1, fSmall, "center", "center")
    y = y + math.floor(30 * sy)

    if mnemonicPhrase then
        dxDrawRectangle(x, y, w, math.floor(110 * sy), card)
        dxDrawRectangle(x, y, w, math.floor(3 * sy), green)
        dxDrawText(mnemonicPhrase, x + math.floor(10 * sx), y + math.floor(10 * sy),
            x + w - math.floor(10 * sx), y + math.floor(100 * sy), green, 1, fBold, "center", "center", true, true)
        y = y + math.floor(124 * sy)
        btn(x + math.floor(60 * sx), y, w - math.floor(120 * sx), math.floor(42 * sy), "Copy Phrase", purple, tocolor(180, 100, 255, 255), white, fBold)
        addClick("copy_phrase", x + math.floor(60 * sx), y, w - math.floor(120 * sx), math.floor(42 * sy))
        y = y + math.floor(56 * sy)
        dxDrawText("Import this phrase into Phantom/Solflare", x, y, x + w, y + math.floor(18 * sy), gray, 1, fSmall, "center", "center")
    else
        dxDrawText("Generating...", x, y, x + w, y + math.floor(40 * sy), gray, 1, fBold, "center", "center")
    end
    y = y + math.floor(40 * sy)
    btnIcon(x, y, w, math.floor(36 * sy), "Done", "icons/back.png", card, cardH, gray, fSmall)
    addClick("back", x, y, w, math.floor(38 * sy))
end

-- ACTIVITY (TX History)
local function drawActivity()
    local x, y, w = px + pad, py + math.floor(62 * sy), pw - pad * 2

    -- Header: title left, refresh right
    dxDrawText("Recent Activity", x, y, x + math.floor(250 * sx), y + math.floor(32 * sy), white, 1, fTitle, "left", "center")
    btn(x + w - math.floor(80 * sx), y + math.floor(2 * sy), math.floor(80 * sx), math.floor(28 * sy), "Refresh", card, cardH, gray, fSmall)
    addClick("refresh_history", x + w - math.floor(80 * sx), y + math.floor(2 * sy), math.floor(80 * sx), math.floor(28 * sy))
    y = y + math.floor(44 * sy)

    if #txHistory == 0 then
        dxDrawText("No transactions yet", x, y + math.floor(40 * sy), x + w, y + math.floor(80 * sy), gray, 1, fSmall, "center", "center")
    else
        for i, tx in ipairs(txHistory) do
            if i > 8 then break end
            local rowH = math.floor(56 * sy)
            dxDrawRectangle(x, y, w, rowH, card)

            -- Status color bar left
            local status = tx.confirmationStatus or "unknown"
            local statusCol = green
            if status == "processed" then statusCol = orange
            elseif status == "confirmed" then statusCol = green
            elseif status == "finalized" then statusCol = purple
            else statusCol = gray end
            if tx.err then statusCol = red end
            dxDrawRectangle(x, y, math.floor(4 * sx), rowH, statusCol)

            -- Row 1: Signature left, Time right
            local sig = tx.signature or "?"
            local sigShort = sig:sub(1, 10) .. "..." .. sig:sub(-6)
            dxDrawText(sigShort, x + math.floor(14 * sx), y + math.floor(4 * sy),
                x + w - math.floor(80 * sx), y + math.floor(26 * sy), dim, 1, fSmall, "left", "center")

            -- Time (top right)
            local agoText = ""
            if tx.blockTime then
                local ago = os.time() - tx.blockTime
                if ago < 60 then agoText = ago .. "s ago"
                elseif ago < 3600 then agoText = math.floor(ago / 60) .. "m ago"
                elseif ago < 86400 then agoText = math.floor(ago / 3600) .. "h ago"
                else agoText = math.floor(ago / 86400) .. "d ago" end
            end
            dxDrawText(agoText, x, y + math.floor(4 * sy), x + w - math.floor(10 * sx),
                y + math.floor(26 * sy), gray, 1, fSmall, "right", "center")

            -- Row 2: Status + Success/Failed left, Detail right
            if tx.err then
                dxDrawText("FAILED", x + math.floor(14 * sx), y + math.floor(28 * sy),
                    x + math.floor(180 * sx), y + math.floor(50 * sy), red, 1, fSmall, "left", "center")
            else
                dxDrawText(status:upper(), x + math.floor(14 * sx), y + math.floor(28 * sy),
                    x + math.floor(100 * sx), y + math.floor(50 * sy), statusCol, 1, fSmall, "left", "center")
                dxDrawText("Success", x + math.floor(100 * sx), y + math.floor(28 * sy),
                    x + math.floor(180 * sx), y + math.floor(50 * sy), green, 1, fSmall, "left", "center")
            end

            -- Detail button (right side)
            local detX = x + w - math.floor(56 * sx)
            local detY = y + math.floor(30 * sy)
            local detW, detH = math.floor(48 * sx), math.floor(20 * sy)
            local detHov = inRect(detX, detY, detW, detH)
            dxDrawRectangle(detX, detY, detW, detH, detHov and purple or border)
            dxDrawText("Detail", detX, detY, detX + detW, detY + detH,
                detHov and white or gray, 1, fSmall, "center", "center")
            addClick("detail_tx_" .. i, detX, detY, detW, detH)

            -- Click whole row to copy sig
            addClick("copy_tx_" .. i, x, y, w - math.floor(60 * sx), rowH)
            y = y + math.floor(60 * sy)
        end
    end
end

-- NAV
-- TX DETAIL
local function drawTxDetail()
    local x, y, w = px + pad, py + math.floor(62 * sy), pw - pad * 2
    local lh = math.floor(18 * sy) -- line height
    local rh = math.floor(26 * sy) -- row height

    dxDrawText("Transaction Detail", x, y, x + w, y + math.floor(28 * sy), white, 1, fTitle, "left", "center")
    y = y + math.floor(34 * sy)

    if not txDetail then
        dxDrawText("No transaction", x, y, x + w, y + rh, gray, 1, fSmall, "center", "center")
        y = y + math.floor(36 * sy)
        btnIcon(x, y, w, math.floor(36 * sy), "Back", "icons/back.png", card, cardH, gray, fSmall)
        addClick("back", x, y, w, math.floor(36 * sy))
        return
    end

    local sig = txDetail.signature or "?"
    local status = txDetail.confirmationStatus or "unknown"
    local failed = txDetail.err and true or false
    local statusCol = failed and red or (status == "finalized" and purple or (status == "confirmed" and green or orange))
    local td = txDetailData -- full RPC data (may be nil while loading)

    -- Signature (compact)
    dxDrawRectangle(x, y, w, rh, card)
    dxDrawText("Sig", x + math.floor(6 * sx), y, x + math.floor(30 * sx), y + rh, gray, 1, fSmall, "left", "center")
    dxDrawText(sig:sub(1, 20) .. "...", x + math.floor(32 * sx), y, x + w - math.floor(44 * sx), y + rh, dim, 1, fSmall, "left", "center")
    btn(x + w - math.floor(38 * sx), y + math.floor(2 * sy), math.floor(34 * sx), rh - math.floor(4 * sy), "Copy", border, cardH, gray, fSmall)
    addClick("copy_sig", x + w - math.floor(38 * sx), y + math.floor(2 * sy), math.floor(34 * sx), rh)
    y = y + rh + math.floor(4 * sy)

    -- Result row: Success/Failed
    dxDrawRectangle(x, y, w, rh, card)
    dxDrawRectangle(x, y, math.floor(3 * sx), rh, statusCol)
    if failed then
        dxDrawText("Failed", x + math.floor(10 * sx), y, x + w - math.floor(6 * sx), y + rh, red, 1, fBold, "left", "center")
    else
        dxDrawText("Success", x + math.floor(10 * sx), y, x + math.floor(100 * sx), y + rh, green, 1, fBold, "left", "center")
        local confText = status == "finalized" and "(MAX confirmations)" or ("(" .. status .. ")")
        dxDrawText(confText, x + math.floor(100 * sx), y, x + w - math.floor(6 * sx), y + rh, gray, 1, fSmall, "left", "center")
    end
    y = y + rh + math.floor(4 * sy)

    -- Transaction Actions (from RPC parsed data)
    if td and td.transaction and td.transaction.message and td.transaction.message.instructions then
        dxDrawText("Transaction Actions", x, y, x + w, y + lh, gray, 1, fSmall, "left", "center")
        y = y + lh + math.floor(2 * sy)
        for _, ix in ipairs(td.transaction.message.instructions) do
            if ix.parsed and ix.parsed.info then
                local info = ix.parsed.info
                local actionH = math.floor(48 * sy)
                dxDrawRectangle(x, y, w, actionH, card)
                -- From
                local from = info.source or info.authority or "?"
                local to = info.destination or info.newAccount or "?"
                local amt = info.lamports or info.amount or info.tokenAmount or ""
                if type(from) == "string" then from = shortAddr(from) end
                if type(to) == "string" then to = shortAddr(to) end
                -- Amount display
                local amtStr = ""
                if info.lamports then
                    amtStr = string.format("%.6f SOL", (tonumber(info.lamports) or 0) / 1000000000)
                elseif info.tokenAmount and type(info.tokenAmount) == "table" then
                    amtStr = tostring(info.tokenAmount.uiAmountString or info.tokenAmount.amount or "")
                elseif info.amount then
                    amtStr = tostring(info.amount)
                end
                dxDrawText(from .. "  ->  " .. to, x + math.floor(10 * sx), y, x + w - math.floor(6 * sx), y + math.floor(24 * sy), dim, 1, fSmall, "left", "center")
                if #amtStr > 0 then
                    dxDrawText(amtStr, x + math.floor(10 * sx), y + math.floor(24 * sy), x + w - math.floor(6 * sx), y + actionH, white, 1, fBold, "left", "center")
                end
                y = y + actionH + math.floor(3 * sy)
            end
        end
    end

    -- Time
    if txDetail.blockTime then
        dxDrawRectangle(x, y, w, rh, card)
        local t = os.date("%Y-%m-%d %H:%M:%S", txDetail.blockTime)
        local ago = os.time() - txDetail.blockTime
        local agoText = ago < 60 and ago .. "s" or (ago < 3600 and math.floor(ago/60) .. "m" or (ago < 86400 and math.floor(ago/3600) .. "h" or math.floor(ago/86400) .. "d"))
        dxDrawText(t, x + math.floor(6 * sx), y, x + w, y + rh, dim, 1, fSmall, "left", "center")
        dxDrawText(agoText .. " ago", x, y, x + w - math.floor(6 * sx), y + rh, gray, 1, fSmall, "right", "center")
        y = y + rh + math.floor(4 * sy)
    end

    -- Fee + Slot + Version (compact rows)
    local fee = "~0.000005 SOL"
    local slot = txDetail.slot or ""
    local ver = "legacy"
    if td then
        if td.meta and td.meta.fee then
            fee = string.format("%.6f SOL", td.meta.fee / 1000000000)
        end
        slot = td.slot or txDetail.slot or ""
        if td.version then ver = tostring(td.version) end
    end

    local infoRows = {
        {"Fee", fee},
        {"Slot", tostring(slot)},
        {"Version", ver},
    }
    if td and td.meta and td.meta.computeUnitsConsumed then
        table.insert(infoRows, 3, {"Compute", tostring(td.meta.computeUnitsConsumed) .. " CU"})
    end
    if td and td.transaction and td.transaction.message and td.transaction.message.recentBlockhash then
        table.insert(infoRows, {"Blockhash", shortAddr(td.transaction.message.recentBlockhash)})
    end

    for _, row in ipairs(infoRows) do
        dxDrawText(row[1], x, y, x + math.floor(80 * sx), y + lh, gray, 1, fSmall, "left", "center")
        dxDrawText(row[2], x + math.floor(82 * sx), y, x + w, y + lh, dim, 1, fSmall, "left", "center")
        y = y + lh + math.floor(1 * sy)
    end

    y = y + math.floor(6 * sy)
    btnIcon(x, y, w, math.floor(38 * sy), "See on Solscan", "icons/nav_activity.png", purple, tocolor(180, 100, 255, 255), white, fBold)
    addClick("see_explorer", x, y, w, math.floor(38 * sy))
    y = y + math.floor(44 * sy)
    btnIcon(x, y, w, math.floor(34 * sy), "Back", "icons/back.png", card, cardH, gray, fSmall)
    addClick("back", x, y, w, math.floor(34 * sy))
end

local function drawNav()
    local navH = math.floor(64 * sy)
    local ny = py + ph - navH
    dxDrawRectangle(px, ny, pw, navH, tocolor(18, 18, 32, 255))
    dxDrawRectangle(px, ny, pw, 1, border)

    local items = {
        { label = "Home",     scr = "main",     icon = "icons/home.png" },
        { label = "Send",     scr = "send",     icon = "icons/nav_send.png" },
        { label = "Activity", scr = "activity",  icon = "icons/nav_activity.png" },
        { label = "Wallets",  scr = "wallets",   icon = "icons/nav_wallets.png" },
    }
    local bw = math.floor(pw / #items)
    local icoSz = math.floor(22 * sy)

    for i, it in ipairs(items) do
        local bx = px + (i - 1) * bw
        local active = (screen == it.scr)
        local hov = inRect(bx, ny, bw, navH)
        local col = active and purple or (hov and white or gray)

        -- Active indicator bar
        if active then dxDrawRectangle(bx, ny + 1, bw, math.floor(3 * sy), purple) end

        -- Icon (centered above text)
        local icx = bx + math.floor((bw - icoSz) / 2)
        local icy = ny + math.floor(10 * sy)
        if fileExists(it.icon) then
            dxDrawImage(icx, icy, icoSz, icoSz, it.icon, 0, 0, 0, col)
        end

        -- Label below icon
        dxDrawText(it.label, bx, icy + icoSz + math.floor(2 * sy), bx + bw, ny + navH,
            col, 1, fSmall, "center", "top")

        addClick("nav_" .. it.scr, bx, ny, bw, navH)
    end
end

-- HEADER
local function drawHeader()
    local hh = math.floor(52 * sy)
    dxDrawRectangle(px, py, pw, hh, tocolor(18, 18, 32, 255))
    dxDrawRectangle(px, py + hh - 1, pw, 1, border)

    -- Title
    dxDrawText("Grove Street Wallet", px + math.floor(16 * sx), py, px + pw, py + hh, purple, 1, fBold, "left", "center")

    -- Right side buttons: [DEVNET] [SOL] [X]
    local btnH = math.floor(22 * sy)
    local btnY = py + math.floor((hh - btnH) / 2)
    local rightX = px + pw - math.floor(10 * sx)

    -- Close X (rightmost)
    local closeW = math.floor(28 * sx)
    rightX = rightX - closeW
    local chov = inRect(rightX, btnY, closeW, btnH)
    dxDrawRectangle(rightX, btnY, closeW, btnH, chov and red or tocolor(50, 50, 70, 200))
    dxDrawText("X", rightX, btnY, rightX + closeW, btnY + btnH, white, 1, fSmall, "center", "center")
    addClick("close", rightX, btnY, closeW, btnH)

    -- Currency toggle (SOL/USD/IDR)
    rightX = rightX - math.floor(42 * sx) - math.floor(4 * sx)
    local curW = math.floor(42 * sx)
    local curHov = inRect(rightX, btnY, curW, btnH)
    dxDrawRectangle(rightX, btnY, curW, btnH, curHov and purple or tocolor(40, 40, 60, 255))
    dxDrawText(currency, rightX, btnY, rightX + curW, btnY + btnH, white, 1, fSmall, "center", "center")
    addClick("currency", rightX, btnY, curW, btnH)

    -- Network toggle (DEVNET/MAINNET)
    local netW = math.floor(62 * sx)
    rightX = rightX - netW - math.floor(4 * sx)
    local netHov = inRect(rightX, btnY, netW, btnH)
    dxDrawRectangle(rightX, btnY, netW, btnH, netHov and tocolor(60, 60, 80, 255) or tocolor(40, 40, 60, 255))
    local ntxt = network == "devnet" and "DEVNET" or "MAINNET"
    local ncol = network == "devnet" and orange or green
    dxDrawText(ntxt, rightX, btnY, rightX + netW, btnY + btnH, ncol, 1, fSmall, "center", "center")
    addClick("network", rightX, btnY, netW, btnH)
end

-- NOTIFICATION
local function drawNotif()
    if notif.alpha <= 0 then return end
    if getTickCount() - notif.tick > 3000 then notif.alpha = math.max(0, notif.alpha - 10) end
    local nw, nh = math.floor(360 * sx), math.floor(36 * sy)
    local nx = math.floor((screenW - nw) / 2)
    dxDrawRectangle(nx, math.floor(16 * sy), nw, nh, tocolor(20, 20, 35, notif.alpha))
    dxDrawRectangle(nx, math.floor(16 * sy), math.floor(4 * sx), nh, notif.col)
    dxDrawText(notif.text, nx + math.floor(14 * sx), math.floor(16 * sy), nx + nw, math.floor(16 * sy) + nh,
        tocolor(255, 255, 255, notif.alpha), 1, fSmall, "left", "center", true)
end

-- ---
-- RENDER
-- ---
addEventHandler("onClientRender", root, function()
    drawNotif()
    if not isOpen then return end
    dxDrawRectangle(px, py, pw, ph, bg)
    dxDrawRectangle(px, py, pw, math.floor(3 * sy), purple)
    clickZones = {}
    drawHeader()
    if screen == "main" then drawMain()
    elseif screen == "send" then drawSend()
    elseif screen == "receive" then drawReceive()
    elseif screen == "tokens" then drawTokens()
    elseif screen == "wallets" then drawWallets()
    elseif screen == "addwallet" then drawAddWallet()
    elseif screen == "mnemonic" then drawMnemonic()
    elseif screen == "activity" then drawActivity()
    elseif screen == "txdetail" then drawTxDetail()
    end
    drawNav()
end)

-- ---
-- CLICK HANDLER (uses clickZones from render)
-- ---
addEventHandler("onClientClick", root, function(button, state)
    if button ~= "left" or state ~= "down" or not isOpen then return end

    -- Check input focus first
    local clickedInput = false
    for id, inp in pairs(inputs) do
        if inp._x and inRect(inp._x, inp._y, inp._w, inp._h) then
            focusedInput = id
            clickedInput = true
            guiSetInputEnabled(true)
        end
    end
    if not clickedInput then
        focusedInput = nil
        guiSetInputEnabled(false)
    end

    -- Check clickZones
    for id, z in pairs(clickZones) do
        if inRect(z.x, z.y, z.w, z.h) then
            handleClick(id)
            return
        end
    end
end)

function handleClick(id)
    -- Universal
    if id == "close" then toggleWallet(); return end
    if id == "back" then
        if screen == "addwallet" then screen = "wallets"
        elseif screen == "mnemonic" then screen = "main"
        elseif screen == "txdetail" then screen = "activity"
        else screen = "main" end
        deleteConfirm = nil; return
    end
    if id == "network" then
        network = network == "devnet" and "mainnet-beta" or "devnet"
        showNotif("Network: " .. network, "warn")
        if selWallet then refreshBalance(); refreshTokens() end
        return
    end
    if id == "currency" then
        if currency == "SOL" then currency = "USD"
        elseif currency == "USD" then currency = "IDR"
        else currency = "SOL" end
        showNotif("Display: " .. currency, "success")
        return
    end
    -- Nav
    if id:sub(1, 4) == "nav_" then
        screen = id:sub(5)
        if screen == "activity" then refreshHistory() end
        if screen == "main" then refreshTokens(); refreshBalance() end
        if screen == "send" then sendMode = "SOL"; sendToken = nil end
        return
    end

    -- Main
    if screen == "main" then
        if id == "create" then screen = "addwallet" end
        if id == "send" then sendMode = "SOL"; sendToken = nil; screen = "send" end
        if id == "receive" then screen = "receive" end
        if id == "copy" and selWallet then setClipboard(selWallet.address); showNotif("Copied!", "success") end
        -- Click SOL row -> send SOL
        if id == "send_sol" then sendMode = "SOL"; sendToken = nil; screen = "send" end
        -- Click token row -> send that token
        for i, tk in ipairs(tokens) do
            if id == "send_token_" .. i then
                sendMode = tk.symbol or "TOKEN"
                sendToken = tk
                screen = "send"
            end
        end

    -- Send
    elseif screen == "send" then
        if id == "confirm_send" then
            local to = getInput("send_to")
            local amt = getInput("send_amt")
            if #to > 30 and tonumber(amt) then
                if sendMode == "SOL" then
                    triggerServerEvent("sol:sendSOL", localPlayer, selWallet.id, to, amt, network)
                    showNotif("Sending " .. amt .. " SOL...", "warn")
                else
                    -- Send SPL token
                    triggerServerEvent("sol:sendToken", localPlayer, selWallet.id, sendToken.pubkey, to, amt, sendToken.mint, sendToken.decimals or 0, sendToken.tokenProgram, network)
                    showNotif("Sending " .. amt .. " " .. sendMode .. "...", "warn")
                end
            else
                showNotif("Invalid address or amount", "error")
            end
        end

    -- Receive
    elseif screen == "receive" then
        if id == "copy_addr" and selWallet then setClipboard(selWallet.address); showNotif("Copied!", "success") end

    -- Tokens
    elseif screen == "tokens" then
        if id == "refresh" then refreshTokens(); showNotif("Refreshing...", "warn") end

    -- Wallets
    elseif screen == "wallets" then
        if id == "addwallet" then screen = "addwallet"; deleteConfirm = nil end
        if id == "confirm_del" and deleteConfirm then
            triggerServerEvent("sol:deleteWallet", localPlayer, deleteConfirm)
            if selWallet and selWallet.id == deleteConfirm then selWallet = nil; balance = nil end
            deleteConfirm = nil
        end
        if id == "cancel_del" then deleteConfirm = nil end
        for i, wl in ipairs(wallets) do
            if id == "select_" .. i then
                selWallet = wl; network = wl.network or "devnet"; screen = "main"
                refreshBalance(); refreshTokens(); deleteConfirm = nil
                showNotif("Switched: " .. shortAddr(wl.address), "success")
            end
            if id == "delete_" .. i then
                deleteConfirm = wl.id
                showNotif("Confirm delete?", "warn")
            end
        end

    -- Add wallet
    elseif screen == "addwallet" then
        if id == "create_new" then
            triggerServerEvent("sol:createWallet", localPlayer, "Wallet " .. (#wallets + 1), network)
            showNotif("Creating...", "warn")
        end
        if id == "gen_mnemonic" then
            screen = "mnemonic"; mnemonicPhrase = nil
            triggerServerEvent("sol:createMnemonic", localPlayer, "Mnemonic " .. (#wallets + 1), network)
        end
        if id == "do_import" then
            local key = getInput("import_key")
            local name = getInput("import_name")
            if #key > 20 then
                triggerServerEvent("sol:importWallet", localPlayer, key, #name > 0 and name or nil, network)
                showNotif("Importing...", "warn")
                clearAllInputs()
            else
                showNotif("Paste a key first (Ctrl+V)", "error")
            end
        end

    -- Mnemonic
    elseif screen == "mnemonic" then
        if id == "copy_phrase" and mnemonicPhrase then
            setClipboard(mnemonicPhrase); showNotif("Phrase copied!", "success")
        end

    -- Activity
    elseif screen == "activity" then
        if id == "refresh_history" then refreshHistory(); showNotif("Refreshing...", "warn") end
        for i, tx in ipairs(txHistory) do
            if id == "copy_tx_" .. i then
                setClipboard(tx.signature or "")
                showNotif("TX sig copied!", "success")
            end
            if id == "detail_tx_" .. i then
                txDetail = tx
                txDetailData = nil  -- reset, will be loaded
                screen = "txdetail"
                triggerServerEvent("sol:fetchTxDetail", localPlayer, tx.signature, network)
            end
        end

    -- TX Detail
    elseif screen == "txdetail" then
        if id == "copy_sig" and txDetail then
            setClipboard(txDetail.signature or "")
            showNotif("Signature copied!", "success")
        end
        if id == "see_explorer" and txDetail then
            local cluster = network == "mainnet-beta" and "" or "?cluster=" .. network
            local url = "https://solscan.io/tx/" .. (txDetail.signature or "") .. cluster
            setClipboard(url)
            showNotif("Solscan URL copied!", "success")
        end
    end
end

-- ---
-- KEYBOARD (typing + paste)
-- ---
addEventHandler("onClientCharacter", root, function(char)
    if not isOpen or not focusedInput then return end
    local inp = inputs[focusedInput]
    if inp then inp.text = inp.text .. char end
end)

addEventHandler("onClientKey", root, function(key, press)
    if not press then return end
    if not isOpen then return end

    if key == "escape" then
        if focusedInput then
            focusedInput = nil; guiSetInputEnabled(false)
        elseif screen ~= "main" then
            screen = "main"; deleteConfirm = nil
        else
            toggleWallet()
        end
        return
    end

    if focusedInput then
        local inp = inputs[focusedInput]
        if not inp then return end

        if key == "backspace" then
            if #inp.text > 0 then inp.text = inp.text:sub(1, -2) end
        elseif key == "v" and getKeyState("lctrl") then
            -- Ctrl+V paste from clipboard
            -- MTA doesn't have direct clipboard read, but guiSetInputEnabled + onClientPaste handles it
            -- Fallback: user types manually
        elseif key == "tab" then
            -- Cycle to next input
            local ids = {}
            for id in pairs(inputs) do ids[#ids + 1] = id end
            table.sort(ids)
            for i, id in ipairs(ids) do
                if id == focusedInput then
                    focusedInput = ids[i % #ids + 1]
                    break
                end
            end
        end
    end
end)

-- Handle paste event
addEventHandler("onClientPaste", root, function(text)
    if not isOpen or not focusedInput then return end
    local inp = inputs[focusedInput]
    if inp then inp.text = inp.text .. text end
end)

-- ---
-- TOGGLE
-- ---
function toggleWallet()
    isOpen = not isOpen
    showCursor(isOpen)
    if isOpen then
        triggerServerEvent("sol:getWallets", localPlayer)
        triggerServerEvent("sol:getPrices", localPlayer)
        if selWallet then refreshBalance(); refreshTokens() end
    else
        focusedInput = nil
        guiSetInputEnabled(false)
    end
end

function refreshBalance()
    if not selWallet then return end
    balance = nil
    triggerServerEvent("sol:fetchBalance", localPlayer, selWallet.address, network)
end

function refreshTokens()
    if not selWallet then return end
    tokens = {}
    triggerServerEvent("sol:fetchTokens", localPlayer, selWallet.address, network)
end

function refreshHistory()
    if not selWallet then return end
    txHistory = {}
    triggerServerEvent("sol:fetchHistory", localPlayer, selWallet.address, network, 8)
end

bindKey("F5", "down", toggleWallet)

-- ---
-- SERVER EVENTS
-- ---
addEvent("sol:walletsData", true)
addEventHandler("sol:walletsData", resourceRoot, function(d) wallets = d or {}; if #wallets > 0 and not selWallet then selWallet = wallets[1]; refreshBalance(); refreshTokens() end end)

addEvent("sol:balanceData", true)
addEventHandler("sol:balanceData", resourceRoot, function(r) if r then balance = r end end)

addEvent("sol:tokensData", true)
addEventHandler("sol:tokensData", resourceRoot, function(d) if d then tokens = d end end)

addEvent("sol:historyData", true)
addEventHandler("sol:historyData", resourceRoot, function(d) if d then txHistory = d end end)

addEvent("sol:txDetailData", true)
addEventHandler("sol:txDetailData", resourceRoot, function(d) if d then txDetailData = d end end)

addEvent("sol:pricesData", true)
addEventHandler("sol:pricesData", resourceRoot, function(p)
    if p then livePrices = p end
end)

addEvent("sol:notify", true)
addEventHandler("sol:notify", resourceRoot, function(t, tp) showNotif(t, tp) end)

addEvent("sol:walletCreated", true)
addEventHandler("sol:walletCreated", resourceRoot, function(address, privateKey)
    screen = "main"
    if address then
        outputChatBox("#00FF00[Wallet] #FFFFFFAddress: #14F195" .. tostring(address), 255, 255, 255, true)
    end
    if privateKey then
        outputChatBox("#FF5555[BACKUP] #FFFFFFPrivate Key: #FFAA1E" .. tostring(privateKey), 255, 255, 255, true)
        outputChatBox("#FF5555[WARNING] #FFFFFFSave your private key! It will NOT be shown again.", 255, 255, 255, true)
        setClipboard(tostring(privateKey))
        outputChatBox("#00FF00[INFO] #FFFFFFPrivate key copied to clipboard (Ctrl+V to paste).", 255, 255, 255, true)
    end
end)

addEvent("sol:mnemonicResult", true)
addEventHandler("sol:mnemonicResult", resourceRoot, function(m) mnemonicPhrase = m; screen = "mnemonic" end)

addEvent("sol:sendDone", true)
addEventHandler("sol:sendDone", resourceRoot, function(r, e) if not e then clearAllInputs(); screen = "main"; refreshBalance() end end)

addEvent("sol:exportData", true)
addEventHandler("sol:exportData", resourceRoot, function(k, err)
    if k and #k > 10 then
        local ok = setClipboard(k)
        if ok then
            showNotif("Private key copied! Ctrl+V to paste.", "success")
        else
            -- Clipboard failed, show in chat as fallback
            outputChatBox("#FF6600[Grove] #FFFFFFKey: " .. k, 255, 255, 255, true)
            showNotif("Key shown in chat (clipboard failed)", "warn")
        end
    else
        showNotif(err or "Failed to export key", "error")
    end
end)
