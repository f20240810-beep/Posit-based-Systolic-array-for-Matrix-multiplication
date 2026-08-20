# Golden reference model for Posit(8,0): nbits=8, es=0

def decode(p, nbits=8):
    p &= (1<<nbits)-1
    if p == 0:
        return 0.0
    if p == (1<<(nbits-1)):
        return float('nan')  # NaR
    sign = (p >> (nbits-1)) & 1
    if sign:
        p = ((1<<nbits) - p) & ((1<<nbits)-1)
    i = nbits - 2          # index of first regime bit (bit6 for nbits=8)
    regime_bit = (p >> i) & 1
    run = 1
    i -= 1
    if regime_bit == 1:
        while i >= 0 and ((p >> i) & 1) == 1:
            run += 1
            i -= 1
        k = run - 1
        if i >= 0:
            i -= 1  # consume terminating 0
    else:
        while i >= 0 and ((p >> i) & 1) == 0:
            run += 1
            i -= 1
        k = -run
        if i >= 0:
            i -= 1  # consume terminating 1
    frac_bits = i + 1
    frac = p & ((1<<frac_bits)-1) if frac_bits > 0 else 0
    value = (2.0**k) * (1 + (frac / (2**frac_bits) if frac_bits > 0 else 0))
    return -value if sign else value

table = {p: decode(p) for p in range(256)}
finite_pos = sorted(set(v for p,v in table.items() if v==v and v>0))
print("maxpos:", max(finite_pos), "minpos:", min(finite_pos), "count:", len(finite_pos))
print("0x40 (expect 1.0):", table[0x40])
print("0x41 (expect 1.03125):", table[0x41])
print("0x3F (expect ~0.96875):", table[0x3F])
for p in [0,1,2,4,8,16,32,63,64,65,96,127]:
    print(hex(p), bin(p)[2:].zfill(8), table[p])

# ---- Encoder: nearest Posit(8,0) for a given real value, round-to-nearest-even, saturating ----
def encode(x, nbits=8):
    if x == 0:
        return 0
    sign = 1 if x < 0 else 0
    x = abs(x)
    best_p, best_err = 0, None
    for p in range(0, 256):
        if p == 128:
            continue
        v = decode(p, nbits)
        if v != v or v < 0:
            continue
        err = abs(v - x)
        if best_err is None or err < best_err or (err == best_err and (p % 2) == 0):
            best_err, best_p = err, p
    return ((256 - best_p) & 0xFF) if sign else best_p

def int8_to_posit8(val):
    return encode(float(val))

def posit8_to_int8(p):
    v = decode(p)
    if v != v:
        return 0  # NaR -> 0 (documented limitation)
    import math
    v = math.floor(abs(v) + 0.5) * (1 if v >= 0 else -1)
    return max(-128, min(127, v))

def posit_mult(pa, pb):
    va, vb = decode(pa), decode(pb)
    if va != va or vb != vb:
        return 128
    return encode(va * vb)

def posit_add(pa, pb):
    va, vb = decode(pa), decode(pb)
    if va != va or vb != vb:
        return 128
    return encode(va + vb)

if __name__ == "__main__":
    print("int8_to_posit8 tests:")
    for v in [0, 1, -1, 5, -5, 64, -64, 100, -100, 127, -128, 3, 7]:
        p = int8_to_posit8(v)
        print(f"  {v:5d} -> posit=0x{p:02x} ({p:08b}) decode={decode(p)}")
