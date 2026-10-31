// Native Goose byte strings, with bstr-compatible byte and UTF-8 semantics.
namespace goostr;

import std;
import .utf8;
import .search;

const UNLIMITED: i64 = 0x7FFFFFFFFFFFFFFF;

// Positions are byte offsets; -1 means not found, as in Goose's std library.
fn contains_str(s: const u8[:], needle: const u8[:]) -> bool { find(s, needle) >= 0 }
fn starts_with_str(s: const u8[:], prefix: const u8[:]) -> bool { ::starts_with(s, prefix) }
fn ends_with_str(s: const u8[:], suffix: const u8[:]) -> bool { ::ends_with(s, suffix) }

fn find_byte(s: const u8[:], byte: u8) -> i64 {
    return byte_search(s, byte, false);
}

fn rfind_byte(s: const u8[:], byte: u8) -> i64 {
    return byte_search(s, byte, true);
}

fn find_byteset(s: const u8[:], set: const u8[:]) -> i64 {
    return byteset_search(s, set, false, false);
}

fn find_not_byteset(s: const u8[:], set: const u8[:]) -> i64 {
    return byteset_search(s, set, false, true);
}

fn rfind_byteset(s: const u8[:], set: const u8[:]) -> i64 {
    return byteset_search(s, set, true, false);
}

fn rfind_not_byteset(s: const u8[:], set: const u8[:]) -> i64 {
    return byteset_search(s, set, true, true);
}

// Callback iteration: matches never overlap. Empty needles match every
// byte boundary, including both ends (even inside a UTF-8 codepoint).
fn find_iter<F>(s: const u8[:], needle: const u8[:]) {
    let searcher = finder(needle);
    var start = 0;
    while start <= s.len {
        let pos = find(searcher, s[start..]);
        if pos < 0 { return; }
        let at = start + pos;
        F(at);
        if needle.len == 0 && at == s.len { return; }
        start = at + max(1, needle.len);
    }
}

fn rfind_iter<F>(s: const u8[:], needle: const u8[:]) {
    let searcher = finder_reverse(needle);
    var end = s.len;
    while end >= 0 {
        let at = rfind(searcher, s[..end]);
        if at < 0 { return; }
        F(at);
        end = at - (if needle.len == 0 { 1 } else { 0 });
    }
}

// n limits the number of pieces, not the number of separators. Negative n
// is invalid. Views borrow s; no bytes are copied by splitting or iteration.
fn splitn_str<F>(s: const u8[:], needle: const u8[:], n: i64) {
    assert(n >= 0);
    if n == 0 { return; }
    var start = 0;
    var count = 0;
    find_iter(s, needle) { at =>
        if count == n - 1 { F(s[start..]); return; }
        F(s[start..at]);
        start = at + needle.len;
        count += 1;
    }
    F(s[start..]);
}

fn split_str<F>(s: const u8[:], needle: const u8[:]) {
    splitn_str(s, needle, UNLIMITED, F);
}

fn rsplitn_str<F>(s: const u8[:], needle: const u8[:], n: i64) {
    assert(n >= 0);
    if n == 0 { return; }
    var end = s.len;
    var count = 0;
    rfind_iter(s, needle) { at =>
        if count == n - 1 { F(s[..end]); return; }
        F(s[at + needle.len..end]);
        end = at;
        count += 1;
    }
    F(s[..end]);
}

fn rsplit_str<F>(s: const u8[:], needle: const u8[:]) {
    rsplitn_str(s, needle, UNLIMITED, F);
}

// The bool reports whether a separator was found. On failure both views
// are empty. On success the separator itself is omitted.
fn split_once_str(s: const u8[:], needle: const u8[:]) -> const u8[:], const u8[:], bool {
    let at = find(s, needle);
    if at < 0 { return s[..0], s[..0], false; }
    return s[..at], s[at + needle.len..], true;
}

fn rsplit_once_str(s: const u8[:], needle: const u8[:]) -> const u8[:], const u8[:], bool {
    let at = rfind(s, needle);
    if at < 0 { return s[..0], s[..0], false; }
    return s[..at], s[at + needle.len..], true;
}

// _into functions append; they never clear the caller's destination.
fn replacen_into(s: const u8[:], needle: const u8[:], replacement: const u8[:], n: i64, out: u8[>..]&) {
    assert(n >= 0);
    var start = 0;
    var count = 0;
    find_iter(s, needle) { at =>
        if count == n { out.append(s[start..]); return; }
        out.append(s[start..at]);
        out.append(replacement);
        start = at + needle.len;
        count += 1;
    }
    out.append(s[start..]);
}

fn replace_into(s: const u8[:], needle: const u8[:], replacement: const u8[:], out: u8[>..]&) {
    replacen_into(s, needle, replacement, UNLIMITED, out);
}

fn replacen(s: const u8[:], needle: const u8[:], replacement: const u8[:], n: i64) -> u8[>..] {
    var out: u8[>..] = [];
    replacen_into(s, needle, replacement, n, out);
    return out;
}

fn replace(s: const u8[:], needle: const u8[:], replacement: const u8[:]) -> u8[>..] {
    return replacen(s, needle, replacement, UNLIMITED);
}

fn repeatn(s: const u8[:], n: i64) -> u8[>..] {
    assert(n >= 0);
    var out: u8[>..] = [];
    if s.len == 0 { return out; }
    for i in n { out.append(s); }
    return out;
}

fn lines_with_terminator<F>(s: const u8[:]) {
    var start = 0;
    for b, i in s {
        if b == '\n' { F(s[start..i + 1]); start = i + 1; }
    }
    if start < s.len { F(s[start..]); }
}

// Only LF and CRLF terminate lines. A bare CR is ordinary data.
fn lines<F>(s: const u8[:]) {
    lines_with_terminator(s) { line =>
        var end = line.len;
        if line[end - 1] == '\n' {
            end -= 1;
            if end > 0 && line[end - 1] == '\r' { end -= 1; }
        }
        F(line[..end]);
    }
}

fn find_non_ascii_byte(s: const u8[:]) -> i64 {
    for b, i in s { if b >= 128 { return i; } }
    return -1;
}

fn is_ascii(s: const u8[:]) -> bool { find_non_ascii_byte(s) < 0 }

fn make_ascii_lowercase(s: u8[:]) {
    for &c in s {
        let mask: u8 = if c >= 'A' && c <= 'Z' { 32 } else { 0 };
        c |= mask;
    }
}

fn make_ascii_uppercase(s: u8[:]) {
    for &c in s {
        let mask: u8 = if c >= 'a' && c <= 'z' { 32 } else { 0 };
        c ^= mask;
    }
}

fn to_ascii_lowercase(s: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    out.append(s);
    make_ascii_lowercase(out);
    return out;
}

fn to_ascii_uppercase(s: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    out.append(s);
    make_ascii_uppercase(out);
    return out;
}

fn reverse_bytes(s: u8[:]) {
    for i in s.len / 2 {
        let b = s[i];
        s[i] = s[s.len - 1 - i];
        s[s.len - 1 - i] = b;
    }
}

// Reverse maximal UTF-8 subparts without replacing malformed bytes.
fn reverse_chars(s: u8[:]) {
    var i = 0;
    while i < s.len {
        let cp, size, valid = decode_utf8(s[i..]);
        reverse_bytes(s[i..i + size]);
        i += size;
    }
    reverse_bytes(s);
}

// Valid non-ASCII UTF-8 is retained (including Unicode controls).
// Invalid bytes use uppercase hex escapes; ASCII space is also escaped.
fn escape_bytes(s: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    let hex = "0123456789ABCDEF";
    var i = 0;
    while i < s.len {
        let cp, size, valid = decode_utf8(s[i..]);
        if valid && size > 1 {
            out.append(s[i..i + size]);
            i += size;
            continue;
        }
        let b = s[i];
        if b >= 0x21 && b <= 0x7E && b != '\\' { out.push(b); }
        else if b == 0 { out.append("\\0"); }
        else if b == '\n' { out.append("\\n"); }
        else if b == '\r' { out.append("\\r"); }
        else if b == '\t' { out.append("\\t"); }
        else if b == '\\' { out.append("\\\\"); }
        else { out.append("\\x"); out.push(hex[b >> 4]); out.push(hex[b & 15]); }
        i += 1;
    }
    return out;
}
