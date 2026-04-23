-- https://github.com/yongsxyz
--[[
    Metaplex SDK - Ed25519 field arithmetic (mod p = 2^255 - 19)
    Implements just enough math to perform Ed25519 point decompression
    so we can detect whether a 32-byte hash lies ON or OFF the curve.

    The on-curve check is required to derive the canonical Solana PDA
    (the canonical bump is the highest one whose hash is OFF the curve).

    Field elements are arrays of 16 limbs of 16 bits (little-endian),
    matching the layout used by TweetNaCl / RFC 8032 implementations.
]]

local floor = math.floor

MetaplexField = {}

local function fe_carry(o)
    for i = 1, 16 do
        o[i] = o[i] + 65536
        local c = floor(o[i] / 65536)
        o[i] = o[i] - c * 65536
        if i < 16 then
            o[i + 1] = o[i + 1] + c - 1
        else
            o[1] = o[1] + (c - 1) * 38
        end
    end
end

local function fe_0() return {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0} end
local function fe_1() return {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0} end

local function fe_copy(f)
    return {f[1],f[2],f[3],f[4],f[5],f[6],f[7],f[8],
            f[9],f[10],f[11],f[12],f[13],f[14],f[15],f[16]}
end

local function fe_add(f, g)
    local h = {}
    for i = 1, 16 do h[i] = f[i] + g[i] end
    return h
end

local function fe_sub(f, g)
    local h = {}
    for i = 1, 16 do h[i] = f[i] - g[i] end
    return h
end

local function fe_mul(f, g)
    local t = {}
    for i = 1, 31 do t[i] = 0 end
    for i = 1, 16 do
        local fi = f[i]
        for j = 1, 16 do
            t[i + j - 1] = t[i + j - 1] + fi * g[j]
        end
    end
    for i = 17, 31 do
        t[i - 16] = t[i - 16] + t[i] * 38
    end
    local h = {}
    for i = 1, 16 do h[i] = t[i] end
    fe_carry(h)
    fe_carry(h)
    return h
end

local function fe_sq(f) return fe_mul(f, f) end

local function fe_neg(f)
    local h = {}
    for i = 1, 16 do h[i] = -f[i] end
    return h
end

local function fe_frombytes(s)
    local h = {}
    for i = 1, 16 do
        h[i] = s[2 * i - 1] + s[2 * i] * 256
    end
    h[16] = h[16] % 32768
    return h
end

local function fe_tobytes(h)
    h = fe_copy(h)
    for _ = 1, 4 do fe_carry(h) end
    local m = fe_copy(h)
    m[1] = m[1] - 0xFFED
    for i = 2, 15 do m[i] = m[i] - 0xFFFF end
    m[16] = m[16] - 0x7FFF
    for i = 1, 15 do
        if m[i] < 0 then
            m[i] = m[i] + 65536
            m[i + 1] = m[i + 1] - 1
        end
    end
    local r = (m[16] >= 0) and m or h
    local s = {}
    for i = 1, 16 do
        s[2 * i - 1] = r[i] % 256
        s[2 * i] = floor(r[i] / 256)
    end
    return s
end

local function fe_eq(a, b)
    local ab = fe_tobytes(a)
    local bb = fe_tobytes(b)
    for i = 1, 32 do
        if ab[i] ~= bb[i] then return false end
    end
    return true
end

-- Curve constant d = -121665/121666 mod p (RFC 8032)
local D_BYTES = {
    0xA3, 0x78, 0x59, 0x13, 0xCA, 0x4D, 0xEB, 0x75,
    0xAB, 0xD8, 0x41, 0x41, 0x4D, 0x0A, 0x70, 0x00,
    0x98, 0xE8, 0x79, 0x77, 0x79, 0x40, 0xC7, 0x8C,
    0x73, 0xFE, 0x6F, 0x2B, 0xEE, 0x6C, 0x03, 0x52
}
local D = fe_frombytes(D_BYTES)

-- z^((p-5)/8) = z^(2^252 - 3) via the standard ed25519 addition chain
local function fe_pow_p_minus_5_div_8(z)
    local function sq_n(x, n)
        for _ = 1, n do x = fe_sq(x) end
        return x
    end
    local z2 = fe_sq(z)
    local t = sq_n(z2, 2)
    local z9 = fe_mul(t, z)
    local z11 = fe_mul(z9, z2)
    t = fe_sq(z11)
    local z_5_0 = fe_mul(t, z9)
    t = sq_n(z_5_0, 5)
    local z_10_0 = fe_mul(t, z_5_0)
    t = sq_n(z_10_0, 10)
    local z_20_0 = fe_mul(t, z_10_0)
    t = sq_n(z_20_0, 20)
    local z_40_0 = fe_mul(t, z_20_0)
    t = sq_n(z_40_0, 10)
    local z_50_0 = fe_mul(t, z_10_0)
    t = sq_n(z_50_0, 50)
    local z_100_0 = fe_mul(t, z_50_0)
    t = sq_n(z_100_0, 100)
    local z_200_0 = fe_mul(t, z_100_0)
    t = sq_n(z_200_0, 50)
    local z_250_0 = fe_mul(t, z_50_0) -- z^(2^250 - 1)
    -- z^(2^252 - 3) = (z^(2^250 - 1))^4 * z = sq(sq(z_250_0)) * z
    t = fe_sq(z_250_0)
    t = fe_sq(t)
    return fe_mul(t, z)
end

-- True iff a 32 byte hash decodes to a valid Edwards curve point.
-- A canonical Solana PDA must NOT be on the curve (no private key exists).
function MetaplexField.isOnCurve(bytes)
    if not bytes or #bytes < 32 then return false end

    local y = fe_frombytes(bytes)
    local y_sq = fe_sq(y)
    local one = fe_1()
    local u = fe_sub(y_sq, one)
    local v = fe_add(fe_mul(D, y_sq), one)

    -- Recover x via: x = u * v^3 * (u * v^7)^((p-5)/8)
    local v2 = fe_sq(v)
    local v3 = fe_mul(v2, v)
    local uv3 = fe_mul(u, v3)
    local v7 = fe_mul(fe_mul(v3, v3), v)
    local uv7 = fe_mul(u, v7)
    local p1 = fe_pow_p_minus_5_div_8(uv7)
    local x = fe_mul(uv3, p1)

    -- The point is on the curve iff v*x^2 == ±u
    local x2 = fe_sq(x)
    local vx2 = fe_mul(v, x2)

    if fe_eq(vx2, u) then return true end
    local neg_u = fe_neg(u)
    if fe_eq(vx2, neg_u) then return true end
    return false
end
