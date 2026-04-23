-- https://github.com/yongsxyz
--[[
    Metaplex Agent Creator - Client UI.

    DirectX panel. F7 toggles. Esc backs out / closes.

    Screens:
      home          - list of agents created with the selected wallet
      wallet_picker - pick wallet from solana-sdk's store
      create        - Identity form (name, description, image URL)
      info          - detailed view of an agent (PDAs, balances, metaplex link)
      deposit       - transfer SOL from wallet to agent's PDA
]]

local screenW, screenH = guiGetScreenSize()
local sx, sy = screenW / 1920, screenH / 1080

-- ---
-- Fonts (Poppins-Bold from :resources, fallback to default-bold)
-- ---

local FONT_PATH = ":resources/Poppins-Bold.ttf"
local function makeFont(size) return dxCreateFont(FONT_PATH, math.floor(size * sy)) or "default-bold" end

local fTiny  = makeFont(9)
local fSmall = makeFont(11)
local fBody  = makeFont(13)
local fSub   = makeFont(16)
local fTitle = makeFont(20)
local fBig   = makeFont(28)

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

local PAD       = math.floor(20 * sx)
local HDR_H     = math.floor(64 * sy)
local FOOTER_H  = math.floor(40 * sy)
local INPUT_H   = math.floor(36 * sy)
local BTN_H     = math.floor(44 * sy)
local ROW_GAP   = math.floor(10 * sy)
local SECT_GAP  = math.floor(18 * sy)

local function contentY()   return py + HDR_H end
local function contentBot() return py + ph - FOOTER_H end

-- ---
-- State
-- ---

local isOpen      = false
local screen      = "home"
local wallets     = {}
local selWallet   = nil
local myAgents    = {}
local selAgent    = nil
local pdaBalance  = nil        -- SOL balance of selAgent.agentSigner
local busy        = false
local busyMsg     = ""
local agentScroll = 0

local notif = { text = "", col = c.green, alpha = 0, tick = 0 }

-- ERC-8004 extras (Advanced section on the Create form)
local trustFlags = {
    ["reputation"]       = true,
    ["crypto-economic"]  = false,
    ["tee-attestation"]  = false,
}
local x402Enabled = false

-- ---
-- Auto agent icon cache (mirrors token UI pattern).
-- Server downloads the logo bytes; client writes to a sandboxed file then
-- dxCreateTexture. Falls back to a colored letter pill while loading.
-- ---
local _autoIcons     = {}
local _iconRequested = {}

local function requestAgentIcon(agent)
    if not agent or _iconRequested[agent] then return end
    _iconRequested[agent] = true
    triggerServerEvent("mpaui:getAgentImage", localPlayer, agent)
end

addEvent("mpaui:agentImageData", true)
addEventHandler("mpaui:agentImageData", resourceRoot, function(agent, bytes, mime, err)
    if err or not bytes or #bytes == 0 then
        _autoIcons[agent] = { state = "failed" }
        return
    end
    local ext = (mime == "image/jpeg") and "jpg"
             or (mime == "image/gif")  and "gif"
             or "png"
    local fname = "_iconcache_" .. agent .. "." .. ext
    if fileExists(fname) then fileDelete(fname) end
    local f = fileCreate(fname)
    if not f then _autoIcons[agent] = { state = "failed" }; return end
    fileWrite(f, bytes)
    fileClose(f)
    local tex = dxCreateTexture(fname)
    if not tex then _autoIcons[agent] = { state = "failed" }; return end
    _autoIcons[agent] = { state = "ready", texture = tex }
end)

-- Deterministic placeholder color from an agent address
local function colorForAgent(addr)
    if not addr then return tocolor(120, 120, 140, 255) end
    local r, g, b = 0, 0, 0
    for i = 1, math.min(#addr, 16) do
        local v = string.byte(addr, i)
        r = (r + v * 7)  % 256
        g = (g + v * 13) % 256
        b = (b + v * 19) % 256
    end
    return tocolor(math.max(r, 80), math.max(g, 80), math.max(b, 80), 255)
end

-- Draw an agent icon at (x, y) sz×sz. Uses cached texture if loaded,
-- otherwise kicks off a fetch and renders a colored placeholder with the
-- agent's first letter.
local function drawAgentIcon(x, y, sz, agentAddr, name)
    local entry = agentAddr and _autoIcons[agentAddr]
    if entry and entry.state == "ready" and entry.texture then
        dxDrawImage(x, y, sz, sz, entry.texture)
        return true
    end
    if agentAddr and not entry then requestAgentIcon(agentAddr) end
    dxDrawRectangle(x, y, sz, sz,
        agentAddr and colorForAgent(agentAddr) or c.cardSoft)
    local letter = string.upper(((name or "?"):gsub("[^%w]", "")):sub(1, 1))
    if letter == "" then letter = "?" end
    dxDrawText(letter, x, y, x + sz, y + sz, c.white, 1, fBody, "center", "center")
    return false
end

-- Dynamic services list. Each entry: { name, endpointId, versionId, skillsId, domainsId, expanded }
-- The *Id fields are the drawInput id keys — content is read from `inputs[id].text`.
local SERVICE_PRESETS = { "web", "A2A", "MCP", "OASF", "ENS", "DID", "email" }
local serviceList = {
    -- default: one web entry with empty endpoint → SDK auto-fills
    { name = "web", _id = "svc1", expanded = false },
}
local _nextSvcId = 2

local function addService()
    table.insert(serviceList, {
        name     = "A2A",
        _id      = "svc" .. tostring(_nextSvcId),
        expanded = false,
    })
    _nextSvcId = _nextSvcId + 1
end

local function removeService(idx)
    if #serviceList <= 1 then return end  -- keep at least one
    local entry = serviceList[idx]
    if entry and inputs[entry._id .. "_ep"]      then inputs[entry._id .. "_ep"].text      = "" end
    if entry and inputs[entry._id .. "_ver"]     then inputs[entry._id .. "_ver"].text     = "" end
    if entry and inputs[entry._id .. "_skills"]  then inputs[entry._id .. "_skills"].text  = "" end
    if entry and inputs[entry._id .. "_domains"] then inputs[entry._id .. "_domains"].text = "" end
    table.remove(serviceList, idx)
end

local function cycleServiceName(idx)
    local entry = serviceList[idx]
    if not entry then return end
    local cur = entry.name
    for i, n in ipairs(SERVICE_PRESETS) do
        if n == cur then
            entry.name = SERVICE_PRESETS[(i % #SERVICE_PRESETS) + 1]
            return
        end
    end
    entry.name = SERVICE_PRESETS[1]
end

local function splitCsv(str)
    local out = {}
    if not str or str == "" then return out end
    for item in str:gmatch("[^,]+") do
        local trimmed = item:match("^%s*(.-)%s*$")
        if #trimmed > 0 then table.insert(out, trimmed) end
    end
    return out
end

local function showNotif(text, kind)
    local col = (kind == "error" and c.red) or (kind == "warn" and c.orange) or c.green
    notif = { text = text, col = col, alpha = 255, tick = getTickCount() }
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
    head = head or 6; tail = tail or 6
    if not a or #a < head + tail + 2 then return a or "?" end
    return a:sub(1, head) .. ".." .. a:sub(-tail)
end

local function fitText(text, maxW, font)
    if not text then return "" end
    if dxGetTextWidth(text, 1, font) <= maxW then return text end
    local lo, hi = 1, #text
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if dxGetTextWidth(text:sub(1, mid) .. "..", 1, font) > maxW then hi = mid - 1
        else lo = mid + 1 end
    end
    return text:sub(1, math.max(1, lo - 1)) .. ".."
end

local function dots()
    local n = math.floor((getTickCount() / 400) % 4)
    return string.rep(".", n)
end

-- ---
-- Input system (reusable across forms)
-- ---

local inputs = {}
local focusedInput = nil
local clickZones = {}

local function addClick(id, x, y, w, h) clickZones[id] = { x = x, y = y, w = w, h = h } end
local function setInput(id, text) inputs[id] = inputs[id] or {}; inputs[id].text = text or "" end
local function getInput(id) return (inputs[id] and inputs[id].text) or "" end
local function clearAllInputs()
    for k in pairs(inputs) do inputs[k].text = "" end
    focusedInput = nil
end

local function drawInput(id, x, y, w, h, placeholder)
    inputs[id] = inputs[id] or { text = "", placeholder = placeholder or "", focused = false }
    local inp = inputs[id]
    inp.placeholder = placeholder or inp.placeholder
    local focused = (focusedInput == id)

    -- Reserve tiny right-side area for the X (clear) button only.
    local clrW    = math.floor(22 * sx)
    local actionW = clrW + math.floor(4 * sx)
    local tw      = w - actionW

    local hov = inRect(x, y, tw, h)

    dxDrawRectangle(x, y, tw, h, c.bgDim)
    dxDrawRectangle(x, y, math.floor(2 * sx), h,
        focused and c.purple or (hov and c.border or c.divider))
    dxDrawRectangle(x, y + h - math.floor(2 * sy), tw, math.floor(2 * sy),
        focused and c.purple or (hov and c.border or c.divider))

    local displayText = (#inp.text > 0) and inp.text or inp.placeholder
    local textCol = (#inp.text > 0) and c.white or c.muted
    local pad = math.floor(12 * sx)
    local shown = fitText(displayText, tw - pad * 2, fSmall)

    dxDrawText(shown, x + pad, y, x + tw - pad, y + h,
        textCol, 1, fSmall, "left", "center", true)

    if focused and math.floor(getTickCount() / 500) % 2 == 0 then
        local textW = dxGetTextWidth(shown, 1, fSmall)
        local curX = x + pad + math.min(textW, tw - pad * 2)
        dxDrawRectangle(curX, y + math.floor(8 * sy), math.floor(2 * sx),
            h - math.floor(16 * sy), c.green)
    end

    -- Clear (X) button only. Ctrl+V paste handled via polling in render loop.
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
-- Buttons
-- ---

local function btnPrimary(x, y, w, h, text, disabled)
    local hov = not disabled and inRect(x, y, w, h)
    local bg = disabled and c.cardSoft or (hov and c.purpleHov or c.purple)
    dxDrawRectangle(x, y, w, h, bg)
    if not disabled then
        dxDrawRectangle(x, y, w, math.floor(1 * sy), tocolor(255, 255, 255, 40))
    end
    local label = (disabled and busyMsg ~= "") and (busyMsg .. dots()) or text
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

-- ---
-- Small helpers
-- ---

local function card(x, y, w, h, hovering)
    dxDrawRectangle(x, y, w, h, hovering and c.cardHov or c.card)
end

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
    home          = "My Agents",
    wallet_picker = "Select Wallet",
    create        = "Create Agent",
    info          = "Agent Details",
    deposit       = "Deposit SOL",
}

local subtitleByScreen = {
    home          = "Agents you've registered with this wallet",
    wallet_picker = "Pick a wallet to act as creator / update authority",
    create        = "Real MPL Core + Agent Registry — appears on metaplex.com/agents",
    info          = "On-chain view (asset, collection, identity PDA, signer PDA)",
    deposit       = "Transfer SOL from your wallet to the agent's Asset Signer PDA",
}

local function drawHeader()
    dxDrawRectangle(px, py, pw, HDR_H, c.card)
    dxDrawRectangle(px, py, pw, math.floor(3 * sy), c.purple)
    dxDrawRectangle(px, py + HDR_H - math.floor(1 * sy), pw, math.floor(1 * sy), c.divider)

    dxDrawText(titleByScreen[screen] or "Agents",
        px + PAD, py + math.floor(8 * sy), px + pw - PAD, py + math.floor(34 * sy),
        c.white, 1, fTitle, "left", "center")
    if subtitleByScreen[screen] then
        dxDrawText(subtitleByScreen[screen], px + PAD, py + math.floor(34 * sy),
            px + pw - PAD, py + math.floor(58 * sy), c.gray, 1, fTiny, "left", "center")
    end

    local ax = px + pw - PAD
    local btnSz = math.floor(30 * sy)
    local btnY = py + math.floor(18 * sy)

    ax = ax - btnSz
    local hovClose = inRect(ax, btnY, btnSz, btnSz)
    dxDrawRectangle(ax, btnY, btnSz, btnSz, hovClose and c.red or c.cardSoft)
    dxDrawText("X", ax, btnY, ax + btnSz, btnY + btnSz,
        hovClose and c.white or c.dim, 1, fBody, "center", "center")
    addClick("close", ax, btnY, btnSz, btnSz)

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
-- Footer
-- ---

local function drawFooter()
    local y = py + ph - FOOTER_H
    dxDrawRectangle(px, y, pw, FOOTER_H, c.cardSoft)
    dxDrawRectangle(px, y, pw, math.floor(1 * sy), c.divider)
    local left = px + PAD
    dxDrawRectangle(left, y + math.floor((FOOTER_H - 8 * sy) / 2), math.floor(6 * sx),
        math.floor(8 * sy), c.green)
    dxDrawText(selWallet and shortAddr(selWallet) or "no wallet",
        left + math.floor(12 * sx), y, left + math.floor(200 * sx), y + FOOTER_H,
        c.dim, 1, fTiny, "left", "center")
    dxDrawText("F7 toggle  |  Esc back",
        px + pw - PAD - math.floor(200 * sx), y, px + pw - PAD, y + FOOTER_H,
        c.muted, 1, fTiny, "right", "center")
end

-- ---
-- Toast
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
-- Screen: wallet_picker (same pattern as token UI)
-- ---

local function drawWalletPicker()
    local x, y = px + PAD, contentY() + PAD
    local w = pw - PAD * 2

    if #wallets == 0 then
        card(x, y, w, math.floor(110 * sy), false)
        dxDrawText("No wallets loaded.",
            x, y + math.floor(18 * sy), x + w, y + math.floor(40 * sy),
            c.orange, 1, fSub, "center", "center")
        dxDrawText("Chat:\n/solwallet phrase   or   /solwallet import <key>",
            x, y + math.floor(44 * sy), x + w, y + math.floor(94 * sy),
            c.gray, 1, fSmall, "center", "center", false, true)
        y = y + math.floor(122 * sy)
        btnSecondary(x, y, w, BTN_H, "Refresh Wallet List")
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
        dxDrawText("WALLET " .. i, x + math.floor(14 * sx), y + math.floor(8 * sy),
            x + math.floor(140 * sx), y + math.floor(26 * sy),
            c.gray, 1, fTiny, "left", "top")
        dxDrawText(addr, x + math.floor(14 * sx), y + math.floor(22 * sy),
            x + w - math.floor(80 * sx), y + rowH - math.floor(4 * sy),
            c.white, 1, fSmall, "left", "top")
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
-- Screen: home (wallet hero + agent list)
-- ---

local function drawHome()
    local x, y = px + PAD, contentY() + PAD
    local w = pw - PAD * 2

    local heroH = math.floor(80 * sy)
    card(x, y, w, heroH, false)
    dxDrawRectangle(x, y, math.floor(3 * sx), heroH, c.purple)
    dxDrawText("ACTIVE WALLET", x + math.floor(14 * sx), y + math.floor(10 * sy),
        x + math.floor(200 * sx), y + math.floor(26 * sy),
        c.gray, 1, fTiny, "left", "top")
    dxDrawText(shortAddr(selWallet or "(none)", 16, 10),
        x + math.floor(14 * sx), y + math.floor(26 * sy),
        x + w - math.floor(110 * sx), y + heroH - math.floor(8 * sy),
        c.white, 1, fSub, "left", "center")

    local swW, swH = math.floor(88 * sx), math.floor(30 * sy)
    local swX = x + w - math.floor(14 * sx) - swW
    local swY = y + math.floor((heroH - swH) / 2)
    btnSecondary(swX, swY, swW, swH, "Switch")
    addClick("switch_wallet", swX, swY, swW, swH)

    y = y + heroH + math.floor(14 * sy)

    btnPrimary(x, y, w, BTN_H, "+ Create New Agent")
    addClick("goto_create", x, y, w, BTN_H)
    y = y + BTN_H + SECT_GAP

    dxDrawText("MY AGENTS", x, y, x + w - math.floor(100 * sx), y + math.floor(16 * sy),
        c.gray, 1, fTiny, "left", "center")
    dxDrawText(tostring(#myAgents),
        x + math.floor(82 * sx), y, x + math.floor(140 * sx), y + math.floor(16 * sy),
        c.purple, 1, fTiny, "left", "center")

    local rX = x + w - math.floor(80 * sx)
    local rhov = inRect(rX, y, math.floor(80 * sx), math.floor(16 * sy))
    dxDrawText("refresh", rX, y, rX + math.floor(80 * sx), y + math.floor(16 * sy),
        rhov and c.purple or c.muted, 1, fTiny, "right", "center")
    addClick("refresh_agents", rX, y, math.floor(80 * sx), math.floor(16 * sy))
    y = y + math.floor(22 * sy)

    if #myAgents == 0 then
        local eh = math.floor(100 * sy)
        card(x, y, w, eh, false)
        dxDrawText("No agents yet",
            x, y + math.floor(20 * sy), x + w, y + math.floor(44 * sy),
            c.gray, 1, fSub, "center", "center")
        dxDrawText("Click '+ Create New Agent' to register one.\nWill appear on metaplex.com/agents.",
            x, y + math.floor(48 * sy), x + w, y + math.floor(90 * sy),
            c.muted, 1, fSmall, "center", "center", false, true)
        return
    end

    local rowH = math.floor(64 * sy)
    local listTop = y
    local listBot = contentBot() - math.floor(10 * sy)
    local visible = math.floor((listBot - listTop) / (rowH + math.floor(8 * sy)))
    local first = agentScroll + 1
    local last  = math.min(#myAgents, first + visible - 1)

    for i = first, last do
        local ag = myAgents[i]
        local hov = inRect(x, y, w, rowH)
        card(x, y, w, rowH, hov)

        -- Logo (auto-fetched), falls back to colored letter while loading
        local icoSz = math.floor(44 * sy)
        local icoX  = x + math.floor(14 * sx)
        local icoY  = y + math.floor((rowH - icoSz) / 2)
        drawAgentIcon(icoX, icoY, icoSz, ag.agent, ag.name)

        local tL = icoX + icoSz + math.floor(14 * sx)
        local tR = x + w - math.floor(14 * sx)
        dxDrawText(fitText(ag.name or "(no name)", tR - tL, fBody),
            tL, y + math.floor(8 * sy), tR, y + math.floor(30 * sy),
            c.white, 1, fBody, "left", "top")
        dxDrawText(fitText(ag.description or "", tR - tL, fTiny),
            tL, y + math.floor(28 * sy), tR, y + math.floor(46 * sy),
            c.gray, 1, fTiny, "left", "top")
        dxDrawText(shortAddr(ag.agent, 8, 6),
            tL, y + math.floor(46 * sy), tR, y + rowH - math.floor(6 * sy),
            c.muted, 1, fTiny, "left", "top")

        addClick("open_agent_" .. i, x, y, w, rowH)
        y = y + rowH + math.floor(8 * sy)
    end

    if agentScroll > 0 then
        dxDrawText("  ^  scroll up  ^", x, listTop - math.floor(14 * sy),
            x + w, listTop, c.muted, 1, fTiny, "center", "center")
    end
    if last < #myAgents then
        dxDrawText("  v  " .. (#myAgents - last) .. " more  v",
            x, listBot, x + w, listBot + math.floor(14 * sy),
            c.muted, 1, fTiny, "center", "center")
    end
end

-- ---
-- Screen: create
-- ---

-- Small clickable chip (pill) for the supportedTrust toggles
local function drawChip(id, x, y, w, h, label, on)
    local hov = inRect(x, y, w, h)
    local bg = on and c.green or (hov and c.cardHov or c.card)
    local textCol = on and tocolor(10, 40, 25, 255) or (hov and c.white or c.dim)
    dxDrawRectangle(x, y, w, h, bg)
    if on then
        dxDrawRectangle(x, y, math.floor(2 * sx), h, tocolor(255, 255, 255, 180))
    end
    dxDrawText(label, x, y, x + w, y + h, textCol, 1, fTiny, "center", "center")
    addClick("chip_" .. id, x, y, w, h)
end

-- Draw one service card (collapsed row + expanded fields).
-- Returns the y coordinate after rendering.
local function drawServiceCard(x, y, w, idx, entry)
    local rowH    = math.floor(34 * sy)
    local gap     = math.floor(4 * sx)
    local nameW   = math.floor(72 * sx)
    local xBtnW   = math.floor(26 * sx)
    local expBtnW = math.floor(28 * sx)
    local epW     = w - nameW - expBtnW - xBtnW - gap * 3

    -- Row: [NAME] [endpoint input] [EXP] [X]
    -- NAME is clickable to cycle through SERVICE_PRESETS
    local nameHov = inRect(x, y, nameW, rowH)
    dxDrawRectangle(x, y, nameW, rowH, nameHov and c.purpleHov or c.purple)
    dxDrawRectangle(x, y, nameW, math.floor(1 * sy), tocolor(255, 255, 255, 60))
    dxDrawText(entry.name, x, y, x + nameW, y + rowH, c.white, 1, fTiny, "center", "center")
    addClick("svc_cycle_" .. idx, x, y, nameW, rowH)

    -- Endpoint input
    local epX = x + nameW + gap
    drawInput(entry._id .. "_ep", epX, y, epW, rowH,
        entry.name == "web"  and "auto → https://example.com/agent/<mint>"
     or entry.name == "A2A"  and "https://agent.example/.well-known/agent-card.json"
     or entry.name == "MCP"  and "https://mcp.agent.example/"
     or entry.name == "OASF" and "ipfs://<cid>"
     or entry.name == "email" and "mail@myagent.com"
     or "endpoint")

    -- Expand toggle
    local expX = x + w - xBtnW - gap - expBtnW
    local expHov = inRect(expX, y, expBtnW, rowH)
    dxDrawRectangle(expX, y, expBtnW, rowH, expHov and c.cardHov or c.cardSoft)
    dxDrawText(entry.expanded and "-" or "+",
        expX, y, expX + expBtnW, y + rowH,
        expHov and c.white or c.dim, 1, fBody, "center", "center")
    addClick("svc_exp_" .. idx, expX, y, expBtnW, rowH)

    -- Delete button
    local xbX = x + w - xBtnW
    local xbHov = inRect(xbX, y, xBtnW, rowH)
    dxDrawRectangle(xbX, y, xBtnW, rowH, xbHov and c.red or c.cardSoft)
    dxDrawText("X", xbX, y, xbX + xBtnW, y + rowH,
        xbHov and c.white or c.muted, 1, fTiny, "center", "center")
    addClick("svc_del_" .. idx, xbX, y, xBtnW, rowH)

    y = y + rowH + math.floor(4 * sy)

    if entry.expanded then
        -- version (always), skills (OASF), domains (OASF)
        local subH = math.floor(28 * sy)
        local thirdW = math.floor((w - math.floor(8 * sx)) / 2)

        dxDrawText("version", x, y, x + math.floor(60 * sx), y + subH,
            c.muted, 1, fTiny, "left", "center")
        drawInput(entry._id .. "_ver", x + math.floor(60 * sx), y,
            w - math.floor(60 * sx), subH,
            entry.name == "A2A"  and "0.3.0"
         or entry.name == "MCP"  and "2025-06-18"
         or entry.name == "OASF" and "0.8"
         or "")
        y = y + subH + math.floor(4 * sy)

        if entry.name == "OASF" then
            dxDrawText("skills",  x, y, x + math.floor(60 * sx), y + subH,
                c.muted, 1, fTiny, "left", "center")
            drawInput(entry._id .. "_skills", x + math.floor(60 * sx), y,
                w - math.floor(60 * sx), subH, "comma,separated,list")
            y = y + subH + math.floor(4 * sy)

            dxDrawText("domains", x, y, x + math.floor(60 * sx), y + subH,
                c.muted, 1, fTiny, "left", "center")
            drawInput(entry._id .. "_domains", x + math.floor(60 * sx), y,
                w - math.floor(60 * sx), subH, "comma,separated,list")
            y = y + subH + math.floor(4 * sy)
        end
    end

    return y + math.floor(4 * sy)
end

local function drawCreate()
    local x, y = px + PAD, contentY() + math.floor(8 * sy)
    local w = pw - PAD * 2

    y = labeledInput(x, y, w, "Name",           "a_name",        "e.g. Plexpert")
    y = labeledInput(x, y, w, "Description",    "a_description", "What does this agent do?")
    y = labeledInput(x, y, w, "Image / Logo URL", "a_image",     "https://gateway.pinata.cloud/ipfs/<cid>")

    -- SERVICES header with + Add button
    dxDrawText("SERVICES (" .. #serviceList .. ")",
        x, y, x + math.floor(140 * sx), y + math.floor(14 * sy),
        c.gray, 1, fTiny, "left", "center")
    local addW = math.floor(86 * sx)
    local addHov = inRect(x + w - addW, y - math.floor(4 * sy), addW, math.floor(22 * sy))
    dxDrawRectangle(x + w - addW, y - math.floor(4 * sy), addW, math.floor(22 * sy),
        addHov and c.purpleHov or c.cardSoft)
    dxDrawText("+ ADD SERVICE", x + w - addW, y - math.floor(4 * sy),
        x + w, y + math.floor(18 * sy),
        addHov and c.white or c.dim, 1, fTiny, "center", "center")
    addClick("svc_add", x + w - addW, y - math.floor(4 * sy), addW, math.floor(22 * sy))
    y = y + math.floor(22 * sy)

    -- Service cards
    for i, entry in ipairs(serviceList) do
        y = drawServiceCard(x, y, w, i, entry)
    end

    y = y + math.floor(4 * sy)

    -- SUPPORTED TRUST chips
    dxDrawText("SUPPORTED TRUST", x, y, x + w, y + math.floor(14 * sy),
        c.gray, 1, fTiny, "left", "center")
    y = y + math.floor(18 * sy)

    local chipH = math.floor(26 * sy)
    local chipGap = math.floor(6 * sx)
    local chipW = math.floor((w - chipGap * 2) / 3)
    drawChip("trust_rep",   x,                                 y, chipW, chipH,
        "REPUTATION", trustFlags["reputation"])
    drawChip("trust_crypto", x + chipW + chipGap,              y, chipW, chipH,
        "CRYPTO-ECONOMIC", trustFlags["crypto-economic"])
    drawChip("trust_tee",   x + (chipW + chipGap) * 2,         y, chipW, chipH,
        "TEE-ATTESTATION", trustFlags["tee-attestation"])
    y = y + chipH + math.floor(8 * sy)

    -- x402 toggle
    local toggleW = math.floor(160 * sx)
    drawChip("x402", x, y, toggleW, chipH,
        x402Enabled and "x402 SUPPORT: ON" or "x402 SUPPORT: OFF", x402Enabled)

    -- Primary CTA pinned at bottom
    local btnY = contentBot() - BTN_H - math.floor(12 * sy)
    busyMsg = busy and "Registering agent" or ""
    btnPrimary(x, btnY, w, BTN_H, "Register Agent", busy)
    if not busy then addClick("confirm_create", x, btnY, w, BTN_H) end
end

-- ---
-- Screen: info
-- ---

local function drawInfo()
    local x, y = px + PAD, contentY() + PAD
    local w = pw - PAD * 2
    if not selAgent then return end

    -- Hero with logo on the left
    local heroH = math.floor(96 * sy)
    card(x, y, w, heroH, false)
    dxDrawRectangle(x, y, math.floor(3 * sx), heroH, c.green)

    -- Logo (auto-fetched from registration JSON's image URL)
    local logoSz = math.floor(72 * sy)
    local logoX  = x + math.floor(14 * sx)
    local logoY  = y + math.floor((heroH - logoSz) / 2)
    drawAgentIcon(logoX, logoY, logoSz, selAgent.agent, selAgent.name)

    -- Text block to the right of the logo
    local tL = logoX + logoSz + math.floor(14 * sx)
    local tR = x + w - math.floor(14 * sx)
    dxDrawText(fitText(selAgent.name or "(no name)", tR - tL, fSub),
        tL, y + math.floor(10 * sy), tR, y + math.floor(34 * sy),
        c.white, 1, fSub, "left", "top")
    dxDrawText(fitText(selAgent.description or "", tR - tL, fSmall),
        tL, y + math.floor(34 * sy), tR, y + math.floor(58 * sy),
        c.dim, 1, fSmall, "left", "top")
    dxDrawText("Agent: " .. shortAddr(selAgent.agent, 10, 8),
        tL, y + math.floor(60 * sy), tR, y + heroH - math.floor(6 * sy),
        c.green, 1, fTiny, "left", "top")
    y = y + heroH + math.floor(14 * sy)

    -- Action row
    local bw = math.floor((w - math.floor(16 * sx)) / 3)
    btnSecondary(x, y, bw, BTN_H, "Refresh")
    addClick("refresh_agent", x, y, bw, BTN_H)
    btnPrimary(x + bw + math.floor(8 * sx), y, bw, BTN_H, "Deposit SOL")
    addClick("goto_deposit", x + bw + math.floor(8 * sx), y, bw, BTN_H)
    btnSecondary(x + (bw + math.floor(8 * sx)) * 2, y, bw, BTN_H, "Metaplex")
    addClick("open_metaplex", x + (bw + math.floor(8 * sx)) * 2, y, bw, BTN_H)
    y = y + BTN_H + SECT_GAP

    -- Facts
    local function fact(label, value, valueCol)
        local rh = math.floor(28 * sy)
        local hov = inRect(x, y, w, rh)
        dxDrawRectangle(x, y, w, rh, hov and c.cardHov or c.card)
        dxDrawText(label, x + math.floor(14 * sx), y,
            x + math.floor(160 * sx), y + rh, c.gray, 1, fTiny, "left", "center")
        dxDrawText(fitText(tostring(value or "?"), w - math.floor(180 * sx), fSmall),
            x + math.floor(160 * sx), y, x + w - math.floor(14 * sx), y + rh,
            valueCol or c.white, 1, fSmall, "left", "center")
        y = y + rh + math.floor(4 * sy)
    end

    fact("collection",         shortAddr(selAgent.collection, 8, 6))
    fact("agent identity PDA", shortAddr(selAgent.agentIdentityPda, 8, 6))
    fact("asset signer PDA",   shortAddr(selAgent.agentSigner, 8, 6), c.green)

    local balStr = pdaBalance == nil and "(press refresh)"
                   or string.format("%.4f SOL", pdaBalance)
    fact("PDA balance", balStr, pdaBalance and pdaBalance > 0 and c.green or c.muted)

    fact("IPFS CID",   shortAddr(selAgent.ipfsCid, 10, 6))
    fact("on-chain URI", fitText(selAgent.onChainUri or "", w - math.floor(180 * sx), fSmall))
end

-- ---
-- Screen: deposit
-- ---

local function drawDeposit()
    local x, y = px + PAD, contentY() + PAD
    local w = pw - PAD * 2
    if not selAgent then return end

    local cardH = math.floor(62 * sy)
    card(x, y, w, cardH, false)
    dxDrawRectangle(x, y, math.floor(3 * sx), cardH, c.green)

    local icoSz = math.floor(42 * sy)
    local icoX  = x + math.floor(14 * sx)
    local icoY  = y + math.floor((cardH - icoSz) / 2)
    drawAgentIcon(icoX, icoY, icoSz, selAgent.agent, selAgent.name)

    local tL = icoX + icoSz + math.floor(14 * sx)
    dxDrawText(selAgent.name or "(no name)",
        tL, y + math.floor(6 * sy),
        x + w - math.floor(14 * sx), y + math.floor(30 * sy),
        c.white, 1, fBody, "left", "top")
    dxDrawText("PDA: " .. shortAddr(selAgent.agentSigner, 10, 8),
        tL, y + math.floor(30 * sy),
        x + w - math.floor(14 * sx), y + math.floor(56 * sy),
        c.green, 1, fTiny, "left", "top")
    y = y + cardH + math.floor(10 * sy)

    y = labeledInput(x, y, w, "Amount (SOL)", "d_amount", "e.g. 0.1",
        "Plain SOL transfer to the agent's PDA. Irreversible for 'withdrawing' without MPL Core Execute.")

    local btnY = contentBot() - BTN_H - math.floor(16 * sy)
    busyMsg = busy and "Sending SOL" or ""
    btnPrimary(x, btnY, w, BTN_H, "Send SOL to Agent PDA", busy)
    if not busy then addClick("confirm_deposit", x, btnY, w, BTN_H) end
end

-- ---
-- Main render
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
    elseif screen == "deposit"       then drawDeposit()
    end
    drawFooter()
    drawNotif()
end)

-- ---
-- Toggle
-- ---

local function openUI()
    isOpen = true
    showCursor(true)
    triggerServerEvent("mpaui:getWallets", resourceRoot)
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

bindKey("F7", "down", toggleUI)

-- ---
-- Server → client events
-- ---

addEvent("mpaui:walletsData", true)
addEventHandler("mpaui:walletsData", resourceRoot, function(list)
    wallets = list or {}
    if not selWallet and #wallets > 0 then
        selWallet = wallets[1]
        triggerServerEvent("mpaui:getAgents", resourceRoot, selWallet)
        screen = "home"
    elseif #wallets == 0 then
        screen = "wallet_picker"
    end
end)

addEvent("mpaui:agentsData", true)
addEventHandler("mpaui:agentsData", resourceRoot, function(walletAddr, list)
    if walletAddr ~= selWallet then return end
    myAgents = list or {}
    if agentScroll > math.max(0, #myAgents - 1) then agentScroll = 0 end
end)

addEvent("mpaui:createResult", true)
addEventHandler("mpaui:createResult", resourceRoot, function(ok, payload, refreshedList)
    busy = false
    if not ok then
        showNotif("Create failed: " .. tostring(payload), "error")
        return
    end
    showNotif("Agent registered! " .. shortAddr(payload.agent), "success")
    if refreshedList then myAgents = refreshedList end
    clearAllInputs()
    for _, ag in ipairs(myAgents) do
        if ag.agent == payload.agent then
            selAgent = ag
            pdaBalance = nil
            screen = "info"
            triggerServerEvent("mpaui:getBalance", resourceRoot, ag.agentSigner)
            break
        end
    end
end)

addEvent("mpaui:depositResult", true)
addEventHandler("mpaui:depositResult", resourceRoot, function(ok, payload)
    busy = false
    if not ok then
        showNotif("Deposit failed: " .. tostring(payload), "error")
        return
    end
    showNotif("Deposited!", "success")
    clearAllInputs()
    screen = "info"
    if selAgent then
        triggerServerEvent("mpaui:getBalance", resourceRoot, selAgent.agentSigner)
    end
end)

addEvent("mpaui:balanceData", true)
addEventHandler("mpaui:balanceData", resourceRoot, function(addr, bal, err)
    if selAgent and addr == selAgent.agentSigner then
        pdaBalance = bal or 0
    end
end)

-- ---
-- Click dispatch
-- ---

local function handleClick(id)
    if id == "close" then closeUI(); return end

    -- Clear (X) button
    if id:sub(1, 6) == "clear_" then
        local inpId = id:sub(7)
        if inputs[inpId] then inputs[inpId].text = "" end
        focusedInput = inpId
        guiSetInputEnabled(true)
        return
    end

    if id == "back" then
        if screen == "info" then screen = "home"
        elseif screen == "deposit" then screen = "info"
        elseif screen == "create" then screen = "home"
        elseif screen == "wallet_picker" then screen = "home"
        else screen = "home" end
        return
    end
    if id == "refresh_wallets" then
        triggerServerEvent("mpaui:getWallets", resourceRoot); return
    end
    if id == "switch_wallet" then screen = "wallet_picker"; return end
    if id:sub(1, 12) == "pick_wallet_" then
        local idx = tonumber(id:sub(13))
        if idx and wallets[idx] then
            selWallet = wallets[idx]
            myAgents = {}
            selAgent = nil
            pdaBalance = nil
            triggerServerEvent("mpaui:getAgents", resourceRoot, selWallet)
            screen = "home"
            showNotif("Wallet: " .. shortAddr(selWallet), "success")
        end
        return
    end

    if screen == "home" then
        if id == "goto_create" then screen = "create"; return end
        if id == "refresh_agents" and selWallet then
            triggerServerEvent("mpaui:getAgents", resourceRoot, selWallet)
            showNotif("Refreshing", "success"); return
        end
        if id:sub(1, 11) == "open_agent_" then
            local idx = tonumber(id:sub(12))
            if idx and myAgents[idx] then
                selAgent = myAgents[idx]
                pdaBalance = nil
                screen = "info"
                triggerServerEvent("mpaui:getBalance", resourceRoot, selAgent.agentSigner)
            end
            return
        end
    end

    -- Chip toggles on Create form
    if id == "chip_trust_rep"    then trustFlags["reputation"]      = not trustFlags["reputation"]; return end
    if id == "chip_trust_crypto" then trustFlags["crypto-economic"] = not trustFlags["crypto-economic"]; return end
    if id == "chip_trust_tee"    then trustFlags["tee-attestation"] = not trustFlags["tee-attestation"]; return end
    if id == "chip_x402"         then x402Enabled                   = not x402Enabled; return end

    -- Service card buttons
    if id == "svc_add" then addService(); return end

    if id:sub(1, 10) == "svc_cycle_" then
        local i = tonumber(id:sub(11)); if i then cycleServiceName(i) end; return
    end
    if id:sub(1, 8) == "svc_exp_" then
        local i = tonumber(id:sub(9))
        if i and serviceList[i] then serviceList[i].expanded = not serviceList[i].expanded end
        return
    end
    if id:sub(1, 8) == "svc_del_" then
        local i = tonumber(id:sub(9)); if i then removeService(i) end; return
    end

    if screen == "create" and id == "confirm_create" then
        if not selWallet then showNotif("No wallet", "error") return end
        local name = getInput("a_name")
        local desc = getInput("a_description")
        local img  = getInput("a_image")
        if #name == 0 or #desc == 0 then
            showNotif("Fill name and description", "warn"); return
        end

        -- Collect services from the dynamic list.
        local services = {}
        for _, entry in ipairs(serviceList) do
            local ep      = getInput(entry._id .. "_ep")
            local ver     = getInput(entry._id .. "_ver")
            local skills  = getInput(entry._id .. "_skills")
            local domains = getInput(entry._id .. "_domains")

            -- Skip entries that lack an endpoint EXCEPT "web" (SDK auto-fills
            -- web's default endpoint when endpoint is nil).
            if entry.name == "web" and #ep == 0 then
                -- let SDK auto-fill web
                table.insert(services, { name = "web" })
            elseif #ep > 0 then
                local svc = { name = entry.name, endpoint = ep }
                if #ver > 0     then svc.version = ver end
                if #skills > 0  then svc.skills  = splitCsv(skills) end
                if #domains > 0 then svc.domains = splitCsv(domains) end
                table.insert(services, svc)
            end
        end
        if #services == 0 then
            -- Guard: always have at least one service. SDK will auto-fill web.
            table.insert(services, { name = "web" })
        end

        -- Collect supportedTrust in canonical spec order
        local supportedTrust = {}
        if trustFlags["reputation"]      then table.insert(supportedTrust, "reputation") end
        if trustFlags["crypto-economic"] then table.insert(supportedTrust, "crypto-economic") end
        if trustFlags["tee-attestation"] then table.insert(supportedTrust, "tee-attestation") end

        busy = true
        showNotif("Uploading JSON to IPFS + atomic on-chain register...", "success")
        triggerServerEvent("mpaui:createAgent", resourceRoot, {
            wallet         = selWallet,
            name           = name,
            description    = desc,
            image          = img,
            services       = services,
            supportedTrust = supportedTrust,
            x402Support    = x402Enabled,
        })
        return
    end

    if screen == "info" then
        if id == "refresh_agent" and selAgent then
            pdaBalance = nil
            triggerServerEvent("mpaui:getBalance", resourceRoot, selAgent.agentSigner)
            showNotif("Fetching balance...", "success"); return
        end
        if id == "goto_deposit" then screen = "deposit"; setInput("d_amount", ""); return end
        if id == "open_metaplex" and selAgent then
            local url = selAgent.metaplexUrl or ("https://www.metaplex.com/agent/" .. tostring(selAgent.agent))
            -- setClipboard is only available in MTA 1.5.6+. Try it safely.
            if setClipboard then
                setClipboard(url)
                showNotif("metaplex.com URL copied to clipboard", "success")
            else
                outputChatBox("#9b45ff[Agent]#ffffff URL: " .. url, 255, 255, 255, true)
                showNotif("URL printed to chat (clipboard unsupported)", "warn")
            end
            return
        end
    end

    if screen == "deposit" and id == "confirm_deposit" then
        if not selWallet or not selAgent then showNotif("No agent", "error") return end
        local amt = tonumber(getInput("d_amount"))
        if not amt or amt <= 0 then
            showNotif("Enter positive SOL amount", "warn"); return
        end
        busy = true
        showNotif("Sending " .. amt .. " SOL...", "success")
        triggerServerEvent("mpaui:depositSol", resourceRoot, {
            wallet = selWallet, agentSigner = selAgent.agentSigner, amount = amt,
        })
        return
    end
end

-- ---
-- Click + keyboard plumbing (same pattern as token UI)
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
        if key == "mouse_wheel_up"   then agentScroll = math.max(0, agentScroll - 1) end
        if key == "mouse_wheel_down" then agentScroll = math.min(math.max(0, #myAgents - 1), agentScroll + 1) end
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
-- Ctrl+V paste via MTA's onClientPaste event (the proper way; works on
-- all MTA versions). Avoids getClipboard() which is 1.5.6+ only.
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
    -- Ctrl held? Don't append the literal char — onClientKey will pick up
    -- Ctrl+V / Ctrl+X / Ctrl+C and do the right thing.
    if getKeyState("lctrl") or getKeyState("rctrl") then return end
    local inp = inputs[focusedInput]
    if not inp then return end
    inp.text = inp.text .. char
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    outputChatBox("#9b45ff[Metaplex Agent UI]#ffffff  Press  #ffaa1eF7#ffffff  to open.",
        255, 255, 255, true)
end)
