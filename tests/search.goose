import goostr from "..";
import goosimd from "github.com/sstadick/goosimd@d030164f014e366a05bcd45f508e699edec10b89";

// Independent membership oracle: no ByteSet or SIMD helpers from the library.
fn check_set(h: const u8[:], n: const u8[:]) {
    var first = -1;
    var last = -1;
    var first_not = -1;
    var last_not = -1;
    for b, i in h {
        var member = false;
        for candidate in n { if b == candidate { member = true; break; } }
        if member {
            if first < 0 { first = i; }
            last = i;
        } else {
            if first_not < 0 { first_not = i; }
            last_not = i;
        }
    }
    assert(goostr::find_byteset(h, n) == first);
    assert(goostr::rfind_byteset(h, n) == last);
    assert(goostr::find_not_byteset(h, n) == first_not);
    assert(goostr::rfind_not_byteset(h, n) == last_not);
}

// Independent, deliberately naive oracle. Also check reusable finders with
// different haystacks so preprocessing and its borrowing contract are exercised.
fn check(h: const u8[:], n: const u8[:]) {
    check_set(h, n);
    let f = goostr::finder(n);
    let r = goostr::finder_reverse(n);
    assert(goostr::find(h, n) == ::find(h, n));
    assert(goostr::rfind(h, n) == ::rfind(h, n));
    assert(goostr::find(f, h) == ::find(h, n));
    assert(goostr::rfind(r, h) == ::rfind(h, n));
    assert(goostr::find(f, h[..h.len / 2]) == ::find(h[..h.len / 2], n));
    assert(goostr::rfind(r, h[h.len / 2..]) == ::rfind(h[h.len / 2..], n));
    var start = 0;
    goostr::find_iter(h, n) { at =>
        assert(start <= h.len);
        let expected = ::find(h[start..], n);
        assert(expected >= 0 && at == start + expected);
        start = at + max(1, n.len);
    }
    assert(start > h.len || ::find(h[start..], n) == -1);
    var end = h.len;
    goostr::rfind_iter(h, n) { at =>
        assert(end >= 0);
        assert(at == ::rfind(h[..end], n));
        end = at - (if n.len == 0 { 1 } else { 0 });
    }
    assert(end < 0 || ::rfind(h[..end], n) == -1);
}

fn random(state: u64&) -> u64 {
    state = state * 6364136223846793005 + 1442695040888963407;
    return state >> 32;
}

fn main() {
    var count = 0;
    // Exhaust all short binary haystacks and needles, including overlapping
    // periodic matches, empty patterns, and both lexicographic suffix choices.
    for hlen in 0..9 {
        for hbits in 0..(1 << hlen) {
            var h: u8[>..] = [];
            for i in hlen { h.push(('a' + ((hbits >> i) & 1)) as u8); }
            for nlen in 0..6 {
                for nbits in 0..(1 << nlen) {
                    var n: u8[>..] = [];
                    for i in nlen { n.push(('a' + ((nbits >> i) & 1)) as u8); }
                    check(h, n);
                    count += 1;
                }
            }
        }
    }
    // SIMD widths, short/long needle threshold, tiny-haystack threshold, and
    // pair-selection cutoff; hits at every byte offset and at the final byte.
    for nlen in [1, 2, 3, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127, 255, 256, 257, 513] {
        var n: u8[>..] = [];
        for i in nlen { n.push((i % 7) as u8); }
        for offset in 0..160 {
            var h: u8[>..] = [];
            h.resize(offset, 255);
            h.append(n);
            check(h, n);
            h.push(255);
            check(h, n);
            count += 2;
        }
    }
    // Multiple SIMD candidates, including a false candidate after the last
    // full match. Changing each byte leaves some pair-filter hits intact.
    for len in [31, 35, 160] {
        var candidates: u8[>..] = [];
        candidates.resize(len, 255);
        let pattern = "abcd";
        for at in [0, 7, len / 2, len - pattern.len] {
            for i in pattern.len { candidates[at + i] = pattern[i]; }
        }
        check(candidates, pattern);
        count += 1;
        for i in pattern.len {
            candidates[len - pattern.len + i] ^= 128;
            check(candidates, pattern);
            candidates[len - pattern.len + i] ^= 128;
            count += 1;
        }
    }
    // Defeat the rare-pair prefilter (the distinct byte lies after offset
    // 255), exercising its retirement and Two-Way's periodic memory.
    for nlen in [33, 64, 256, 513] {
        var h: u8[>..] = [];
        h.resize(8192, 'a');
        var n: u8[>..] = [];
        n.resize(nlen, 'a');
        for where in [0, nlen / 2, nlen - 1] {
            n[where] = 'b';
            check(h, n);
            n[where] = 'a';
            count += 1;
        }
        check(h, n);
        count += 1;
    }
    var state: u64 = 0xB57;
    for trial in 6000 {
        let hlen = (random(state) % 2048) as i64;
        let nlen = (random(state) % 400) as i64;
        let alphabet = if trial % 2 == 0 { 3 } else { 256 };
        var h: u8[>..] = [];
        for i in hlen { h.push((random(state) % alphabet as u64) as u8); }
        var n: u8[>..] = [];
        if trial % 3 != 0 && nlen <= hlen {
            let at = (random(state) % (hlen - nlen + 1) as u64) as i64;
            n.append(h[at..at + nlen]);
        } else {
            for i in nlen { n.push((random(state) % alphabet as u64) as u8); }
        }
        check(h, n);
        count += 1;
    }
    print(count, " search cases passed");

    // Every position around 16/32-byte vectors and 64/128-byte unrolling.
    // Include high bits, NUL, duplicate set members, empty and full sets.
    var set_cases = 0;
    for size in 0..6 {
        var n: u8[>..] = [];
        for i in size { n.push([0, 128, 255, 1, 128][i] as u8); }
        for len in [0, 1, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 129, 160] {
            var h: u8[>..] = [];
            h.resize(len, 7);
            check_set(h, n);
            set_cases += 1;
            for at in len {
                h[at] = 128;
                check_set(h, n);
                h[at] = 255;
                check_set(h, n);
                h[at] = 0;
                check_set(h, n);
                h[at] = 7;
                set_cases += 3;
            }
            for i in len { h[i] = 0; }
            for at in len {
                h[at] = 7;
                check_set(h, n);
                h[at] = 0;
                set_cases += 1;
            }
        }
    }
    var all: u8[>..] = [];
    for byte in 256 { all.push(byte as u8); }
    check_set(all, all);
    check_set(all, all[..255]);
    check_set(all, all[1..]);
    check_set(all, "\xFF\xFF\xFF");
    var duplicates: u8[>..] = [];
    duplicates.resize(257, 0);
    check_set(all, duplicates);
    duplicates.append(all);
    check_set(all, duplicates);
    print(set_cases + 6, " additional byte-set cases passed");
}
