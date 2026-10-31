// Native Goose byte strings, with bstr-compatible byte and UTF-8 semantics.
namespace goostr;

import std;
import .utf8;
import .search;

const UNLIMITED: i64 = 0x7FFFFFFFFFFFFFFF;

// Return whether needle occurs in s. An empty needle always matches.
//
// ```goose
// assert(goostr::contains_str("a\0b", "\0"));
// assert(!goostr::contains_str("goose", "duck"));
// ```
fn contains_str(s: const u8[:], needle: const u8[:]) -> bool { find(s, needle) >= 0 }
// Return whether s begins with prefix. An empty prefix always matches.
//
// ```goose
// assert(goostr::starts_with_str("goose", "goo"));
// assert(!goostr::starts_with_str("goose", "ose"));
// ```
fn starts_with_str(s: const u8[:], prefix: const u8[:]) -> bool { ::starts_with(s, prefix) }
// Return whether s ends with suffix. An empty suffix always matches.
//
// ```goose
// assert(goostr::ends_with_str("notes.txt", ".txt"));
// assert(!goostr::ends_with_str("notes.txt", ".csv"));
// ```
fn ends_with_str(s: const u8[:], suffix: const u8[:]) -> bool { ::ends_with(s, suffix) }

// Return the first byte offset matching byte, or -1 if absent.
//
// ```goose
// assert(goostr::find_byte("goose", 'o') == 1);
// assert(goostr::find_byte("goose", 'x') == -1);
// ```
fn find_byte(s: const u8[:], byte: u8) -> i64 {
    return byte_search(s, byte, false);
}

// Return the last byte offset matching byte, or -1 if absent.
//
// ```goose
// assert(goostr::rfind_byte("goose", 'o') == 2);
// assert(goostr::rfind_byte("goose", 'x') == -1);
// ```
fn rfind_byte(s: const u8[:], byte: u8) -> i64 {
    return byte_search(s, byte, true);
}

// Return the first offset of any byte in set, or -1 if absent.
// Duplicates in set have no effect; an empty set never matches.
//
// ```goose
// assert(goostr::find_byteset("abc,def;ghi", ",;") == 3);
// assert(goostr::find_byteset("abc", "") == -1);
// ```
fn find_byteset(s: const u8[:], set: const u8[:]) -> i64 {
    return byteset_search(s, set, false, false);
}

// Return the first offset of a byte outside set, or -1 if none exists.
// An empty set matches every byte; empty input still returns -1.
//
// ```goose
// assert(goostr::find_not_byteset("  \tname", " \t") == 3);
// assert(goostr::find_not_byteset("  ", " ") == -1);
// ```
fn find_not_byteset(s: const u8[:], set: const u8[:]) -> i64 {
    return byteset_search(s, set, false, true);
}

// Return the last offset of any byte in set, or -1 if absent.
// Duplicates in set have no effect; an empty set never matches.
//
// ```goose
// assert(goostr::rfind_byteset("abc,def;ghi", ",;") == 7);
// assert(goostr::rfind_byteset("abc", "") == -1);
// ```
fn rfind_byteset(s: const u8[:], set: const u8[:]) -> i64 {
    return byteset_search(s, set, true, false);
}

// Return the last offset of a byte outside set, or -1 if none exists.
// An empty set matches every byte; empty input still returns -1.
//
// ```goose
// assert(goostr::rfind_not_byteset("name \t ", " \t") == 3);
// assert(goostr::rfind_not_byteset("", "") == -1);
// ```
fn rfind_not_byteset(s: const u8[:], set: const u8[:]) -> i64 {
    return byteset_search(s, set, true, true);
}

// Call F(byte_offset) for non-overlapping matches, from left to right.
// Empty needles match every byte boundary, including both ends and positions
// inside a UTF-8 codepoint.
//
// ```goose
// var offsets: i64[>..] = [];
// goostr::find_iter("ababa", "aba") { at => offsets.push(at); }
// assert(offsets.len == 1 && offsets[0] == 0); // Matches do not overlap.
// ```
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

// Call F(byte_offset) for non-overlapping matches, from right to left.
// Empty needles match every byte boundary, including both ends and positions
// inside a UTF-8 codepoint. Reverse matches may differ from forward matches.
//
// ```goose
// var offsets: i64[>..] = [];
// goostr::rfind_iter("ababa", "aba") { at => offsets.push(at); }
// assert(offsets.len == 1 && offsets[0] == 2);
// ```
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

// Call F(piece) for at most n pieces split on needle, from left to right.
// Views borrow s and omit separators; the last piece contains the remainder.
// Zero yields no pieces; negative n asserts. Empty needles split at every
// byte boundary, including both ends. Empty pieces are retained.
//
// ```goose
// var parts: const u8[:][>..] = [];
// goostr::splitn_str("a:b:c", ":", 2) { part => parts.push(part); }
// assert(parts.len == 2 && parts[0] == "a" && parts[1] == "b:c");
// ```
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

// Call F(piece) for all pieces split on non-overlapping needle matches,
// from left to right. Views borrow s and omit separators; empty pieces are
// retained. Empty needles split at every byte boundary, including both ends.
//
// ```goose
// var parts: const u8[:][>..] = [];
// goostr::split_str("a::b::", "::") { part => parts.push(part); }
// assert(parts.len == 3 && parts[1] == "b" && parts[2] == "");
// ```
fn split_str<F>(s: const u8[:], needle: const u8[:]) {
    splitn_str(s, needle, UNLIMITED, F);
}

// Call F(piece) for at most n pieces split on needle, from right to left.
// Views borrow s and omit separators; the last piece contains the remainder.
// Zero yields no pieces; negative n asserts. Empty needles split at every
// byte boundary, including both ends. Empty pieces are retained.
//
// ```goose
// var parts: const u8[:][>..] = [];
// goostr::rsplitn_str("a:b:c", ":", 2) { part => parts.push(part); }
// assert(parts.len == 2 && parts[0] == "c" && parts[1] == "a:b");
// ```
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

// Call F(piece) for all pieces split on non-overlapping needle matches,
// from right to left. Views borrow s and omit separators; empty pieces are
// retained. Empty needles split at every byte boundary, including both ends.
//
// ```goose
// var parts: const u8[:][>..] = [];
// goostr::rsplit_str("a:b:c", ":") { part => parts.push(part); }
// assert(parts.len == 3 && parts[0] == "c" && parts[2] == "a");
// ```
fn rsplit_str<F>(s: const u8[:], needle: const u8[:]) {
    rsplitn_str(s, needle, UNLIMITED, F);
}

// Split at the first needle, returning (left, right, found). Both views
// borrow s and omit the separator; both are empty if absent. An empty needle
// succeeds with an empty left view and all of s on the right.
//
// ```goose
// let key, value, found = goostr::split_once_str("name=goose=bird", "=");
// assert(found && key == "name" && value == "goose=bird");
// ```
fn split_once_str(s: const u8[:], needle: const u8[:]) -> const u8[:], const u8[:], bool {
    let at = find(s, needle);
    if at < 0 { return s[..0], s[..0], false; }
    return s[..at], s[at + needle.len..], true;
}

// Split at the last needle, returning (left, right, found). Both views
// borrow s and omit the separator; both are empty if absent. An empty needle
// succeeds with all of s on the left and an empty right view.
//
// ```goose
// let base, extension, found = goostr::rsplit_once_str("archive.tar.gz", ".");
// assert(found && base == "archive.tar" && extension == "gz");
// ```
fn rsplit_once_str(s: const u8[:], needle: const u8[:]) -> const u8[:], const u8[:], bool {
    let at = rfind(s, needle);
    if at < 0 { return s[..0], s[..0], false; }
    return s[..at], s[at + needle.len..], true;
}

// Append s with at most n non-overlapping needle matches replaced, scanning
// left to right. Does not clear out. Zero appends s unchanged; negative n
// asserts. An empty needle inserts at byte boundaries, including both ends.
//
// ```goose
// var out: u8[>..] = [];
// out.append("result: ");
// goostr::replacen_into("a-a-a", "-", "/", 1, out);
// assert(out == "result: a/a-a");
// ```
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

// Append s with all non-overlapping needle matches replaced, scanning left
// to right. Does not clear out. An empty needle inserts replacement at every
// byte boundary, including both ends.
//
// ```goose
// var out: u8[>..] = [];
// out.append("result: ");
// goostr::replace_into("a\0b", "\0", "/", out);
// assert(out == "result: a/b");
// ```
fn replace_into(s: const u8[:], needle: const u8[:], replacement: const u8[:], out: u8[>..]&) {
    replacen_into(s, needle, replacement, UNLIMITED, out);
}

// Return an owned copy with at most n non-overlapping matches replaced,
// scanning left to right. Zero returns a copy of s; negative n asserts.
// An empty needle inserts at byte boundaries, including both ends.
//
// ```goose
// assert(goostr::replacen("a-a-a", "-", "/", 1) == "a/a-a");
// assert(goostr::replacen("abc", "b", "X", 0) == "abc");
// ```
fn replacen(s: const u8[:], needle: const u8[:], replacement: const u8[:], n: i64) -> u8[>..] {
    var out: u8[>..] = [];
    replacen_into(s, needle, replacement, n, out);
    return out;
}

// Return an owned copy with all non-overlapping matches replaced, scanning
// left to right. An empty needle inserts at every byte boundary, including
// both ends; otherwise an absent needle returns a copy of s.
//
// ```goose
// assert(goostr::replace("a-a-a", "-", "/") == "a/a/a");
// assert(goostr::replace("ab", "", "-") == "-a-b-");
// ```
fn replace(s: const u8[:], needle: const u8[:], replacement: const u8[:]) -> u8[>..] {
    return replacen(s, needle, replacement, UNLIMITED);
}

// Return an owned concatenation of n copies of s. Zero or empty input gives
// an empty builder; negative n asserts.
//
// ```goose
// assert(goostr::repeatn("ab", 3) == "ababab");
// assert(goostr::repeatn("ab", 0) == "");
// ```
fn repeatn(s: const u8[:], n: i64) -> u8[>..] {
    assert(n >= 0);
    var out: u8[>..] = [];
    if s.len == 0 { return out; }
    for i in n { out.append(s); }
    return out;
}

// Call F(line) for borrowed lines, retaining their LF or CRLF terminators.
// A final unterminated line is included. Empty input produces no lines, and
// a final terminator does not produce an additional empty line.
//
// ```goose
// var rows: const u8[:][>..] = [];
// goostr::lines_with_terminator("a\r\nb\n") { row => rows.push(row); }
// assert(rows.len == 2 && rows[0] == "a\r\n" && rows[1] == "b\n");
// ```
fn lines_with_terminator<F>(s: const u8[:]) {
    var start = 0;
    for b, i in s {
        if b == '\n' { F(s[start..i + 1]); start = i + 1; }
    }
    if start < s.len { F(s[start..]); }
}

// Call F(line) for borrowed lines with LF or CRLF terminators removed.
// A bare CR is data. Empty input produces no lines; a final terminator does
// not produce an additional empty line.
//
// ```goose
// var rows: const u8[:][>..] = [];
// goostr::lines("a\r\nb\n") { row => rows.push(row); }
// assert(rows.len == 2 && rows[0] == "a" && rows[1] == "b");
// ```
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

// Return the first offset of a byte >= 128, or -1 if every byte is ASCII.
//
// ```goose
// assert(goostr::find_non_ascii_byte("café") == 3);
// assert(goostr::find_non_ascii_byte("goose") == -1);
// ```
fn find_non_ascii_byte(s: const u8[:]) -> i64 {
    for b, i in s { if b >= 128 { return i; } }
    return -1;
}

// Return whether every byte is below 128. Empty input is ASCII.
//
// ```goose
// assert(goostr::is_ascii("a\0b"));
// assert(!goostr::is_ascii("café"));
// ```
fn is_ascii(s: const u8[:]) -> bool { find_non_ascii_byte(s) < 0 }

// Convert ASCII A..Z to a..z in place. All other bytes are unchanged.
//
// ```goose
// var bytes: u8[>..] = [];
// bytes.append("GOOSE\xFF");
// goostr::make_ascii_lowercase(bytes);
// assert(bytes == "goose\xFF");
// ```
fn make_ascii_lowercase(s: u8[:]) {
    for &c in s {
        let mask: u8 = if c >= 'A' && c <= 'Z' { 32 } else { 0 };
        c |= mask;
    }
}

// Convert ASCII a..z to A..Z in place. All other bytes are unchanged.
//
// ```goose
// var bytes: u8[>..] = [];
// bytes.append("goose\xFF");
// goostr::make_ascii_uppercase(bytes);
// assert(bytes == "GOOSE\xFF");
// ```
fn make_ascii_uppercase(s: u8[:]) {
    for &c in s {
        let mask: u8 = if c >= 'a' && c <= 'z' { 32 } else { 0 };
        c ^= mask;
    }
}

// Return an owned copy with ASCII A..Z converted to a..z. Non-ASCII bytes
// are unchanged; this is not Unicode case conversion.
//
// ```goose
// assert(goostr::to_ascii_lowercase("CAFÉ") == "cafÉ");
// ```
fn to_ascii_lowercase(s: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    out.append(s);
    make_ascii_lowercase(out);
    return out;
}

// Return an owned copy with ASCII a..z converted to A..Z. Non-ASCII bytes
// are unchanged; this is not Unicode case conversion.
//
// ```goose
// assert(goostr::to_ascii_uppercase("café") == "CAFé");
// ```
fn to_ascii_uppercase(s: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    out.append(s);
    make_ascii_uppercase(out);
    return out;
}

// Reverse bytes in place, without interpreting UTF-8.
//
// ```goose
// var bytes: u8[>..] = [];
// bytes.append("a\0bc");
// goostr::reverse_bytes(bytes);
// assert(bytes == "cb\0a");
// ```
fn reverse_bytes(s: u8[:]) {
    for i in s.len / 2 {
        let b = s[i];
        s[i] = s[s.len - 1 - i];
        s[s.len - 1 - i] = b;
    }
}

// Reverse decoded characters and maximal malformed UTF-8 subparts in place,
// preserving the bytes within each. Does not reverse grapheme clusters.
//
// ```goose
// var bytes: u8[>..] = [];
// bytes.append("aé\xFF");
// goostr::reverse_chars(bytes);
// assert(bytes == "\xFFéa");
// ```
fn reverse_chars(s: u8[:]) {
    var i = 0;
    while i < s.len {
        let cp, size, valid = decode_utf8(s[i..]);
        reverse_bytes(s[i..i + size]);
        i += size;
    }
    reverse_bytes(s);
}

// Return an owned escaped representation. Valid non-ASCII UTF-8 is retained
// (including Unicode controls). Backslashes, NUL, LF, CR and TAB are escaped.
// Invalid bytes use uppercase hex escapes; ASCII space is also escaped.
//
// ```goose
// assert(goostr::escape_bytes("a \xFF\n") == "a\\x20\\xFF\\n");
// assert(goostr::escape_bytes("café") == "café");
// ```
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
