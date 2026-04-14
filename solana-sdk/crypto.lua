-- https://github.com/yongsxyz
--[[
    Pure Lua Ed25519 for MTA:SA
    Supports: keypair generation, signing

    NOTE: Signing takes ~0.3-0.5s in MTA Lua VM.
    Normal for pure-Lua crypto. Avoid tight loops.

    Random generation is NOT cryptographically secure.
    For real funds, import keys from an existing wallet.
]]

Ed25519 = {}
Crypto = {}

local floor = math.floor

-- ---
-- Shared Utilities (accessible by other files via Crypto.xxx)
-- ---

function Crypto.bytesToString(bytes)
    local t = {}
    for i = 1, #bytes do t[i] = string.char(bytes[i]) end
    return table.concat(t)
end

function Crypto.stringToBytes(str)
    local bytes = {}
    for i = 1, #str do bytes[i] = string.byte(str, i) end
    return bytes
end

function Crypto.sha512(data)
    local str = type(data) == "string" and data or Crypto.bytesToString(data)
    local hex = hash("sha512", str)
    local out = {}
    for i = 1, 128, 2 do
        out[#out + 1] = tonumber(hex:sub(i, i + 1), 16)
    end
    return out
end

function Crypto.sha256(data)
    local str = type(data) == "string" and data or Crypto.bytesToString(data)
    local hex = hash("sha256", str)
    local out = {}
    for i = 1, 64, 2 do
        out[#out + 1] = tonumber(hex:sub(i, i + 1), 16)
    end
    return out
end

function Crypto.bxor(a, b)
    local r, p = 0, 1
    for _ = 0, 7 do
        local a1 = a % 2
        local b1 = b % 2
        if a1 ~= b1 then r = r + p end
        a = (a - a1) / 2
        b = (b - b1) / 2
        p = p * 2
    end
    return r
end

function Crypto.hmacSha512(key, message)
    if type(key) == "string" then key = Crypto.stringToBytes(key) end
    if type(message) == "string" then message = Crypto.stringToBytes(message) end
    local block_size = 128
    if #key > block_size then key = Crypto.sha512(key) end
    local k = {}
    for i = 1, #key do k[i] = key[i] end
    while #k < block_size do k[#k + 1] = 0 end
    local ipad_data, opad_data = {}, {}
    for i = 1, block_size do
        ipad_data[i] = Crypto.bxor(k[i], 0x36)
        opad_data[i] = Crypto.bxor(k[i], 0x5c)
    end
    for i = 1, #message do ipad_data[block_size + i] = message[i] end
    local inner = Crypto.sha512(ipad_data)
    for i = 1, 64 do opad_data[block_size + i] = inner[i] end
    return Crypto.sha512(opad_data)
end

-- Local aliases for use within this file
local bytes_to_string = Crypto.bytesToString
local sha512 = Crypto.sha512

-- ---
-- Field Element (mod p = 2^255 - 19)
-- 16 limbs of 16 bits, little-endian
-- ---

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
    return o
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

local function fe_sq(f)
    return fe_mul(f, f)
end

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
    -- Conditional subtract p
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

-- Inversion: a^(p-2) using efficient addition chain
local function fe_inv(z)
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
    local z_250_0 = fe_mul(t, z_50_0)
    t = sq_n(z_250_0, 5)
    return fe_mul(t, z11)
end

-- ---
-- Curve Constants
-- ---

-- d = -121665/121666 mod p
local D_BYTES = {
    0xA3, 0x78, 0x59, 0x13, 0xCA, 0x4D, 0xEB, 0x75,
    0xAB, 0xD8, 0x41, 0x41, 0x4D, 0x0A, 0x70, 0x00,
    0x98, 0xE8, 0x79, 0x77, 0x79, 0x40, 0xC7, 0x8C,
    0x73, 0xFE, 0x6F, 0x2B, 0xEE, 0x6C, 0x03, 0x52
}
local D = fe_frombytes(D_BYTES)
local D2 = fe_add(D, D)
fe_carry(D2)

-- Base point
local BX = fe_frombytes({
    0x1A, 0xD5, 0x25, 0x8F, 0x60, 0x2D, 0x56, 0xC9,
    0xB2, 0xA7, 0x25, 0x95, 0x60, 0xC7, 0x2C, 0x69,
    0x5C, 0xDC, 0xD6, 0xFD, 0x31, 0xE2, 0xA4, 0xC0,
    0xFE, 0x53, 0x6E, 0xCD, 0xD3, 0x36, 0x69, 0x21
})
local BY = fe_frombytes({
    0x58, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66,
    0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66,
    0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66,
    0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66
})
local BZ = fe_1()
local BT = fe_mul(BX, BY)

-- Group order L
local L_BYTES = {
    0xED, 0xD3, 0xF5, 0x5C, 0x1A, 0x63, 0x12, 0x58,
    0xD6, 0x9C, 0xF7, 0xA2, 0xDE, 0xF9, 0xDE, 0x14,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10
}

-- ---
-- Group Element Operations (Extended Coordinates)
-- Point = {X, Y, Z, T} where x=X/Z, y=Y/Z, T=X*Y/Z
-- Curve: -x^2 + y^2 = 1 + d*x^2*y^2 (a = -1)
-- ---

local function ge_zero()
    return {fe_0(), fe_1(), fe_1(), fe_0()}
end

-- Point doubling (dbl-2008-hwcd)
local function ge_double(p)
    local X1, Y1, Z1 = p[1], p[2], p[3]
    local A = fe_sq(X1)
    local B = fe_sq(Y1)
    local C = fe_sq(Z1)
    C = fe_add(C, C)
    fe_carry(C)
    local DD = fe_neg(A) -- D = a*A = -A since a=-1
    fe_carry(DD)
    local E = fe_add(X1, Y1)
    E = fe_sq(E)
    E = fe_sub(E, A)
    E = fe_sub(E, B)
    fe_carry(E)
    local G = fe_add(DD, B)
    fe_carry(G)
    local F = fe_sub(G, C)
    fe_carry(F)
    local H = fe_sub(DD, B)
    fe_carry(H)
    local X3 = fe_mul(E, F)
    local Y3 = fe_mul(G, H)
    local T3 = fe_mul(E, H)
    local Z3 = fe_mul(F, G)
    return {X3, Y3, Z3, T3}
end

-- Point addition - direct port of TweetNaCl's add()
-- Uses (Y1-X1)(Y2-X2) / (X1+Y1)(X2+Y2) decomposition with D2=2d
local function ge_add(p, q)
    local a = fe_mul(fe_sub(p[2], p[1]), fe_sub(q[2], q[1]))  -- (Y1-X1)*(Y2-X2)
    local b = fe_mul(fe_add(p[1], p[2]), fe_add(q[1], q[2]))  -- (X1+Y1)*(X2+Y2)
    local c = fe_mul(fe_mul(p[4], q[4]), D2)                   -- T1*T2*2d
    local d = fe_mul(p[3], q[3])                                -- Z1*Z2
    d = fe_add(d, d)                                             -- 2*Z1*Z2
    local e = fe_sub(b, a)
    local f = fe_sub(d, c)
    local g = fe_add(d, c)
    local h = fe_add(b, a)
    return {fe_mul(e, f), fe_mul(h, g), fe_mul(g, f), fe_mul(e, h)}
end

-- Scalar multiplication: s * P
local function ge_scalarmult(s, p)
    -- s is 32-byte array (little-endian scalar)
    local Q = ge_zero()
    for i = 255, 0, -1 do
        Q = ge_double(Q)
        local byte_idx = floor(i / 8) + 1
        local bit_idx = i % 8
        local bit = floor(s[byte_idx] / (2 ^ bit_idx)) % 2
        if bit == 1 then
            Q = ge_add(Q, p)
        end
    end
    return Q
end

local function ge_scalarmult_base(s)
    return ge_scalarmult(s, {fe_copy(BX), fe_copy(BY), fe_copy(BZ), fe_copy(BT)})
end

-- Compress point to 32 bytes
local function ge_tobytes(p)
    local X, Y, Z = p[1], p[2], p[3]
    local zi = fe_inv(Z)
    local x = fe_mul(X, zi)
    local y = fe_mul(Y, zi)
    local s = fe_tobytes(y)
    -- Encode sign of x in top bit of last byte
    local x_bytes = fe_tobytes(x)
    s[32] = s[32] + (x_bytes[1] % 2) * 128
    return s
end

-- ---
-- Scalar Operations (mod L)
-- ---

-- Reduce 64-byte scalar mod L in place
local function sc_reduce(x)
    for ci = 63, 32, -1 do
        local carry = 0
        for cj = ci - 32, ci - 13 do
            x[cj + 1] = x[cj + 1] + carry - 16 * x[ci + 1] * L_BYTES[cj - ci + 33]
            carry = floor((x[cj + 1] + 128) / 256)
            x[cj + 1] = x[cj + 1] - carry * 256
        end
        x[ci - 11] = x[ci - 11] + carry
        x[ci + 1] = 0
    end
    local carry = 0
    for cj = 0, 31 do
        x[cj + 1] = x[cj + 1] + carry - floor(x[32] / 16) * L_BYTES[cj + 1]
        carry = floor(x[cj + 1] / 256)
        x[cj + 1] = x[cj + 1] % 256
    end
    for cj = 0, 31 do
        x[cj + 1] = x[cj + 1] - carry * L_BYTES[cj + 1]
    end
end

-- Compute (a * b + c) mod L
local function sc_muladd(a, b, c)
    local x = {}
    for i = 1, 64 do x[i] = 0 end
    for i = 1, 32 do
        local ai = a[i]
        for j = 1, 32 do
            x[i + j - 1] = x[i + j - 1] + ai * b[j]
        end
    end
    for i = 1, 32 do
        x[i] = x[i] + c[i]
    end
    for i = 1, 63 do
        x[i + 1] = x[i + 1] + floor(x[i] / 256)
        x[i] = x[i] % 256
    end
    x[64] = x[64] % 256
    sc_reduce(x)
    local result = {}
    for i = 1, 32 do result[i] = x[i] end
    return result
end

-- ---
-- Ed25519 Public API
-- ---

-- Clamp scalar (per RFC 8032)
local function clamp(a)
    a[1] = a[1] - (a[1] % 8)                -- clear bits 0,1,2
    a[32] = (a[32] % 64) + 64               -- clear bit 255, set bit 254
    return a
end

-- Generate keypair from 32-byte seed
function Ed25519.keypairFromSeed(seed)
    local h = sha512(seed)
    local a = {}
    for i = 1, 32 do a[i] = h[i] end
    clamp(a)
    local A = ge_scalarmult_base(a)
    local publicKey = ge_tobytes(A)
    return {
        seed = seed,
        scalar = a,
        prefix = {h[33], h[34], h[35], h[36], h[37], h[38], h[39], h[40],
                  h[41], h[42], h[43], h[44], h[45], h[46], h[47], h[48],
                  h[49], h[50], h[51], h[52], h[53], h[54], h[55], h[56],
                  h[57], h[58], h[59], h[60], h[61], h[62], h[63], h[64]},
        publicKey = publicKey,
    }
end

-- Derive public key from 32-byte seed
function Ed25519.publicKeyFromSeed(seed)
    local kp = Ed25519.keypairFromSeed(seed)
    return kp.publicKey
end

-- Sign message with keypair
-- Returns 64-byte signature
function Ed25519.sign(message, keypair)
    local a = keypair.scalar
    local prefix = keypair.prefix
    local publicKey = keypair.publicKey

    -- r = SHA-512(prefix || message) mod L
    local r_input = {}
    for i = 1, 32 do r_input[i] = prefix[i] end
    for i = 1, #message do r_input[32 + i] = message[i] end
    local r_hash = sha512(r_input)
    sc_reduce(r_hash)
    local r = {}
    for i = 1, 32 do r[i] = r_hash[i] end

    -- R = r * B
    local R = ge_scalarmult_base(r)
    local R_bytes = ge_tobytes(R)

    -- k = SHA-512(R || A || message) mod L
    local k_input = {}
    for i = 1, 32 do k_input[i] = R_bytes[i] end
    for i = 1, 32 do k_input[32 + i] = publicKey[i] end
    for i = 1, #message do k_input[64 + i] = message[i] end
    local k_hash = sha512(k_input)
    sc_reduce(k_hash)
    local k = {}
    for i = 1, 32 do k[i] = k_hash[i] end

    -- S = (r + k * a) mod L
    local S = sc_muladd(k, a, r)

    -- Signature = R || S
    local sig = {}
    for i = 1, 32 do sig[i] = R_bytes[i] end
    for i = 1, 32 do sig[32 + i] = S[i] end
    return sig
end

-- Generate random bytes (NOT cryptographically secure!)
function Ed25519.randomBytes(n)
    local entropy = tostring(getTickCount()) ..
        tostring(math.random(1, 2147483647)) ..
        tostring(getRealTime().timestamp) ..
        tostring(math.random(1, 2147483647))
    local bytes = {}
    while #bytes < n do
        entropy = entropy .. tostring(math.random(1, 2147483647)) .. tostring(getTickCount())
        local hex = hash("sha512", entropy)
        for i = 1, math.min((n - #bytes) * 2, 128), 2 do
            bytes[#bytes + 1] = tonumber(hex:sub(i, i + 1), 16)
        end
    end
    return bytes
end

-- Helper: bytes to hex string
function Ed25519.bytesToHex(bytes)
    local hex = {}
    for i = 1, #bytes do
        hex[i] = string.format("%02x", bytes[i])
    end
    return table.concat(hex)
end

-- Helper: hex string to bytes
function Ed25519.hexToBytes(hexStr)
    local bytes = {}
    for i = 1, #hexStr, 2 do
        bytes[#bytes + 1] = tonumber(hexStr:sub(i, i + 1), 16)
    end
    return bytes
end

-- ---
-- SELF TEST - Run /soltest in MTA to diagnose
-- RFC 8032 Test Vector 1
-- ---

-- Check if 32 bytes represent a point on Ed25519 curve
-- Used by PDA derivation — PDA must NOT be on curve
function Crypto.isOnEdCurve(hashBytes)
    local y = fe_frombytes(hashBytes)
    local y2 = fe_sq(y)
    local u = fe_sub(y2, fe_1())
    local v = fe_add(fe_mul(D, y2), fe_1())
    local v3 = fe_mul(fe_mul(v, v), v)
    local v7 = fe_mul(fe_mul(v3, v3), v)
    local uv7 = fe_mul(fe_mul(u, v7), fe_1())
    -- pow2523: z^((p-5)/8) using square-and-multiply
    local function pow2523(z)
        local c = fe_copy(z)
        for i = 250, 0, -1 do
            c = fe_sq(c)
            if i ~= 1 then c = fe_mul(c, z) end
        end
        return c
    end
    local x = fe_mul(fe_mul(u, v3), pow2523(fe_mul(u, v7)))
    local vx2 = fe_mul(v, fe_sq(x))
    local check1 = fe_tobytes(fe_sub(vx2, u))
    local check2 = fe_tobytes(fe_add(vx2, u))
    local z1, z2 = true, true
    for i = 1, 32 do
        if check1[i] ~= 0 then z1 = false end
        if check2[i] ~= 0 then z2 = false end
    end
    return z1 or z2
end

function Ed25519.selfTest()
    local results = {}
    local function log(msg)
        results[#results + 1] = msg
        outputDebugString("[ed25519-test] " .. msg)
    end

    -- Test 1: SHA-512
    log("=== TEST 1: SHA-512 ===")
    local sha_out = sha512({0x61, 0x62, 0x63}) -- "abc"
    local sha_hex = Ed25519.bytesToHex(sha_out)
    local sha_expect = "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"
    local sha_ok = (sha_hex == sha_expect)
    log("Result:   " .. sha_hex:sub(1,32) .. "...")
    log("Expected: " .. sha_expect:sub(1,32) .. "...")
    log("SHA-512: " .. (sha_ok and "PASS" or "FAIL"))

    -- Test 2: Field arithmetic basics
    log("=== TEST 2: Field Arithmetic ===")
    local two = {2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
    local three = {3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
    local six = fe_mul(two, three)
    log("2 * 3 = limb[1]=" .. tostring(six[1]) .. " (expected 6)")
    local four = fe_sq(two)
    log("2^2 = limb[1]=" .. tostring(four[1]) .. " (expected 4)")
    local one_inv = fe_inv(fe_1())
    local one_inv_bytes = fe_tobytes(one_inv)
    log("inv(1) = byte[1]=" .. tostring(one_inv_bytes[1]) .. " (expected 1)")

    -- Test 3: Base point encoding
    log("=== TEST 3: Base Point ===")
    local bp = {fe_copy(BX), fe_copy(BY), fe_copy(BZ), fe_copy(BT)}
    local bp_bytes = ge_tobytes(bp)
    local bp_hex = Ed25519.bytesToHex(bp_bytes)
    local bp_expect = "5866666666666666666666666666666666666666666666666666666666666666"
    log("B compressed: " .. bp_hex:sub(1,32) .. "...")
    log("Expected:     " .. bp_expect:sub(1,32) .. "...")
    log("Base point: " .. (bp_hex == bp_expect and "PASS" or "FAIL"))

    -- Test 4: 1*B = B
    log("=== TEST 4: Scalar mult 1*B ===")
    local scalar_one = {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
    local result_1B = ge_scalarmult_base(scalar_one)
    local result_1B_bytes = ge_tobytes(result_1B)
    local result_1B_hex = Ed25519.bytesToHex(result_1B_bytes)
    log("1*B: " .. result_1B_hex:sub(1,32) .. "...")
    log("Exp: " .. bp_expect:sub(1,32) .. "...")
    log("1*B == B: " .. (result_1B_hex == bp_expect and "PASS" or "FAIL"))

    -- Test 5: 2*B
    log("=== TEST 5: 2*B ===")
    local scalar_two = {2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
    local result_2B = ge_scalarmult_base(scalar_two)
    local result_2B_bytes = ge_tobytes(result_2B)
    local result_2B_hex = Ed25519.bytesToHex(result_2B_bytes)
    local expect_2B = "c9a3f86aae465f0e56513864510f3997561fa2c9e85ea21dc2292309f3cd6022"
    log("2*B: " .. result_2B_hex)
    log("Exp: " .. expect_2B)
    log("2*B: " .. (result_2B_hex == expect_2B and "PASS" or "FAIL"))

    -- Test 6: Double B directly
    log("=== TEST 6: double(B) ===")
    local dbl_B = ge_double(bp)
    local dbl_B_bytes = ge_tobytes(dbl_B)
    local dbl_B_hex = Ed25519.bytesToHex(dbl_B_bytes)
    log("dbl(B): " .. dbl_B_hex)
    log("Exp:    " .. expect_2B)
    log("dbl(B): " .. (dbl_B_hex == expect_2B and "PASS" or "FAIL"))

    -- Test 7: B + B using ge_add
    log("=== TEST 7: B + B ===")
    local bp2 = {fe_copy(BX), fe_copy(BY), fe_copy(BZ), fe_copy(BT)}
    local add_BB = ge_add(bp, bp2)
    local add_BB_bytes = ge_tobytes(add_BB)
    local add_BB_hex = Ed25519.bytesToHex(add_BB_bytes)
    log("B+B:  " .. add_BB_hex)
    log("Exp:  " .. expect_2B)

    -- Test 7b: B+B via AFFINE (bypass projective, test field arithmetic directly)
    log("=== TEST 7b: B+B AFFINE (field math test) ===")
    -- x3 = 2*Bx*By / (1 + d*Bx^2*By^2)
    -- y3 = (By^2 + Bx^2) / (1 - d*Bx^2*By^2)
    local bx2 = fe_sq(BX)
    local by2 = fe_sq(BY)
    local bxby = fe_mul(BX, BY)
    local bx2by2 = fe_mul(bx2, by2)
    local d_bx2by2 = fe_mul(D, bx2by2)  -- d * Bx^2 * By^2
    local num_x = fe_add(bxby, bxby)  -- 2*Bx*By
    fe_carry(num_x)
    local den_x = fe_add(fe_1(), d_bx2by2)  -- 1 + d*Bx^2*By^2
    fe_carry(den_x)
    local num_y = fe_add(by2, bx2)  -- By^2 + Bx^2
    fe_carry(num_y)
    local den_y = fe_sub(fe_1(), d_bx2by2)  -- 1 - d*Bx^2*By^2
    fe_carry(den_y)
    local inv_den_x = fe_inv(den_x)
    local inv_den_y = fe_inv(den_y)
    local aff_x = fe_mul(num_x, inv_den_x)
    local aff_y = fe_mul(num_y, inv_den_y)
    -- Encode
    local aff_bytes = fe_tobytes(aff_y)
    local aff_x_bytes = fe_tobytes(aff_x)
    aff_bytes[32] = aff_bytes[32] + (aff_x_bytes[1] % 2) * 128
    local aff_hex = Ed25519.bytesToHex(aff_bytes)
    log("Affine: " .. aff_hex)
    log("Exp:    " .. expect_2B)
    log("Affine B+B: " .. (aff_hex == expect_2B and "PASS" or "FAIL"))

    -- Test 7c: Show raw projective coords of ge_add result
    log("=== TEST 7c: ge_add raw coords ===")
    local add_X = fe_tobytes(add_BB[1])
    local add_Y = fe_tobytes(add_BB[2])
    local add_Z = fe_tobytes(add_BB[3])
    log("X3: " .. Ed25519.bytesToHex(add_X):sub(1,16) .. "...")
    log("Y3: " .. Ed25519.bytesToHex(add_Y):sub(1,16) .. "...")
    log("Z3: " .. Ed25519.bytesToHex(add_Z):sub(1,16) .. "...")
    log("B+B: " .. (add_BB_hex == expect_2B and "PASS" or "FAIL"))

    -- Test 8: RFC 8032 keypair derivation
    log("=== TEST 8: RFC 8032 Keypair ===")
    local seed = Ed25519.hexToBytes("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
    -- Check SHA-512 of seed
    local seed_hash = sha512(seed)
    local seed_hash_hex = Ed25519.bytesToHex(seed_hash)
    log("SHA-512(seed): " .. seed_hash_hex:sub(1,32) .. "...")

    local kp = Ed25519.keypairFromSeed(seed)
    local pk_hex = Ed25519.bytesToHex(kp.publicKey)
    local pk_expect = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
    log("Derived PK: " .. pk_hex)
    log("Expected:   " .. pk_expect)
    log("Keypair: " .. (pk_hex == pk_expect and "PASS" or "FAIL"))

    -- Test 9: RFC 8032 signature
    log("=== TEST 9: RFC 8032 Sign ===")
    if pk_hex == pk_expect then
        local sig = Ed25519.sign({}, kp) -- sign empty message
        local sig_hex = Ed25519.bytesToHex(sig)
        local sig_expect = "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
        log("Signature: " .. sig_hex:sub(1,32) .. "...")
        log("Expected:  " .. sig_expect:sub(1,32) .. "...")
        log("Sign: " .. (sig_hex == sig_expect and "PASS" or "FAIL"))
    else
        log("Sign: SKIP (keypair failed)")
    end

    log("=== TESTS COMPLETE ===")
    return results
end
