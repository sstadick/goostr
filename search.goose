// Search algorithms ported from memchr 2.8.3 (the engine used by bstr).
// Copyright (c) 2015 Andrew Gallant. MIT; see LICENSE.
namespace goostr;
import std;
import goosimd from "github.com/sstadick/goosimd@main";

// Bounded, overlapping loads verify 2..32 bytes without a memcmp call in
// the candidate loop. All loads stay within both slices.
inline fn equal_short(s: const u8[:], needle: const u8[:]) -> bool {
    let n = needle.len;
    if n >= 16 {
        return ((goosimd::load_u64(s) ^ goosimd::load_u64(needle)) |
            (goosimd::load_u64(s[8..]) ^ goosimd::load_u64(needle[8..])) |
            (goosimd::load_u64(s[n - 16..]) ^ goosimd::load_u64(needle[n - 16..])) |
            (goosimd::load_u64(s[n - 8..]) ^ goosimd::load_u64(needle[n - 8..]))) == 0;
    }
    if n >= 8 {
        return ((goosimd::load_u64(s) ^ goosimd::load_u64(needle)) |
            (goosimd::load_u64(s[n - 8..]) ^ goosimd::load_u64(needle[n - 8..]))) == 0;
    }
    if n >= 4 {
        return ((goosimd::load_u32(s) ^ goosimd::load_u32(needle)) |
            (goosimd::load_u32(s[n - 4..]) ^ goosimd::load_u32(needle[n - 4..]))) == 0;
    }
    return ((goosimd::load_u16(s) ^ goosimd::load_u16(needle)) |
        (goosimd::load_u16(s[n - 2..]) ^ goosimd::load_u16(needle[n - 2..]))) == 0;
}

fn packed(s: const u8[:], needle: const u8[:], a: i64, b: i64, prefilter: bool) -> i64 {
    if needle.len > s.len || needle.len < 2 { return -1; }
    let x = needle[a];
    let y = needle[b];
    let count = s.len - needle.len + 1;
    var xs = s[a..a + count];
    var ys = s[b..b + count];
    // Each lane represents a start position with room for the whole needle.
    while xs.len >= 32 {
        let vx = goosimd::load<goosimd::U8x32>(xs).eq(x);
        let vy = goosimd::load<goosimd::U8x32>(ys).eq(y);
        var hits = vx.bit_and(vy).to_bits();
        if hits == 0 {
            xs = xs[32..];
            ys = ys[32..];
            // Scan misses two blocks at a time, without delaying early hits.
            while xs.len >= 64 {
                let x0 = goosimd::load<goosimd::U8x32>(xs).eq(x);
                let y0 = goosimd::load<goosimd::U8x32>(ys).eq(y);
                let x1 = goosimd::load<goosimd::U8x32>(xs[32..]).eq(x);
                let y1 = goosimd::load<goosimd::U8x32>(ys[32..]).eq(y);
                if x0.bit_and(y0).bit_or(x1.bit_and(y1)).to_bits() != 0 { break; }
                xs = xs[64..];
                ys = ys[64..];
            }
            continue;
        }
        while hits != 0 {
            let at = count - xs.len + ctz(hits);
            if prefilter || equal_short(s[at..], needle) { return at; }
            hits &= hits - 1;
        }
        xs = xs[32..];
        ys = ys[32..];
    }
    for pos in xs.len {
        let at = count - xs.len + pos;
        if xs[pos] == x && ys[pos] == y &&
            (prefilter || equal_short(s[at..], needle)) { return at; }
    }
    return -1;
}

fn packed_reverse(s: const u8[:], needle: const u8[:], a: i64, b: i64) -> i64 {
    if needle.len > s.len || needle.len < 2 { return -1; }
    let x = needle[a];
    let y = needle[b];
    let count = s.len - needle.len + 1;
    var xs = s[a..a + count];
    var ys = s[b..b + count];
    while xs.len >= 32 {
        let start = xs.len - 32;
        let vx = goosimd::load<goosimd::U8x32>(xs[start..]).eq(x);
        let vy = goosimd::load<goosimd::U8x32>(ys[start..]).eq(y);
        var hits = vx.bit_and(vy).to_bits();
        while hits != 0 {
            let lane = 63 - clz(hits);
            let at = start + lane;
            if equal_short(s[at..], needle) { return at; }
            hits &= ~((1 as u32) << lane);
        }
        xs = xs[..start];
        ys = ys[..start];
    }
    for offset in xs.len {
        let at = xs.len - 1 - offset;
        if xs[at] == x && ys[at] == y && equal_short(s[at..], needle) { return at; }
    }
    return -1;
}

// Cover 16..31 candidate positions with two overlapping 16-byte blocks.
// Keep this separate so the wide loop does not carry the narrow path's state.
inline fn packed_small(s: const u8[:], needle: const u8[:], a: i64, b: i64, reverse: bool) -> i64 {
    let last = s.len - needle.len + 1 - 16;
    let x = needle[a];
    let y = needle[b];
    let xs = s[a..];
    let ys = s[b..];
    let first_x = goosimd::load<goosimd::U8x16>(xs).eq(x);
    let first_y = goosimd::load<goosimd::U8x16>(ys).eq(y);
    let last_x = goosimd::load<goosimd::U8x16>(xs[last..]).eq(x);
    let last_y = goosimd::load<goosimd::U8x16>(ys[last..]).eq(y);
    var hits = first_x.bit_and(first_y).to_bits() |
        (last_x.bit_and(last_y).to_bits() << last);
    while hits != 0 {
        let at = if reverse { 63 - clz(hits) } else { ctz(hits) };
        if equal_short(s[at..], needle) { return at; }
        if reverse { hits &= ~((1 as u32) << at); }
        else { hits &= hits - 1; }
    }
    return -1;
}

inline fn small_test(s: const u8[:], a: u8, b: u8, c: u8, count: i64, invert: bool) -> goosimd::Mask<u8[32]> {
    let v = goosimd::load<goosimd::U8x32>(s);
    var hits = v.eq(a);
    if count >= 2 { hits = hits.bit_or(v.eq(b)); }
    if count == 3 { hits = hits.bit_or(v.eq(c)); }
    if invert { hits = hits.bit_not(); }
    return hits;
}

inline fn small_mask16(s: const u8[:], a: u8, b: u8, c: u8, count: i64, invert: bool) -> u32 {
    let v = goosimd::load<goosimd::U8x16>(s);
    var hits = v.eq(a);
    if count >= 2 { hits = hits.bit_or(v.eq(b)); }
    if count == 3 { hits = hits.bit_or(v.eq(c)); }
    let mask = hits.to_bits();
    return if invert { mask ^ 0xFFFF } else { mask };
}

// Count and inversion are constants at the call sites. Misses test four
// blocks together; a hit resolves the first/last matching lane in order.
inline fn small_search(s: const u8[:], a: u8, b: u8, c: u8, count: i64, reverse: bool, invert: bool) -> i64 {
    if s.len < 32 && s.len >= 16 {
        if !reverse {
            let first = small_mask16(s, a, b, c, count, invert);
            if first != 0 { return ctz(first); }
            let last = small_mask16(s[s.len - 16..], a, b, c, count, invert);
            return if last != 0 { s.len - 16 + ctz(last) } else { -1 };
        }
        let last = small_mask16(s[s.len - 16..], a, b, c, count, invert);
        if last != 0 { return s.len - 16 + 63 - clz(last); }
        let first = small_mask16(s, a, b, c, count, invert);
        return if first != 0 { 63 - clz(first) } else { -1 };
    }
    var rest = s;
    if !reverse {
        while rest.len >= 128 {
            let v0 = small_test(rest, a, b, c, count, invert);
            let v1 = small_test(rest[32..], a, b, c, count, invert);
            let v2 = small_test(rest[64..], a, b, c, count, invert);
            let v3 = small_test(rest[96..], a, b, c, count, invert);
            if v0.bit_or(v1).bit_or(v2.bit_or(v3)).to_bits() != 0 {
                let base = s.len - rest.len;
                let m0 = v0.to_bits();
                let m1 = v1.to_bits();
                let m2 = v2.to_bits();
                if m0 != 0 { return base + ctz(m0); }
                if m1 != 0 { return base + 32 + ctz(m1); }
                if m2 != 0 { return base + 64 + ctz(m2); }
                return base + 96 + ctz(v3.to_bits());
            }
            rest = rest[128..];
        }
        while rest.len >= 32 {
            let hits = small_test(rest, a, b, c, count, invert).to_bits();
            if hits != 0 { return s.len - rest.len + ctz(hits); }
            rest = rest[32..];
        }
        // Overlap the last in-bounds block; earlier bytes have already missed.
        if rest.len > 0 && s.len >= 32 {
            let hits = small_test(s[s.len - 32..], a, b, c, count, invert).to_bits();
            return if hits != 0 { s.len - 32 + ctz(hits) } else { -1 };
        }
        for v, i in rest {
            if (v == a || (count >= 2 && v == b) || (count == 3 && v == c)) != invert {
                return s.len - rest.len + i;
            }
        }
        return -1;
    }
    while rest.len >= 128 {
        let base = rest.len - 128;
        let v0 = small_test(rest[base..], a, b, c, count, invert);
        let v1 = small_test(rest[base + 32..], a, b, c, count, invert);
        let v2 = small_test(rest[base + 64..], a, b, c, count, invert);
        let v3 = small_test(rest[base + 96..], a, b, c, count, invert);
        if v0.bit_or(v1).bit_or(v2.bit_or(v3)).to_bits() != 0 {
            let m3 = v3.to_bits();
            let m2 = v2.to_bits();
            let m1 = v1.to_bits();
            if m3 != 0 { return base + 96 + 63 - clz(m3); }
            if m2 != 0 { return base + 64 + 63 - clz(m2); }
            if m1 != 0 { return base + 32 + 63 - clz(m1); }
            return base + 63 - clz(v0.to_bits());
        }
        rest = rest[..base];
    }
    while rest.len >= 32 {
        let base = rest.len - 32;
        let hits = small_test(rest[base..], a, b, c, count, invert).to_bits();
        if hits != 0 { return base + 63 - clz(hits); }
        rest = rest[..base];
    }
    if rest.len > 0 && s.len >= 32 {
        let hits = small_test(s, a, b, c, count, invert).to_bits();
        return if hits != 0 { 63 - clz(hits) } else { -1 };
    }
    var end = rest.len;
    while end > 0 {
        end -= 1;
        let v = rest[end];
        if (v == a || (count >= 2 && v == b) || (count == 3 && v == c)) != invert { return end; }
    }
    return -1;
}

fn byte_search(s: const u8[:], byte: u8, reverse: bool) -> i64 {
    return small_search(s, byte, 0, 0, 1, reverse, false);
}

// Copy the constant directly, without a fill-literal temporary.
const EMPTY_MEMBERS: u8[256] = [0; 256];

fn byteset_search(s: const u8[:], set: const u8[:], reverse: bool, invert: bool) -> i64 {
    if s.len == 0 { return -1; }
    if set.len == 0 { return if invert { if reverse { s.len - 1 } else { 0 } } else { -1 }; }
    if set.len <= 3 {
        if !invert {
            if set.len == 1 { return small_search(s, set[0], 0, 0, 1, reverse, false); }
            if set.len == 2 { return small_search(s, set[0], set[1], 0, 2, reverse, false); }
            return small_search(s, set[0], set[1], set[2], 3, reverse, false);
        }
        if set.len == 1 { return small_search(s, set[0], 0, 0, 1, reverse, true); }
        if set.len == 2 { return small_search(s, set[0], set[1], 0, 2, reverse, true); }
        return small_search(s, set[0], set[1], set[2], 3, reverse, true);
    }
    var members = EMPTY_MEMBERS;
    for b in set { members[b] = 1; }
    if set.len >= 256 {
        var count = 0;
        for b in members { count += b; }
        if count == 256 { return if invert { -1 } else { if reverse { s.len - 1 } else { 0 } }; }
    }
    let excluded: u8 = if invert { 1 } else { 0 };
    if !reverse {
        var rest = s;
        while rest.len >= 4 {
            let base = s.len - rest.len;
            if members[rest[0]] != excluded { return base; }
            if members[rest[1]] != excluded { return base + 1; }
            if members[rest[2]] != excluded { return base + 2; }
            if members[rest[3]] != excluded { return base + 3; }
            rest = rest[4..];
        }
        for b, i in rest { if members[b] != excluded { return s.len - rest.len + i; } }
    } else {
        var end = s.len;
        while end >= 4 {
            if members[s[end - 1]] != excluded { return end - 1; }
            if members[s[end - 2]] != excluded { return end - 2; }
            if members[s[end - 3]] != excluded { return end - 3; }
            if members[s[end - 4]] != excluded { return end - 4; }
            end -= 4;
        }
        while end > 0 {
            end -= 1;
            if members[s[end]] != excluded { return end; }
        }
    }
    return -1;
}

// memchr's background-frequency ranks. Smaller means rarer. These select
// two predictive bytes, not necessarily the first and last needle bytes.
const BYTE_RANK: u8[256] = [
    55,52,51,50,49,48,47,46,45,103,242,66,67,229,44,43,
    42,41,40,39,38,37,36,35,34,33,56,32,31,30,29,28,
    255,148,164,149,136,160,155,173,221,222,134,122,232,202,215,224,
    208,220,204,187,183,179,177,168,178,200,226,195,154,184,174,126,
    120,191,157,194,170,189,162,161,150,193,142,137,171,176,185,167,
    186,112,175,192,188,156,140,143,123,133,128,147,138,146,114,223,
    151,249,216,238,236,253,227,218,230,247,135,180,241,233,246,244,
    231,139,245,243,251,235,201,196,240,214,152,182,205,181,127,27,
    212,211,210,213,228,197,169,159,131,172,105,80,98,96,97,81,
    207,145,116,115,144,130,153,121,107,132,109,110,124,111,82,108,
    118,141,113,129,119,125,165,117,92,106,83,72,99,93,65,79,
    166,237,163,199,190,225,209,203,198,217,219,206,234,248,158,239,
    255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,
    255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,
    255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,
    255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,
];

struct TwoWay { critical: i64, period: i64, memory: i64, bytes: u64 }
// Finders borrow their needle. Do not mutate it while the finder is in use.
struct Finder { needle: const u8[:], a: i64, b: i64, two: TwoWay }
struct FinderReverse { needle: const u8[:], two: TwoWay, a: i64, b: i64 }

inline fn suffix(s: const u8[:], maximal: bool, reverse: bool) -> i64, i64 {
    var best = 0;
    var period = 1;
    var candidate = 1;
    var offset = 0;
    while candidate + offset < s.len {
        let x = s[if reverse { s.len - 1 - best - offset } else { best + offset }];
        let y = s[if reverse { s.len - 1 - candidate - offset } else { candidate + offset }];
        if x == y {
            if offset + 1 == period { candidate += period; offset = 0; }
            else { offset += 1; }
        } else if (maximal && y > x) || (!maximal && y < x) {
            best = candidate;
            candidate += 1;
            period = 1;
            offset = 0;
        } else {
            candidate += offset + 1;
            offset = 0;
            period = candidate - best;
        }
    }
    return best, period;
}

inline fn two_way(s: const u8[:], reverse: bool) -> TwoWay {
    let a, ap = suffix(s, false, reverse);
    let b, bp = suffix(s, true, reverse);
    let critical = max(a, b);
    var period = if a > b { ap } else { bp };
    var small = critical * 2 < s.len;
    if small {
        if reverse { small = s[s.len - critical..] == s[s.len - period - critical..s.len - period]; }
        else { small = s[..critical] == s[period..period + critical]; }
    }
    if !small { period = max(critical, s.len - critical); }
    var bits: u64 = 0;
    // A periodic needle's first period contains its complete byte alphabet.
    let rest = if small { s[..period] } else { s };
    for byte in rest { bits |= (1 as u64) << (byte & 63); }
    return TwoWay { critical: if reverse { s.len - critical } else { critical },
        period: period, memory: if small { s.len - period } else { 0 }, bytes: bits };
}

inline fn rare_pair(needle: const u8[:]) -> i64, i64 {
    if needle.len < 2 { return 0, 0; }
    var a = 0;
    var b = 1;
    if BYTE_RANK[needle[b]] < BYTE_RANK[needle[a]] { a = 1; b = 0; }
    for i in 2..min(needle.len, 255) {
        if BYTE_RANK[needle[i]] < BYTE_RANK[needle[a]] { b = a; a = i; }
        else if needle[i] != needle[a] && BYTE_RANK[needle[i]] < BYTE_RANK[needle[b]] { b = i; }
    }
    return a, b;
}

fn finder(needle: const u8[:]) -> Finder {
    let a, b = rare_pair(needle);
    var f = Finder { needle: needle, a: a, b: b, two: default<TwoWay>() };
    if needle.len > 32 { f.two = two_way(needle, false); }
    return f;
}

fn finder_reverse(needle: const u8[:]) -> FinderReverse {
    var f = FinderReverse { needle: needle, two: two_way(needle, true), a: 0, b: 0 };
    if needle.len <= 32 {
        let a, b = rare_pair(needle);
        f.a = a;
        f.b = b;
    }
    return f;
}

// Tiny haystacks need no rare-pair preprocessing. Use the first/last bytes
// for 16..31 SIMD candidates, and Rabin-Karp otherwise.
// The 64-byte haystack bound prevents quadratic asymptotics.
inline fn find_small(s: const u8[:], needle: const u8[:], reverse: bool) -> i64 {
    if needle.len > s.len { return -1; }
    if needle.len == 0 { return if reverse { s.len } else { 0 }; }
    let candidates = s.len - needle.len + 1;
    if needle.len >= 2 && needle.len <= 32 && candidates >= 16 && candidates < 32 {
        return packed_small(s, needle, 0, needle.len - 1, reverse);
    }
    var want: u32 = 0;
    var have: u32 = 0;
    // The outgoing byte's weight is 2^(len - 1), modulo 2^32.
    let power: u32 = if needle.len <= 32 { (1 as u32) << (needle.len - 1) } else { 0 };
    for i in needle.len {
        want = (want << 1) + needle[if reverse { needle.len - 1 - i } else { i }];
        have = (have << 1) + s[if reverse { s.len - 1 - i } else { i }];
    }
    var pos = 0;
    while pos <= s.len - needle.len {
        let at = if reverse { s.len - needle.len - pos } else { pos };
        if have == want && s[at..at + needle.len] == needle { return at; }
        if pos == s.len - needle.len { return -1; }
        let old = s[if reverse { s.len - 1 - pos } else { pos }] as u32;
        let next = s[if reverse { s.len - 1 - pos - needle.len } else { pos + needle.len }] as u32;
        have = ((have - old * power) << 1) + next;
        pos += 1;
    }
    return -1;
}

fn find(f: const Finder&, s: const u8[:]) -> i64 {
    let needle = f.needle;
    if needle.len > s.len { return -1; }
    if needle.len == 0 { return 0; }
    if needle.len == 1 { return byte_search(s, needle[0], false); }
    if needle.len <= 32 {
        let candidates = s.len - needle.len + 1;
        if candidates >= 16 && candidates < 32 { return packed_small(s, needle, f.a, f.b, false); }
        return packed(s, needle, f.a, f.b, false);
    }
    if f.two.memory > 0 { return find_two_way(f, s, true); }
    return find_two_way(f, s, false);
}

// Specialize the periodic and nonperiodic loops, as memchr does, so ordinary
// needles don't pay for tracking the part of a periodic match already seen.
inline fn find_two_way(f: const Finder&, s: const u8[:], periodic: bool) -> i64 {
    let needle = f.needle;
    var pos = 0;
    var memory = 0;
    var skips = 0;
    var skipped = 0;
    var prefilter = true;
    while pos <= s.len - needle.len {
        // memchr's adaptive rule: after 50 attempts, retire a prefilter
        // averaging fewer than 8 bytes skipped. Never re-enable it here.
        if prefilter {
            if skips >= 50 && skipped < skips * 8 { prefilter = false; }
            else {
                let jump = packed(s[pos..], needle, f.a, f.b, true);
                if jump < 0 { return -1; }
                pos += jump;
                skipped += jump;
                skips += 1;
                memory = 0;
            }
        }
        if f.two.bytes & ((1 as u64) << (s[pos + needle.len - 1] & 63)) == 0 {
            pos += needle.len; memory = 0; continue;
        }
        var i = if periodic { max(f.two.critical, memory) } else { f.two.critical };
        if i < needle.len && needle[i] != s[pos + i] {
            pos += i - f.two.critical + 1;
            memory = 0;
            continue;
        }
        let window = s[pos..pos + needle.len];
        if i < needle.len {
            i += 1;
            while i < needle.len && needle[i] == window[i] { i += 1; }
        }
        if i < needle.len {
            pos += i - f.two.critical + 1;
            memory = 0;
        } else {
            var j = f.two.critical;
            let stop = if periodic { memory } else { 0 };
            while j > stop && needle[j - 1] == window[j - 1] { j -= 1; }
            if j <= stop { return pos; }
            pos += f.two.period;
            memory = f.two.memory;
        }
    }
    return -1;
}

fn rfind(f: const FinderReverse&, s: const u8[:]) -> i64 {
    let needle = f.needle;
    if needle.len > s.len { return -1; }
    if needle.len == 0 { return s.len; }
    if needle.len == 1 { return byte_search(s, needle[0], true); }
    if needle.len <= 32 {
        let candidates = s.len - needle.len + 1;
        if candidates >= 16 && candidates < 32 { return packed_small(s, needle, f.a, f.b, true); }
        if candidates >= 32 {
            let last = s.len - needle.len;
            if equal_short(s[last..], needle) { return last; }
            return packed_reverse(s, needle, f.a, f.b);
        }
    }
    if f.two.memory > 0 { return rfind_two_way(f, s, true); }
    return rfind_two_way(f, s, false);
}

inline fn rfind_two_way(f: const FinderReverse&, s: const u8[:], periodic: bool) -> i64 {
    let needle = f.needle;
    var rest = s;
    var memory = needle.len;
    while rest.len >= needle.len {
        let base = rest.len - needle.len;
        if f.two.bytes & ((1 as u64) << (rest[base] & 63)) == 0 {
            rest = rest[..base]; memory = needle.len; continue;
        }
        let window = rest[base..];
        var i = if periodic { min(f.two.critical, memory) } else { f.two.critical };
        if i > 0 && needle[i - 1] == window[i - 1] {
            i -= 1;
            while i >= 8 {
                if goosimd::load_u64(needle[i - 8..]) != goosimd::load_u64(window[i - 8..]) { break; }
                i -= 8;
            }
            while i > 0 && needle[i - 1] == window[i - 1] { i -= 1; }
        }
        if i > 0 {
            rest = rest[..rest.len - (f.two.critical - i + 1)];
            memory = needle.len;
        } else {
            var j = f.two.critical;
            let stop = if periodic { memory } else { needle.len };
            while j < stop && needle[j] == window[j] { j += 1; }
            if j >= stop { return base; }
            rest = rest[..rest.len - f.two.period];
            memory = needle.len - f.two.memory;
        }
    }
    return -1;
}

fn find(s: const u8[:], needle: const u8[:]) -> i64 {
    if s.len < 64 { return find_small(s, needle, false); }
    if needle.len > s.len { return -1; }
    let f = finder(needle);
    return find(f, s);
}

fn rfind(s: const u8[:], needle: const u8[:]) -> i64 {
    if s.len < 64 { return find_small(s, needle, true); }
    if needle.len > s.len { return -1; }
    if needle.len >= 2 && needle.len <= 32 {
        let last = s.len - needle.len;
        if equal_short(s[last..], needle) { return last; }
        let a, b = rare_pair(needle);
        return packed_reverse(s, needle, a, b);
    }
    let f = finder_reverse(needle);
    return rfind(f, s);
}
