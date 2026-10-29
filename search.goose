// Search algorithms ported from memchr 2.8.3 (the engine used by bstr).
// Copyright (c) 2015 Andrew Gallant. MIT; see LICENSE.
namespace goostr;
import std;

extern "goostr_packed" fn packed(s: const u8[:], needle: const u8[:], a: i64, b: i64, prefilter: bool) -> i64;
extern "goostr_byte" fn byte_search(s: const u8[:], byte: u8, reverse: bool) -> i64;
extern "goostr_byteset" fn byteset_search(s: const u8[:], set: const u8[:], reverse: bool, invert: bool) -> i64;

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
struct FinderReverse { needle: const u8[:], two: TwoWay }

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
    for byte in s { bits |= (1 as u64) << (byte & 63); }
    return TwoWay { critical: if reverse { s.len - critical } else { critical },
        period: period, memory: if small { s.len - period } else { 0 }, bytes: bits };
}

fn finder(needle: const u8[:]) -> Finder {
    var f = Finder { needle: needle, a: 0, b: 0, two: default<TwoWay>() };
    if needle.len < 2 { return f; }
    f.b = 1;
    if BYTE_RANK[needle[f.b]] < BYTE_RANK[needle[f.a]] { f.a = 1; f.b = 0; }
    for i in 2..min(needle.len, 255) {
        if BYTE_RANK[needle[i]] < BYTE_RANK[needle[f.a]] { f.b = f.a; f.a = i; }
        else if needle[i] != needle[f.a] && BYTE_RANK[needle[i]] < BYTE_RANK[needle[f.b]] { f.b = i; }
    }
    if needle.len > 32 { f.two = two_way(needle, false); }
    return f;
}

fn finder_reverse(needle: const u8[:]) -> FinderReverse {
    return FinderReverse { needle: needle, two: two_way(needle, true) };
}

// Rabin-Karp is restricted to haystacks shorter than 64 bytes. Its tiny
// setup cost wins there; the size bound prevents quadratic asymptotics.
inline fn rabin_karp(s: const u8[:], needle: const u8[:], reverse: bool) -> i64 {
    if needle.len > s.len { return -1; }
    if needle.len == 0 { return if reverse { s.len } else { 0 }; }
    var want: u32 = 0;
    var have: u32 = 0;
    var power: u32 = 1;
    for i in needle.len {
        want = (want << 1) + needle[if reverse { needle.len - 1 - i } else { i }];
        have = (have << 1) + s[if reverse { s.len - 1 - i } else { i }];
        if i > 0 { power <<= 1; }
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
    if needle.len <= 32 { return packed(s, needle, f.a, f.b, false); }
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
        while i < needle.len && needle[i] == s[pos + i] { i += 1; }
        if i < needle.len {
            pos += i - f.two.critical + 1;
            memory = 0;
        } else {
            var j = f.two.critical;
            let stop = if periodic { memory } else { 0 };
            while j > stop && needle[j - 1] == s[pos + j - 1] { j -= 1; }
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
    if f.two.memory > 0 { return rfind_two_way(f, s, true); }
    return rfind_two_way(f, s, false);
}

inline fn rfind_two_way(f: const FinderReverse&, s: const u8[:], periodic: bool) -> i64 {
    let needle = f.needle;
    var pos = s.len;
    var memory = needle.len;
    while pos >= needle.len {
        let base = pos - needle.len;
        if f.two.bytes & ((1 as u64) << (s[base] & 63)) == 0 {
            pos -= needle.len; memory = needle.len; continue;
        }
        var i = if periodic { min(f.two.critical, memory) } else { f.two.critical };
        while i > 0 && needle[i - 1] == s[base + i - 1] { i -= 1; }
        if i > 0 {
            pos -= f.two.critical - i + 1;
            memory = needle.len;
        } else {
            var j = f.two.critical;
            let stop = if periodic { memory } else { needle.len };
            while j < stop && needle[j] == s[base + j] { j += 1; }
            if j >= stop { return base; }
            pos -= f.two.period;
            memory = needle.len - f.two.memory;
        }
    }
    return -1;
}

fn find(s: const u8[:], needle: const u8[:]) -> i64 {
    if s.len < 64 { return rabin_karp(s, needle, false); }
    if needle.len > s.len { return -1; }
    let f = finder(needle);
    return find(f, s);
}

fn rfind(s: const u8[:], needle: const u8[:]) -> i64 {
    if s.len < 64 { return rabin_karp(s, needle, true); }
    if needle.len > s.len { return -1; }
    let f = finder_reverse(needle);
    return rfind(f, s);
}
