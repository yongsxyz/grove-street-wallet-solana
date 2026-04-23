-- https://github.com/yongsxyz
--[[
    Metaplex Token Creator - Client UI (v2).

    Pure DirectX. F6 toggles. Esc backs out / closes.

    Screens:
      home | wallet_picker | create | info | update | burn
]]

local screenW, screenH = guiGetScreenSize()
local sx, sy = screenW / 1920, screenH / 1080

-- ---
-- Fonts
-- ---

local FONT_PATH = ":resources/Poppins-Bold.ttf"

local function makeFont(size, fallback)
    return dxCreateFont(FONT_PATH, math.floor(size * sy)) or (fallback or "default-bold")
end

local fTiny    = makeFont(9,  "default-bold")   -- labels / captions
local fSmall   = makeFont(11, "default-bold")   -- body
local fBody    = makeFont(13, "default-bold")   -- buttons / rows
local fSub     = makeFont(16, "default-bold")   -- section titles
local fTitle   = makeFont(20, "default-bold")   -- screen titles
local fBig     = makeFont(28, "default-bold")   -- hero numbers

-- ---
-- Palette
-- ---

local c = {
    bg        = tocolor(11, 11, 20, 252),
    bgDim     = tocolor(0, 0, 0, 180),
    card      = tocolor(23, 23, 38, 255),
    cardHov   = tocolor(35, 35, 58, 255),
    cardSoft  = tocolor(20, 20, 32, 255),
    divider   = tocolor(42, 42, 69, 180),
    border    = tocolor(60, 60, 92, 200),

    purple    = tocolor(153, 69, 255, 255),
    purpleHov = tocolor(180, 110, 255, 255),
    purpleDim = tocolor(153, 69, 255, 80),

    green     = tocolor(20, 241, 149, 255),
    greenDim  = tocolor(20, 241, 149, 60),
    orange    = tocolor(255, 170, 30, 255),
    red       = tocolor(240, 60, 60, 255),
    redHov    = tocolor(255, 90, 90, 255),

    white     = tocolor(255, 255, 255, 255),
    dim       = tocolor(200, 200, 215, 255),
    gray      = tocolor(144, 144, 165, 255),
    muted     = tocolor(90, 90, 117, 255),
}

-- ---
-- Panel geometry
-- ---

local pw, ph = math.floor(520 * sx), math.floor(680 * sy)
local px, py = math.floor((screenW - pw) / 2), math.floor((screenH - ph) / 2)

local PAD        = math.floor(20 * sx)
local HDR_H      = math.floor(64 * sy)
local FOOTER_H   = math.floor(40 * sy)
local INPUT_H    = math.floor(36 * sy)
local BTN_H      = math.floor(44 * sy)
local ROW_GAP    = math.floor(10 * sy)
local SECT_GAP   = math.floor(18 * sy)

-- content area
local function contentY()  return py + HDR_H end
local function contentBot() return py + ph - FOOTER_H end

-- ---
-- State
-- ---

local isOpen      = false
local screen      = "home"
local wallets     = {}
local selWallet   = nil
local myTokens    = {}
local selToken    = nil
local remoteAsset = nil
local busy        = false
local busyMsg     = ""
local tokenScroll = 0

local notif = { text = "", col = c.green, alpha = 0, tick = 0 }

local function showNotif(text, kind)
    local col = (kind == "error" and c.red) or (kind == "warn" and c.orange) or c.green
    notif = { text = text, col = col, alpha = 255, tick = getTickCount() }
end

-- ---
-- Auto token icon cache (mirrors solana-example-wallet pattern).
-- Server fetches metadata JSON → image bytes; client writes to a sandboxed
-- file then dxCreateTexture. Falls back to colored letter pill while loading.
-- ---
local _autoIcons     = {}
local _iconRequested = {}

local function requestTokenIcon(mint)
    if not mint or _iconRequested[mint] then return end
    _iconRequested[mint] = true
    triggerServerEvent("mpui:getTokenImage", localPlayer, mint)
end

addEvent("mpui:tokenImageData", true)
addEventHandler("mpui:tokenImageData", resourceRoot, function(mint, bytes, mime, err)
    if err or not bytes or #bytes == 0 then
        _autoIcons[mint] = { state = "failed" }
        return
    end
    local ext = (mime == "image/jpeg") and "jpg"
             or (mime == "image/gif")  and "gif"
             or "png"
    local fname = "_iconcache_" .. mint .. "." .. ext
    if fileExists(fname) then fileDelete(fname) end
    local f = fileCreate(fname)
    if not f then _autoIcons[mint] = { state = "failed" }; return end
    fileWrite(f, bytes)
    fileClose(f)
    local tex = dxCreateTexture(fname)
    if not tex then _autoIcons[mint] = { state = "failed" }; return end
    _autoIcons[mint] = { state = "ready", texture = tex }
end)

-- Comma-group a human integer string. Use this for values that are ALREADY
-- in human units (e.g. the initial supply the user typed into the form —
-- stored locally without decimals adjustment).
local function formatHumanInt(str)
    if str == nil or str == "" or str == "?" then return "?" end
    local s = tostring(str):gsub("^%+", ""):gsub("^0+", "")
    if s == "" then s = "0" end
    if not s:match("^%d+$") then return tostring(str) end  -- bad input
    return s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

-- Convert a raw u64 string like "1000000000000000" to a human-readable
-- string like "1,000,000" by:
--   1. stripping leading zeros
--   2. inserting a decimal point `decimals` places from the right
--   3. trimming trailing zeros from the fractional part
--   4. grouping the integer part with thousands separators
local function formatSupply(rawStr, decimals)
    if rawStr == nil or rawStr == "" or rawStr == "?" then return "?" end
    decimals = tonumber(decimals) or 9

    local s = tostring(rawStr):gsub("^%+", ""):gsub("^0+", "")
    if s == "" then s = "0" end
    if not s:match("^%d+$") then return tostring(rawStr) end  -- bad input, dump as-is

    local intPart, fracPart
    if #s <= decimals then
        intPart  = "0"
        fracPart = string.rep("0", decimals - #s) .. s
    else
        intPart  = s:sub(1, #s - decimals)
        fracPart = s:sub(#s - decimals + 1)
    end
    fracPart = fracPart:gsub("0+$", "")

    -- Commas every 3 digits from the right
    local withCommas = intPart:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    if fracPart == "" then return withCommas end
    return withCommas .. "." .. fracPart
end

-- Deterministic placeholder color from mint address.
local function colorForMint(mint)
    if not mint then return tocolor(120, 120, 140, 255) end
    local r, g, b = 0, 0, 0
    for i = 1, math.min(#mint, 16) do
        local v = string.byte(mint, i)
        r = (r + v * 7)  % 256
        g = (g + v * 13) % 256
        b = (b + v * 19) % 256
    end
    return tocolor(math.max(r, 80), math.max(g, 80), math.max(b, 80), 255)
end

-- Renders icon at (x, y) sz×sz. Tries cached texture, then placeholder.
-- `mint` and `symbol` together let the placeholder draw a recognizable letter.
local function drawTokenIcon(x, y, sz, mint, symbol)
    local entry = mint and _autoIcons[mint]
    if entry and entry.state == "ready" and entry.texture then
        dxDrawImage(x, y, sz, sz, entry.texture)
        return true
    end
    if mint and not entry then requestTokenIcon(mint) end
    -- Placeholder: colored square + first letter
    dxDrawRectangle(x, y, sz, sz, mint and colorForMint(mint) or c.cardSoft)
    local letter = string.upper((symbol or "?"):sub(1, 1))
    dxDrawText(letter, x, y, x + sz, y + sz, c.white, 1, fBody, "center", "center")
    return false
end

-- ---
-- Helpers
-- ---

local function inRect(x, y, w, h)
    if not isCursorShowing() then return false end
    local cx, cy = getCursorPosition()
    if not cx then return false end
    cx, cy = cx * screenW, cy * screenH
    return cx >= x and cx <= x + w and cy >= y and cy <= y + h
end

local function shortAddr(a, head, tail)
    head = head or 6
    tail = tail or 6
    if not a or #a < head + tail + 2 then return a or "?" end
    return a:sub(1, head) .. ".." .. a:sub(-tail)
end

local function fitText(text, maxW, font)
    if not text then return "" end
    if dxGetTextWidth(text, 1, font) <= maxW then return text end
    -- Binary search truncation
    local lo, hi = 1, #text
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if dxGetTextWidth(text:sub(1, mid) .. "..", 1, font) > maxW then hi = mid - 1
        else lo = mid + 1 end
    end
    return text:sub(1, math.max(1, lo - 1)) .. ".."
end

-- Animated "Working..." dots (3 states)
local function dots()
    local n = math.floor((getTickCount() / 400) % 4)
    return string.rep(".", n)
end

-- ---
-- Input system
-- ---

local inputs = {}
local focusedInput = nil
local clickZones = {}

local function addClick(id, x, y, w, h)
    clickZones[id] = { x = x, y = y, w = w, h = h }
end

local function setInput(id, text)
    inputs[id] = inputs[id] or { text = "", placeholder = "", focused = false }
    inputs[id].text = text or ""
end

local function getInput(id)
    return (inputs[id] and inputs[id].text) or ""
end

local function clearAllInputs()
    for k in pairs(inputs) do
        inputs[k].text = ""
    end
    focusedInput = nil
end

local function drawInput(id, x, y, w, h, placeholder)
    inputs[id] = inputs[id] or { text = "", placeholder = placeholder or "", focused = false }
    local inp = inputs[id]
    inp.placeholder = placeholder or inp.placeholder
    local focused = (focusedInput == id)

    -- Reserve a tiny area on the right for the X (clear) button.
    local clrW    = math.floor(22 * sx)
    local actionW = clrW + math.floor(4 * sx)
    local tw      = w - actionW

    local hov = inRect(x, y, tw, h)

    -- Background
    dxDrawRectangle(x, y, tw, h, c.bgDim)
    -- Left accent
    dxDrawRectangle(x, y, math.floor(2 * sx), h,
        focused and c.purple or (hov and c.border or c.divider))
    -- Bottom border
    dxDrawRectangle(x, y + h - math.floor(2 * sy), tw, math.floor(2 * sy),
        focused and c.purple or (hov and c.border or c.divider))

    local displayText = (#inp.text > 0) and inp.text or inp.placeholder
    local textCol = (#inp.text > 0) and c.white or c.muted

    local pad = math.floor(12 * sx)
    local shown = fitText(displayText, tw - pad * 2 - math.floor(4 * sx), fSmall)

    dxDrawText(shown, x + pad, y, x + tw - pad, y + h,
        textCol, 1, fSmall, "left", "center", true)

    if focused and math.floor(getTickCount() / 500) % 2 == 0 then
        local textW = dxGetTextWidth(shown, 1, fSmall)
        local curX = x + pad + math.min(textW, tw - pad * 2)
        dxDrawRectangle(curX, y + math.floor(8 * sy), math.floor(2 * sx),
            h - math.floor(16 * sy), c.green)
    end

    -- Clear (X) button only — paste is handled via Ctrl+V polling below.
    local cbX = x + tw + math.floor(4 * sx)
    local cbHov = inRect(cbX, y, clrW, h)
    dxDrawRectangle(cbX, y, clrW, h, cbHov and c.red or c.cardSoft)
    dxDrawText("X", cbX, y, cbX + clrW, y + h,
        cbHov and c.white or c.muted, 1, fTiny, "center", "center")
    addClick("clear_" .. id, cbX, y, clrW, h)

    inp._x, inp._y, inp._w, inp._h = x, y, tw, h
    return hov
end

-- ---
-- Button primitives
-- ---

local function btnPrimary(x, y, w, h, text, disabled)
    local hov = not disabled and inRect(x, y, w, h)
    local bg = disabled and c.cardSoft or (hov and c.purpleHov or c.purple)
    dxDrawRectangle(x, y, w, h, bg)
    -- Subtle highlight bar on top
    if not disabled then
        dxDrawRectangle(x, y, w, math.floor(1 * sy), tocolor(255, 255, 255, 40))
    end
    local label = disabled and busyMsg ~= "" and (busyMsg .. dots()) or text
    dxDrawText(label, x, y, x + w, y + h,
        disabled and c.muted or c.white, 1, fBody, "center", "center")
    return hov
end

local function btnSecondary(x, y, w, h, text)
    local hov = inRect(x, y, w, h)
    dxDrawRectangle(x, y, w, h, hov and c.cardHov or c.card)
    dxDrawRectangle(x, y, w, math.floor(1 * sy), c.border)
    dxDrawText(text, x, y, x + w, y + h, hov and c.white or c.dim, 1, fBody, "center", "center")
    return hov
end

local function btnDanger(x, y, w, h, text, disabled)
    local hov = not disabled and inRect(x, y, w, h)
    local bg = disabled and c.cardSoft or (hov and c.redHov or c.red)
    dxDrawRectangle(x, y, w, h, bg)
    if not disabled then
        dxDrawRectangle(x, y, w, math.floor(1 * sy), tocolor(255, 255, 255, 40))
    end
    local label = disabled and busyMsg ~= "" and (busyMsg .. dots()) or text
    dxDrawText(label, x, y, x + w, y + h,
        disabled and c.muted or c.white, 1, fBody, "center", "center")
    return hov
end

local function btnGhost(x, y, w, h, text)
    local hov = inRect(x, y, w, h)
    dxDrawText(text, x, y, x + w, y + h, hov and c.purple or c.gray, 1, fSmall, "center", "center")
    return hov
end

-- ---
-- Card with label (subtle panel)
-- ---

local function card(x, y, w, h, hovering)
    dxDrawRectangle(x, y, w, h, hovering and c.cardHov or c.card)
end

local function divider(y)
    dxDrawRectangle(px + PAD, y, pw - PAD * 2, math.floor(1 * sy), c.divider)
end

-- ---
-- Labeled field (label above, input below)
-- ---

local function labeledInput(x, y, w, label, id, placeholder, hint)
    dxDrawText(string.upper(label), x, y, x + w, y + math.floor(14 * sy),
        c.gray, 1, fTiny, "left", "center")
    y = y + math.floor(16 * sy)
    drawInput(id, x, y, w, INPUT_H, placeholder)
    y = y + INPUT_H
    if hint then
        y = y + math.floor(4 * sy)
        dxDrawText(hint, x, y, x + w, y + math.floor(14 * sy),
            c.muted, 1, fTiny, "left", "center")
        y = y + math.floor(14 * sy)
    end
    return y + ROW_GAP
end

-- ---
-- Header
-- ---

local titleByScreen = {
    home          = "My Tokens",
    wallet_picker = "Select Wallet",
    create        = "Create Fungible Token",
    info          = "Token Details",
    update        = "Update Metadata",
    burn          = "Burn Tokens",
}

local subtitleByScreen = {
    home          = "All tokens you've minted with this wallet",
    wallet_picker = "Pick a wallet to act as update authority",
    create        = "Atomic: CreateV1 + ATA + MintTo in one TX",
    info          = "On-chain view of the selected mint",
    update        = "Change on-chain name / symbol / uri / bps",
    burn          = "Permanently destroy tokens from your ATA",
}

local function drawHeader()
    -- Top bar background
    dxDrawRectangle(px, py, pw, HDR_H, c.card)
    -- Accent stripe
    dxDrawRectangle(px, py, pw, math.floor(3 * sy), c.purple)
    -- Divider
    dxDrawRectangle(px, py + HDR_H - math.floor(1 * sy), pw, math.floor(1 * sy), c.divider)

    -- Title + subtitle (left)
    local title = titleByScreen[screen] or "Metaplex"
    local subtitle = subtitleByScreen[screen] or ""
    dxDrawText(title, px + PAD, py + math.floor(8 * sy), px + pw - PAD, py + math.floor(34 * sy),
        c.white, 1, fTitle, "left", "center")
    if subtitle ~= "" then
        dxDrawText(subtitle, px + PAD, py + math.floor(34 * sy), px + pw - PAD,
            py + math.floor(58 * sy), c.gray, 1, fTiny, "left", "center")
    end

    -- Top-right action cluster: back + close
    local ax = px + pw - PAD
    local btnSz = math.floor(30 * sy)
    local btnY = py + math.floor(18 * sy)

    -- Close (always)
    ax = ax - btnSz
    local hovClose = inRect(ax, btnY, btnSz, btnSz)
    dxDrawRectangle(ax, btnY, btnSz, btnSz, hovClose and c.red or c.cardSoft)
    dxDrawText("X", ax, btnY, ax + btnSz, btnY + btnSz,
        hovClose and c.white or c.dim, 1, fBody, "center", "center")
    addClick("close", ax, btnY, btnSz, btnSz)

    -- Back (when not on home)
    if screen ~= "home" then
        ax = ax - btnSz - math.floor(6 * sx)
        local hovBack = inRect(ax, btnY, btnSz, btnSz)
        dxDrawRectangle(ax, btnY, btnSz, btnSz, hovBack and c.cardHov or c.cardSoft)
        dxDrawText("<", ax, btnY, ax + btnSz, btnY + btnSz,
            hovBack and c.white or c.dim, 1, fBody, "center", "center")
        addClick("back", ax, btnY, btnSz, btnSz)
    end
end

-- ---
-- Footer (small network / wallet status line)
-- ---

local function drawFooter()
    local y = py + ph - FOOTER_H
    dxDrawRectangle(px, y, pw, FOOTER_H, c.cardSoft)
    dxDrawRectangle(px, y, pw, math.floor(1 * sy), c.divider)

    -- Left: wallet info
    local left = px + PAD
    dxDrawRectangle(left, y + math.floor((FOOTER_H - 8 * sy) / 2), math.floor(6 * sx),
        math.floor(8 * sy), c.green)
    dxDrawText(selWallet and shortAddr(selWallet) or "no wallet",
        left + math.floor(12 * sx), y, left + math.floor(200 * sx), y + FOOTER_H,
        c.dim, 1, fTiny, "left", "center")

    -- Right: keybind hint
    local right = "F6 toggle  |  Esc back"
    dxDrawText(right, px + pw - PAD - math.floor(200 * sx), y,
        px + pw - PAD, y + FOOTER_H, c.muted, 1, fTiny, "right", "center")
end

-- ---
-- Notif toast (slides in from bottom)
-- ---

local function drawNotif()
    if notif.alpha <= 0 then return end
    local age = getTickCount() - notif.tick
    if age > 3500 then notif.alpha = math.max(0, notif.alpha - 12)
    else notif.alpha = 255 end
    if notif.alpha <= 0 then return end

    local a = notif.alpha
    local nh = math.floor(36 * sy)
    local nw = math.floor((pw - PAD * 2) * 0.7)
    local nx = px + math.floor((pw - nw) / 2)
    local ny = py + ph - FOOTER_H - nh - math.floor(10 * sy)

    dxDrawRectangle(nx, ny, nw, nh, tocolor(0, 0, 0, math.floor(a * 0.92)))
    dxDrawRectangle(nx, ny, math.floor(3 * sx), nh, notif.col)
    dxDrawText(notif.text, nx + math.floor(14 * sx), ny, nx + nw - math.floor(12 * sx),
        ny + nh, notif.col, 1, fSmall, "left", "center")
end

-- ---
-- Screen: wallet_picker
-- ---

local function drawWalletPicker()
    local x, y = px + PAD, contentY() + PAD
    local w = pw - PAD * 2

    if #wallets == 0 then
        card(x, y, w, math.floor(110 * sy), false)
        dxDrawText("No wallets loaded.",
            x, y + math.floor(18 * sy), x + w, y + math.floor(40 * sy),
            c.orange, 1, fSub, "center", "center")
        dxDrawText("Open chat and run:\n/solwallet phrase   or   /solwallet import <key>",
            x, y + math.floor(44 * sy), x + w, y + math.floor(94 * sy),
            c.gray, 1, fSmall, "center", "center", false, true)
        y = y + math.floor(122 * sy)
        if btnSecondary(x, y, w, BTN_H, "Refresh Wallet List") then end
        addClick("refresh_wallets", x, y, w, BTN_H)
        return
    end

    dxDrawText(#wallets .. " wallet" .. (#wallets == 1 and "" or "s") .. " loaded",
        x, y, x + w, y + math.floor(16 * sy), c.gray, 1, fTiny, "left", "center")
    y = y + math.floor(22 * sy)

    local rowH = math.floor(54 * sy)
    for i, addr in ipairs(wallets) do
        if i > 8 then break end
        local hov = inRect(x, y, w, rowH)
        card(x, y, w, rowH, hov)
        dxDrawRectangle(x, y, math.floor(3 * sx), rowH, c.purple)

        -- "Wallet N" label
        dxDrawText("WALLET " .. i, x + math.floor(14 * sx),
            y + math.floor(8 * sy), x + math.floor(140 * sx), y + math.floor(26 * sy),
            c.gray, 1, fTiny, "left", "top")

        -- Address
        dxDrawText(addr, x + math.floor(14 * sx), y + math.floor(22 * sy),
            x + w - math.floor(80 * sx), y + rowH - math.floor(4 * sy),
            c.white, 1, fSmall, "left", "top")

        -- Action marker
        dxDrawText(hov and "OPEN  >" or "open",
            x + w - math.floor(80 * sx), y, x + w - math.floor(12 * sx), y + rowH,
            hov and c.purple or c.muted, 1, fTiny, "right", "center")

        addClick("pick_wallet_" .. i, x, y, w, rowH)
        y = y + rowH + math.floor(8 * sy)
    end

    y = y + math.floor(4 * sy)
    btnSecondary(x, y, w, math.floor(34 * sy), "Refresh")
    addClick("refresh_wallets", x, y, w, math.floor(34 * sy))
end

-- ---
-- Screen: home
-- ---

local function drawHome()
    local x, y = px + PAD, contentY() + PAD
    local w = pw - PAD * 2

    -- Wallet hero card
    local heroH = math.floor(80 * sy)
    card(x, y, w, heroH, false)
    dxDrawRectangle(x, y, math.floor(3 * sx), heroH, c.purple)

    dxDrawText("ACTIVE WALLET", x + math.floor(14 * sx), y + math.floor(10 * sy),
        x + math.floor(200 * sx), y + math.floor(26 * sy),
        c.gray, 1, fTiny, "left", "top")

    local addrText = selWallet or "(none selected)"
    dxDrawText(shortAddr(addrText, 16, 10),
        x + math.floor(14 * sx), y + math.floor(26 * sy),
        x + w - math.floor(110 * sx), y + heroH - math.floor(8 * sy),
        c.white, 1, fSub, "left", "center")

    -- Switch button on the right
    local swW, swH = math.floor(88 * sx), math.floor(30 * sy)
    local swX = x + w - math.floor(14 * sx) - swW
    local swY = y + math.floor((heroH - swH) / 2)
    btnSecondary(swX, swY, swW, swH, "Switch")
    addClick("switch_wallet", swX, swY, swW, swH)

    y = y + heroH + math.floor(14 * sy)

    -- Primary CTA
    btnPrimary(x, y, w, BTN_H, "+ Create New Token")
    addClick("goto_create", x, y, w, BTN_H)
    y = y + BTN_H + SECT_GAP

    -- Section header
    dxDrawText("MY TOKENS", x, y, x + w - math.floor(100 * sx), y + math.floor(16 * sy),
        c.gray, 1, fTiny, "left", "center")
    dxDrawText(tostring(#myTokens),
        x + math.floor(84 * sx), y, x + math.floor(140 * sx), y + math.floor(16 * sy),
        c.purple, 1, fTiny, "left", "center")

    local rX = x + w - math.floor(80 * sx)
    local rhov = inRect(rX, y, math.floor(80 * sx), math.floor(16 * sy))
    dxDrawText("refresh", rX, y, rX + math.floor(80 * sx), y + math.floor(16 * sy),
        rhov and c.purple or c.muted, 1, fTiny, "right", "center")
    addClick("refresh_tokens", rX, y, math.floor(80 * sx), math.floor(16 * sy))
    y = y + math.floor(22 * sy)

    -- Empty state
    if #myTokens == 0 then
        local eh = math.floor(100 * sy)
        card(x, y, w, eh, false)
        dxDrawText("No tokens yet", x, y + math.floor(20 * sy),
            x + w, y + math.floor(44 * sy), c.gray, 1, fSub, "center", "center")
        dxDrawText("Click '+ Create New Token' above to mint your first one.",
            x, y + math.floor(48 * sy), x + w, y + math.floor(80 * sy),
            c.muted, 1, fSmall, "center", "center")
        return
    end

    -- Token list
    local rowH = math.floor(64 * sy)
    local listTop = y
    local listBot = contentBot() - math.floor(10 * sy)
    local visible = math.floor((listBot - listTop) / (rowH + math.floor(8 * sy)))
    local first = tokenScroll + 1
    local last  = math.min(#myTokens, first + visible - 1)

    for i = first, last do
        local tk = myTokens[i]
        local hov = inRect(x, y, w, rowH)
        card(x, y, w, rowH, hov)

        -- Logo (auto-fetched from IPFS metadata, with placeholder fallback)
        local icoSz = math.floor(40 * sy)
        local icoX  = x + math.floor(14 * sx)
        local icoY  = y + math.floor((rowH - icoSz) / 2)
        drawTokenIcon(icoX, icoY, icoSz, tk.mint, tk.symbol)

        -- Name + mint (middle)
        local tL = icoX + icoSz + math.floor(14 * sx)
        local tR = x + w - math.floor(100 * sx)
        dxDrawText(fitText(tk.name or "(no name)", tR - tL, fBody),
            tL, y + math.floor(10 * sy), tR, y + math.floor(32 * sy),
            c.white, 1, fBody, "left", "top")
        dxDrawText(shortAddr(tk.mint, 8, 6),
            tL, y + math.floor(34 * sy), tR, y + rowH - math.floor(6 * sy),
            c.muted, 1, fTiny, "left", "top")

        -- Stats (right)
        local statsX = x + w - math.floor(100 * sx)
        dxDrawText("SUPPLY", statsX, y + math.floor(10 * sy),
            statsX + math.floor(88 * sx), y + math.floor(24 * sy),
            c.muted, 1, fTiny, "right", "top")
        -- Local store's `supply` is what the user typed (already in HUMAN
        -- units), so comma-group without dividing by decimals.
        local supplyStr = formatHumanInt(tk.supply)
        if #supplyStr > 10 then supplyStr = supplyStr:sub(1, 8) .. ".." end
        dxDrawText(supplyStr, statsX, y + math.floor(26 * sy),
            statsX + math.floor(88 * sx), y + math.floor(46 * sy),
            c.white, 1, fBody, "right", "top")
        dxDrawText((tk.decimals or 9) .. " dec",
            statsX, y + math.floor(46 * sy),
            statsX + math.floor(88 * sx), y + rowH - math.floor(6 * sy),
            c.muted, 1, fTiny, "right", "top")

        addClick("open_token_" .. i, x, y, w, rowH)
        y = y + rowH + math.floor(8 * sy)
    end

    -- Scroll hints
    if tokenScroll > 0 then
        dxDrawText("  ^  scroll up  ^", x, listTop - math.floor(14 * sy),
            x + w, listTop, c.muted, 1, fTiny, "center", "center")
    end
    if last < #myTokens then
        dxDrawText("  v  " .. (#myTokens - last) .. " more  v",
            x, listBot, x + w, listBot + math.floor(14 * sy),
            c.muted, 1, fTiny, "center", "center")
    end
end

-- ---
-- Screen: create
-- ---

local function drawCreate()
    local x, y = px + PAD, contentY() + PAD
    local w = pw - PAD * 2

    y = labeledInput(x, y, w, "Name (max 32)",       "c_name",        "e.g. My Fungible Token")
    y = labeledInput(x, y, w, "Symbol (max 10)",     "c_symbol",      "e.g. MFT")
    y = labeledInput(x, y, w, "Description",         "c_description", "What is this token for?")
    y = labeledInput(x, y, w, "Image / Logo URL",    "c_image",       "https://gateway.pinata.cloud/ipfs/<cid>",
        "Upload logo to Pinata web UI first, paste URL here")

    -- Decimals + Supply side-by-side
    local half = math.floor((w - math.floor(12 * sx)) / 2)
    dxDrawText("DECIMALS", x, y, x + half, y + math.floor(14 * sy),
        c.gray, 1, fTiny, "left", "center")
    dxDrawText("INITIAL SUPPLY", x + half + math.floor(12 * sx), y,
        x + w, y + math.floor(14 * sy), c.gray, 1, fTiny, "left", "center")
    y = y + math.floor(16 * sy)
    drawInput("c_decimals", x, y, half, INPUT_H, "9")
    drawInput("c_supply",   x + half + math.floor(12 * sx), y, half, INPUT_H, "1000000")
    y = y + INPUT_H + math.floor(4 * sy)
    dxDrawText("9 = SOL-style, 6 = stablecoin, 0 = whitelist",
        x, y, x + half, y + math.floor(14 * sy), c.muted, 1, fTiny, "left", "center")
    dxDrawText("Human units (1000000 = 1,000,000 tokens)",
        x + half + math.floor(12 * sx), y, x + w, y + math.floor(14 * sy),
        c.muted, 1, fTiny, "left", "center")
    y = y + math.floor(14 * sy) + ROW_GAP

    y = labeledInput(x, y, w, "Seller Fee BPS  (optional)", "c_bps", "0",
        "550 = 5.5%. For fungibles usually 0.")

    -- Primary CTA pinned above footer notif
    local btnY = contentBot() - BTN_H - math.floor(16 * sy)
    busyMsg = busy and "Creating atomic TX" or ""
    btnPrimary(x, btnY, w, BTN_H, "Create & Mint", busy)
    if not busy then addClick("confirm_create", x, btnY, w, BTN_H) end
end

-- ---
-- Screen: info
-- ---

local function drawInfo()
    local x, y = px + PAD, contentY() + PAD
    local w = pw - PAD * 2

    if not selToken then
        dxDrawText("No token selected.", x, y, x + w, y + math.floor(40 * sy),
            c.gray, 1, fSmall, "center", "center")
        return
    end

    -- Hero: local record + on-chain logo
    local heroH = math.floor(100 * sy)
    card(x, y, w, heroH, false)
    dxDrawRectangle(x, y, math.floor(3 * sx), heroH, c.green)

    -- Logo on the left (big — auto-fetched from on-chain metadata)
    local logoSz = math.floor(72 * sy)
    local logoX  = x + math.floor(14 * sx)
    local logoY  = y + math.floor((heroH - logoSz) / 2)
    drawTokenIcon(logoX, logoY, logoSz, selToken.mint, selToken.symbol)

    -- Symbol underneath the logo (small badge)
    local symBadgeW = logoSz
    local symBadgeH = math.floor(16 * sy)
    -- (skipping a separate badge — symbol shows on placeholder pill anyway)

    -- Name + symbol + mint
    local tL = logoX + logoSz + math.floor(14 * sx)
    local tR = x + w - math.floor(14 * sx)
    dxDrawText(fitText(selToken.name or "(no name)", tR - tL, fSub),
        tL, y + math.floor(10 * sy), tR, y + math.floor(34 * sy),
        c.white, 1, fSub, "left", "top")
    dxDrawText(selToken.symbol or "?",
        tL, y + math.floor(34 * sy), tR, y + math.floor(52 * sy),
        c.purple, 1, fBody, "left", "top")
    dxDrawText(shortAddr(selToken.mint, 10, 8),
        tL, y + math.floor(56 * sy), tR, y + math.floor(74 * sy),
        c.green, 1, fSmall, "left", "top")

    -- Footer of hero: decimals + supply. Source matters for formatting:
    --   * on-chain (remoteAsset.mintInfo.supply) is RAW u64 → divide by 10^dec
    --   * local store (selToken.supply) is HUMAN (what user typed) → just add commas
    local supplyText, decimals, supplyLabel
    if remoteAsset and remoteAsset.mintInfo and remoteAsset.mintInfo.supply then
        decimals    = remoteAsset.mintInfo.decimals or selToken.decimals or 9
        supplyText  = formatSupply(remoteAsset.mintInfo.supply, decimals)
        supplyLabel = "supply"
    else
        decimals    = selToken.decimals or 9
        supplyText  = formatHumanInt(selToken.supply)
        supplyLabel = "initial supply"
    end
    dxDrawText("dec " .. tostring(decimals) ..
        "  |  " .. supplyLabel .. " " .. supplyText,
        tL, y + heroH - math.floor(20 * sy),
        tR, y + heroH - math.floor(4 * sy),
        c.muted, 1, fTiny, "left", "center")
    y = y + heroH + math.floor(12 * sy)

    -- Action row: 3 equal buttons
    local bw = math.floor((w - math.floor(16 * sx)) / 3)
    btnSecondary(x, y, bw, BTN_H, "Refresh")
    addClick("refresh_asset", x, y, bw, BTN_H)
    btnPrimary(x + bw + math.floor(8 * sx), y, bw, BTN_H, "Update")
    addClick("goto_update", x + bw + math.floor(8 * sx), y, bw, BTN_H)
    btnDanger(x + (bw + math.floor(8 * sx)) * 2, y, bw, BTN_H, "Burn")
    addClick("goto_burn", x + (bw + math.floor(8 * sx)) * 2, y, bw, BTN_H)
    y = y + BTN_H + SECT_GAP

    -- On-chain section
    dxDrawText("ON-CHAIN", x, y, x + w - math.floor(60 * sx),
        y + math.floor(16 * sy), c.gray, 1, fTiny, "left", "center")
    if selToken.uri then
        local cpX = x + w - math.floor(60 * sx)
        local cpHov = inRect(cpX, y, math.floor(60 * sx), math.floor(16 * sy))
        dxDrawText(cpHov and "copy URI" or "copy URI",
            cpX, y, cpX + math.floor(60 * sx), y + math.floor(16 * sy),
            cpHov and c.purple or c.muted, 1, fTiny, "right", "center")
        addClick("copy_uri", cpX, y, math.floor(60 * sx), math.floor(16 * sy))
    end
    y = y + math.floor(20 * sy)
    divider(y - math.floor(4 * sy))

    if not remoteAsset then
        local eh = math.floor(80 * sy)
        card(x, y, w, eh, false)
        dxDrawText(busy and ("Loading" .. dots()) or "Click Refresh to load on-chain data",
            x, y, x + w, y + eh, c.gray, 1, fSmall, "center", "center")
        return
    end

    local md = remoteAsset.metadata or {}
    local mi = remoteAsset.mintInfo or {}

    local function fact(label, value, valueCol, copyId)
        local rh = math.floor(28 * sy)
        local hov = inRect(x, y, w, rh)
        dxDrawRectangle(x, y, w, rh, hov and c.cardHov or c.card)
        dxDrawText(label, x + math.floor(14 * sx), y,
            x + math.floor(140 * sx), y + rh, c.gray, 1, fTiny, "left", "center")
        local vStr = tostring(value or "?")
        dxDrawText(fitText(vStr, w - math.floor(160 * sx), fSmall),
            x + math.floor(140 * sx), y, x + w - math.floor(14 * sx), y + rh,
            valueCol or c.white, 1, fSmall, "left", "center")
        if copyId and hov then
            -- Clickable row
            addClick(copyId, x, y, w, rh)
        end
        y = y + rh + math.floor(4 * sy)
    end

    fact("name",        md.name)
    fact("symbol",      md.symbol)
    fact("uri",         md.uri)
    -- Show the human-readable supply (derived using on-chain decimals),
    -- and the raw u64 below it — sometimes you need the raw value to
    -- double-check burns, airdrops, etc.
    fact("supply",      formatSupply(mi.supply, mi.decimals))
    fact("supply raw",  tostring(mi.supply or "?"), c.muted)
    fact("decimals",    mi.decimals)
    fact("isMutable",   tostring(md.isMutable),
        md.isMutable == false and c.red or c.green)
    fact("update auth", shortAddr(md.updateAuthority or "", 8, 6))
    fact("mint auth",   shortAddr(mi.mintAuthority or "(none)", 8, 6))
end

-- ---
-- Screen: update
-- ---

local function drawUpdate()
    local x, y = px + PAD, contentY() + PAD
    local w = pw - PAD * 2

    -- Info callout
    local ih = math.floor(48 * sy)
    dxDrawRectangle(x, y, w, ih, tocolor(60, 40, 10, 240))
    dxDrawRectangle(x, y, math.floor(3 * sx), ih, c.orange)
    dxDrawText("Leave fields blank to keep the current on-chain value.",
        x + math.floor(14 * sx), y, x + w - math.floor(14 * sx), y + math.floor(26 * sy),
        c.orange, 1, fSmall, "left", "top")
    dxDrawText("Requires: isMutable=true + wallet = update authority.",
        x + math.floor(14 * sx), y + math.floor(24 * sy),
        x + w - math.floor(14 * sx), y + ih - math.floor(4 * sy),
        c.muted, 1, fTiny, "left", "top")
    y = y + ih + math.floor(14 * sy)

    y = labeledInput(x, y, w, "New Name",   "u_name",   selToken and selToken.name   or "")
    y = labeledInput(x, y, w, "New Symbol", "u_symbol", selToken and selToken.symbol or "")
    y = labeledInput(x, y, w, "New URI",    "u_uri",    selToken and selToken.uri    or "")
    y = labeledInput(x, y, w, "New BPS",    "u_bps",    tostring(selToken and selToken.bps or 0))

    local btnY = contentBot() - BTN_H - math.floor(16 * sy)
    busyMsg = busy and "Submitting updateV1" or ""
    btnPrimary(x, btnY, w, BTN_H, "Apply Update", busy)
    if not busy then addClick("confirm_update", x, btnY, w, BTN_H) end
end

-- ---
-- Screen: burn
-- ---

local function drawBurn()
    local x, y = px + PAD, contentY() + PAD
    local w = pw - PAD * 2

    -- Danger banner
    local ih = math.floor(54 * sy)
    dxDrawRectangle(x, y, w, ih, tocolor(50, 10, 10, 245))
    dxDrawRectangle(x, y, math.floor(3 * sx), ih, c.red)
    dxDrawText("PERMANENT & IRREVERSIBLE",
        x + math.floor(14 * sx), y + math.floor(6 * sy),
        x + w - math.floor(14 * sx), y + math.floor(30 * sy),
        c.red, 1, fBody, "left", "top")
    dxDrawText("Burned tokens cannot be recovered. Total supply decreases.",
        x + math.floor(14 * sx), y + math.floor(28 * sy),
        x + w - math.floor(14 * sx), y + ih - math.floor(6 * sy),
        c.dim, 1, fTiny, "left", "top")
    y = y + ih + math.floor(14 * sy)

    -- Target token card
    if selToken then
        local th = math.floor(60 * sy)
        card(x, y, w, th, false)
        dxDrawRectangle(x, y, math.floor(3 * sx), th, c.red)

        local icoSz = math.floor(40 * sy)
        local icoX  = x + math.floor(14 * sx)
        local icoY  = y + math.floor((th - icoSz) / 2)
        drawTokenIcon(icoX, icoY, icoSz, selToken.mint, selToken.symbol)

        local tL = icoX + icoSz + math.floor(14 * sx)
        dxDrawText(fitText(selToken.name or "(no name)", w - math.floor(100 * sx), fBody),
            tL, y, x + w - math.floor(14 * sx), y + math.floor(34 * sy),
            c.white, 1, fBody, "left", "center")
        dxDrawText(shortAddr(selToken.mint, 8, 6),
            tL, y + math.floor(30 * sy),
            x + w - math.floor(14 * sx), y + th - math.floor(4 * sy),
            c.muted, 1, fTiny, "left", "top")
        y = y + th + math.floor(14 * sy)
    end

    y = labeledInput(x, y, w, "Amount (human units)", "b_amount", "e.g. 100")
    y = labeledInput(x, y, w, "Decimals (keep unless you know otherwise)", "b_decimals",
        tostring(selToken and selToken.decimals or 9))

    local btnY = contentBot() - BTN_H - math.floor(16 * sy)
    busyMsg = busy and "Burning" or ""
    btnDanger(x, btnY, w, BTN_H, "Confirm Burn", busy)
    if not busy then addClick("confirm_burn", x, btnY, w, BTN_H) end
end

-- ---
-- Main render pipeline
-- ---

addEventHandler("onClientRender", root, function()
    if not isOpen then return end
    clickZones = {}

    dxDrawRectangle(px, py, pw, ph, c.bg)

    drawHeader()

    if     screen == "home"          then drawHome()
    elseif screen == "wallet_picker" then drawWalletPicker()
    elseif screen == "create"        then drawCreate()
    elseif screen == "info"          then drawInfo()
    elseif screen == "update"        then drawUpdate()
    elseif screen == "burn"          then drawBurn()
    end

    drawFooter()
    drawNotif()
end)

-- ---
-- Toggle + server-triggered events
-- ---

local function openUI()
    isOpen = true
    showCursor(true)
    triggerServerEvent("mpui:getWallets", resourceRoot)
end

local function closeUI()
    isOpen = false
    showCursor(false)
    guiSetInputEnabled(false)
    focusedInput = nil
end

function toggleUI()
    if isOpen then closeUI() else openUI() end
end

bindKey("F6", "down", toggleUI)

addEvent("mpui:walletsData", true)
addEventHandler("mpui:walletsData", resourceRoot, function(list)
    wallets = list or {}
    if not selWallet and #wallets > 0 then
        selWallet = wallets[1]
        triggerServerEvent("mpui:getTokens", resourceRoot, selWallet)
        screen = "home"
    elseif #wallets == 0 then
        screen = "wallet_picker"
    end
end)

addEvent("mpui:tokensData", true)
addEventHandler("mpui:tokensData", resourceRoot, function(walletAddr, list)
    if walletAddr ~= selWallet then return end
    myTokens = list or {}
    if tokenScroll > math.max(0, #myTokens - 1) then tokenScroll = 0 end
end)

addEvent("mpui:createResult", true)
addEventHandler("mpui:createResult", resourceRoot, function(ok, payload, refreshedList)
    busy = false
    if not ok then
        showNotif("Create failed: " .. tostring(payload), "error")
        return
    end
    showNotif("Token created: " .. shortAddr(payload.mint), "success")
    if refreshedList then myTokens = refreshedList end
    clearAllInputs()
    for _, tk in ipairs(myTokens) do
        if tk.mint == payload.mint then
            selToken = tk
            remoteAsset = nil
            screen = "info"
            break
        end
    end
end)

addEvent("mpui:assetData", true)
addEventHandler("mpui:assetData", resourceRoot, function(ok, payload)
    busy = false
    if not ok then
        showNotif("Fetch failed: " .. tostring(payload), "error")
        remoteAsset = nil
        return
    end
    remoteAsset = payload
end)

addEvent("mpui:updateResult", true)
addEventHandler("mpui:updateResult", resourceRoot, function(ok, payload, refreshedList)
    busy = false
    if not ok then
        showNotif("Update failed: " .. tostring(payload), "error")
        return
    end
    showNotif("Metadata updated", "success")
    if refreshedList then
        myTokens = refreshedList
        if selToken then
            for _, tk in ipairs(myTokens) do
                if tk.mint == selToken.mint then selToken = tk; break end
            end
        end
    end
    clearAllInputs()
    remoteAsset = nil
    screen = "info"
    -- Auto re-fetch so updated metadata shows immediately
    if selToken and selToken.mint then
        triggerServerEvent("mpui:getAsset", resourceRoot, selToken.mint)
    end
end)

addEvent("mpui:burnResult", true)
addEventHandler("mpui:burnResult", resourceRoot, function(ok, payload)
    busy = false
    if not ok then
        showNotif("Burn failed: " .. tostring(payload), "error")
        return
    end
    showNotif("Burn complete", "success")
    clearAllInputs()
    remoteAsset = nil
    screen = "info"
    -- Auto re-fetch so the new (lower) supply shows immediately
    if selToken and selToken.mint then
        triggerServerEvent("mpui:getAsset", resourceRoot, selToken.mint)
    end
end)

-- ---
-- Click dispatch
-- ---

local function handleClick(id)
    if id == "close" then closeUI(); return end

    -- Clear button (per-input X)
    if id:sub(1, 6) == "clear_" then
        local inpId = id:sub(7)
        if inputs[inpId] then inputs[inpId].text = "" end
        focusedInput = inpId
        guiSetInputEnabled(true)
        return
    end

    if id == "back" then
        if screen == "info" then screen = "home"; remoteAsset = nil
        elseif screen == "update" or screen == "burn" then screen = "info"
        elseif screen == "create" then screen = "home"
        elseif screen == "wallet_picker" then screen = "home"
        else screen = "home" end
        return
    end
    if id == "refresh_wallets" then
        triggerServerEvent("mpui:getWallets", resourceRoot); return
    end
    if id == "switch_wallet" then screen = "wallet_picker"; return end
    if id:sub(1, 12) == "pick_wallet_" then
        local idx = tonumber(id:sub(13))
        if idx and wallets[idx] then
            selWallet = wallets[idx]
            myTokens = {}
            selToken = nil
            triggerServerEvent("mpui:getTokens", resourceRoot, selWallet)
            screen = "home"
            showNotif("Wallet: " .. shortAddr(selWallet), "success")
        end
        return
    end

    if screen == "home" then
        if id == "goto_create" then screen = "create"; return end
        if id == "refresh_tokens" and selWallet then
            triggerServerEvent("mpui:getTokens", resourceRoot, selWallet)
            showNotif("Refreshing", "success"); return
        end
        if id:sub(1, 11) == "open_token_" then
            local idx = tonumber(id:sub(12))
            if idx and myTokens[idx] then
                selToken = myTokens[idx]
                remoteAsset = nil
                screen = "info"
                -- Auto-refresh on-chain data so the displayed supply reflects
                -- the current mint state (not the stale "initial supply").
                if selToken.mint then
                    triggerServerEvent("mpui:getAsset", resourceRoot, selToken.mint)
                end
            end
            return
        end
    end

    if screen == "create" and id == "confirm_create" then
        if not selWallet then showNotif("No wallet", "error") return end
        local payload = {
            wallet      = selWallet,
            name        = getInput("c_name"),
            symbol      = getInput("c_symbol"),
            description = getInput("c_description"),
            image       = getInput("c_image"),
            decimals    = tonumber(getInput("c_decimals")) or 9,
            supply      = getInput("c_supply"),
            bps         = tonumber(getInput("c_bps")) or 0,
        }
        if #payload.name == 0 or #payload.symbol == 0 or #payload.supply == 0 then
            showNotif("Fill name, symbol, and supply", "warn")
            return
        end
        busy = true
        showNotif("Uploading metadata to IPFS + minting...", "success")
        triggerServerEvent("mpui:createToken", resourceRoot, payload)
        return
    end

    if screen == "info" then
        if id == "goto_update" then
            setInput("u_name",   selToken and selToken.name   or "")
            setInput("u_symbol", selToken and selToken.symbol or "")
            setInput("u_uri",    selToken and selToken.uri    or "")
            setInput("u_bps",    tostring(selToken and selToken.bps or 0))
            screen = "update"; return
        end
        if id == "goto_burn" then
            setInput("b_amount", "")
            setInput("b_decimals", tostring(selToken and selToken.decimals or 9))
            screen = "burn"; return
        end
        if id == "refresh_asset" and selToken then
            busy = true
            remoteAsset = nil
            triggerServerEvent("mpui:getAsset", resourceRoot, selToken.mint)
            showNotif("Fetching asset", "success")
            return
        end
        if id == "copy_uri" and selToken and selToken.uri then
            if setClipboard then
                setClipboard(selToken.uri)
                showNotif("URI copied", "success")
            else
                outputChatBox("#9b45ff[Token]#ffffff URI: " .. selToken.uri, 255, 255, 255, true)
                showNotif("URI printed to chat (clipboard unsupported)", "warn")
            end
            return
        end
    end

    if screen == "update" and id == "confirm_update" then
        if not selWallet or not selToken then showNotif("No token", "error"); return end
        busy = true
        showNotif("Fetching + submitting", "success")
        triggerServerEvent("mpui:updateToken", resourceRoot, {
            wallet = selWallet,
            mint   = selToken.mint,
            name   = getInput("u_name"),
            symbol = getInput("u_symbol"),
            uri    = getInput("u_uri"),
            bps    = tonumber(getInput("u_bps")),
        })
        return
    end

    if screen == "burn" and id == "confirm_burn" then
        if not selWallet or not selToken then showNotif("No token", "error"); return end
        -- Defensive: make sure mint is a valid base58 string
        local mint = tostring(selToken.mint or "")
        if #mint < 32 then
            showNotif("Selected token has no mint address", "error"); return
        end
        local amount = getInput("b_amount"):gsub("^%s+", ""):gsub("%s+$", "")
        if not amount:match("^%d+$") or amount == "0" then
            showNotif("Enter positive whole number (no commas/dots)", "warn"); return
        end
        local decimals = tonumber(getInput("b_decimals"))
                      or tonumber(selToken.decimals) or 9
        if decimals < 0 or decimals > 18 then
            showNotif("Decimals out of range (0-18)", "warn"); return
        end
        busy = true
        showNotif("Burning " .. amount .. " @ " .. decimals .. " dec...", "success")
        triggerServerEvent("mpui:burnTokens", resourceRoot, {
            wallet      = selWallet,
            mint        = mint,
            humanAmount = amount,
            decimals    = decimals,
        })
        return
    end
end

-- ---
-- Cursor / click / input plumbing
-- ---

addEventHandler("onClientClick", root, function(button, state)
    if button ~= "left" or state ~= "down" or not isOpen then return end

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

    for id, z in pairs(clickZones) do
        if inRect(z.x, z.y, z.w, z.h) then
            handleClick(id); return
        end
    end
end)

addEventHandler("onClientKey", root, function(key, press)
    if not isOpen or not press then return end

    if screen == "home" then
        if key == "mouse_wheel_up"   then tokenScroll = math.max(0, tokenScroll - 1) end
        if key == "mouse_wheel_down" then tokenScroll = math.min(math.max(0, #myTokens - 1), tokenScroll + 1) end
    end

    if key == "escape" then
        if focusedInput then focusedInput = nil; guiSetInputEnabled(false)
        elseif screen ~= "home" then handleClick("back")
        else closeUI() end
        return
    end

    if focusedInput and inputs[focusedInput] then
        local inp = inputs[focusedInput]
        if key == "backspace" and #inp.text > 0 then
            inp.text = inp.text:sub(1, -2)
        elseif key == "tab" then
            local keys = {}
            for k in pairs(inputs) do keys[#keys + 1] = k end
            table.sort(keys)
            local current = 0
            for i, k in ipairs(keys) do if k == focusedInput then current = i break end end
            focusedInput = keys[(current % #keys) + 1]
        end
    end
end)

-- ---
-- Ctrl+V paste — uses MTA's onClientPaste event (works in all MTA versions
-- since 1.5.0). We do NOT use getClipboard() — it doesn't exist in MTA
-- versions before 1.5.6 and would throw "attempt to call global getClipboard".
-- ---
addEventHandler("onClientPaste", root, function(text)
    if not isOpen or not focusedInput then return end
    local inp = inputs[focusedInput]
    if not inp then return end
    inp.text = (inp.text or "") .. (text or "")
    showNotif("Pasted " .. #(text or "") .. " chars", "success")
end)

addEventHandler("onClientCharacter", root, function(char)
    if not isOpen or not focusedInput then return end
    -- Ctrl is held? Skip character append. Otherwise Ctrl+V would produce
    -- "<clipboard>v" (paste appends clipboard, then this appends "v").
    if getKeyState("lctrl") or getKeyState("rctrl") then return end
    local inp = inputs[focusedInput]
    if not inp then return end
    inp.text = inp.text .. char
end)

-- ---
-- Startup hint
-- ---

addEventHandler("onClientResourceStart", resourceRoot, function()
    outputChatBox("#9b45ff[Metaplex UI]#ffffff  Press  #ffaa1eF6#ffffff  to open.",
        255, 255, 255, true)
end)
