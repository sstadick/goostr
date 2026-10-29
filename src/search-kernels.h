// Instantiated by search.c for each vector backend. No include guard: the
// algorithms are shared, but each instantiation has its own ISA and names.

// Every vector load is wholly inside the caller's slices. The loop bounds
// additionally guarantee that every candidate has room for the whole needle.
// a and b must be valid needle indices; !prefilter requires n.len <= 32.
static TARGET int64_t PACKED(byte_slice h, byte_slice n, int64_t a, int64_t b, uint8_t prefilter) {
    if (n.len > h.len || n.len < 2) return -1;
    const int64_t count = h.len - n.len + 1;
    const uint8_t x = n.data[a], y = n.data[b];
    int64_t pos = 0;
#ifdef WIDTH
    const vector vx = splat(x), vy = splat(y);
    const int64_t limit = count - WIDTH;
    for (; pos <= limit; pos += WIDTH) {
        uint64_t hits = mask(both(equal(load(h.data + pos + a), vx), equal(load(h.data + pos + b), vy)));
        while (hits) {
            const unsigned bit = (unsigned)__builtin_ctzll(hits);
            const int64_t at = pos + bit / MASK_STEP;
            if (prefilter || equal_short(h.data + at, n.data, n.len)) return at;
            hits &= hits - 1;
        }
    }
#endif
    for (; pos < count; pos++) {
        if (h.data[pos + a] == x && h.data[pos + b] == y &&
            (prefilter || equal_short(h.data + pos, n.data, n.len))) return pos;
    }
    return -1;
}

// count is constant at each call site, eliminating unused comparisons. The
// same bounded scan handles membership and its complement in either direction.
static TARGET ALWAYS_INLINE int64_t SMALL(byte_slice h, uint8_t n1, uint8_t n2, uint8_t n3,
                                        int count, uint8_t reverse, uint8_t invert) {
    if (h.len <= 0) return -1;
#define MATCH_BYTE(v) (((v) == n1 || (count >= 2 && (v) == n2) || (count == 3 && (v) == n3)) != invert)
#ifdef WIDTH
    const vector v1 = splat(n1), v2 = splat(n2), v3 = splat(n3);
    const vector flip = splat(invert ? 255 : 0);
#define TEST(p) xorv(count == 1 ? equal(load(p), v1) : \
    count == 2 ? either(equal(load(p), v1), equal(load(p), v2)) : \
    either(either(equal(load(p), v1), equal(load(p), v2)), equal(load(p), v3)), flip)
    if (!reverse) {
        int64_t pos = 0;
        while (h.len - pos >= 4 * WIDTH) {
            vector a = TEST(h.data + pos), b = TEST(h.data + pos + WIDTH);
            vector c = TEST(h.data + pos + 2 * WIDTH), d = TEST(h.data + pos + 3 * WIDTH);
            if (mask(either(either(a, b), either(c, d)))) {
                uint64_t hits;
                if ((hits = mask(a))) return pos + __builtin_ctzll(hits) / MASK_STEP;
                if ((hits = mask(b))) return pos + WIDTH + __builtin_ctzll(hits) / MASK_STEP;
                if ((hits = mask(c))) return pos + 2 * WIDTH + __builtin_ctzll(hits) / MASK_STEP;
                return pos + 3 * WIDTH + __builtin_ctzll(mask(d)) / MASK_STEP;
            }
            pos += 4 * WIDTH;
        }
        while (h.len - pos >= WIDTH) {
            const uint64_t hits = mask(TEST(h.data + pos));
            if (hits) return pos + __builtin_ctzll(hits) / MASK_STEP;
            pos += WIDTH;
        }
        // Overlap the final in-bounds vector instead of scanning its tail
        // byte by byte. Any overlapping bytes have already failed to match.
        if (pos < h.len && h.len >= WIDTH) {
            pos = h.len - WIDTH;
            const uint64_t hits = mask(TEST(h.data + pos));
            return hits ? pos + __builtin_ctzll(hits) / MASK_STEP : -1;
        }
        for (; pos < h.len; pos++) if (MATCH_BYTE(h.data[pos])) return pos;
        return -1;
    }
    int64_t end = h.len;
    while (end >= 4 * WIDTH) {
        end -= 4 * WIDTH;
        vector a = TEST(h.data + end), b = TEST(h.data + end + WIDTH);
        vector c = TEST(h.data + end + 2 * WIDTH), d = TEST(h.data + end + 3 * WIDTH);
        if (mask(either(either(a, b), either(c, d)))) {
            uint64_t hits;
            if ((hits = mask(d))) return end + 3 * WIDTH + (63 - __builtin_clzll(hits)) / MASK_STEP;
            if ((hits = mask(c))) return end + 2 * WIDTH + (63 - __builtin_clzll(hits)) / MASK_STEP;
            if ((hits = mask(b))) return end + WIDTH + (63 - __builtin_clzll(hits)) / MASK_STEP;
            return end + (63 - __builtin_clzll(mask(a))) / MASK_STEP;
        }
    }
    while (end >= WIDTH) {
        end -= WIDTH;
        const uint64_t hits = mask(TEST(h.data + end));
        if (hits) return end + (63 - __builtin_clzll(hits)) / MASK_STEP;
    }
    if (end > 0 && h.len >= WIDTH) {
        const uint64_t hits = mask(TEST(h.data));
        return hits ? (63 - __builtin_clzll(hits)) / MASK_STEP : -1;
    }
#undef TEST
#else
    if (!reverse && !invert && count == 1) {
        const uint8_t *p = (const uint8_t *)memchr(h.data, n1, (size_t)h.len);
        return p ? p - h.data : -1;
    }
    if (!reverse) {
        for (int64_t i = 0; i < h.len; i++) if (MATCH_BYTE(h.data[i])) return i;
        return -1;
    }
    int64_t end = h.len;
#endif
    while (end > 0) { end--; if (MATCH_BYTE(h.data[end])) return end; }
#undef MATCH_BYTE
    return -1;
}

static TARGET int64_t BYTE(byte_slice h, uint8_t byte, uint8_t reverse) {
    return SMALL(h, byte, 0, 0, 1, reverse, 0);
}

// Only called for sets of 1..3 bytes. Duplicate bytes need no special case.
static TARGET int64_t SET(byte_slice h, byte_slice n, uint8_t reverse, uint8_t invert) {
    // Specialize inversion too: positive scans need no per-vector XOR.
    if (!invert) {
        if (n.len == 1) return SMALL(h, n.data[0], 0, 0, 1, reverse, 0);
        if (n.len == 2) return SMALL(h, n.data[0], n.data[1], 0, 2, reverse, 0);
        return SMALL(h, n.data[0], n.data[1], n.data[2], 3, reverse, 0);
    }
    if (n.len == 1) return SMALL(h, n.data[0], 0, 0, 1, reverse, 1);
    if (n.len == 2) return SMALL(h, n.data[0], n.data[1], 0, 2, reverse, 1);
    return SMALL(h, n.data[0], n.data[1], n.data[2], 3, reverse, 1);
}

#undef TARGET
#undef PACKED
#undef BYTE
#undef SMALL
#undef SET
#undef vector
#undef WIDTH
#undef MASK_STEP
#undef load
#undef splat
#undef equal
#undef both
#undef either
#undef xorv
#undef mask
