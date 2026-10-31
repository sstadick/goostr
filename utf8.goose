namespace goostr;

import std;

// Decode one Unicode scalar, returning (codepoint, consumed bytes, valid).
// Invalid input yields U+FFFD and consumes one maximal subpart. Empty input
// yields (U+FFFD, 0, false). No valid result is a surrogate or above U+10FFFF.
//
// ```goose
// let cp, size, valid = goostr::decode_utf8("é!");
// assert(cp == 0xE9 && size == 2 && valid);
// ```
fn decode_utf8(s: const u8[:]) -> i64, i64, bool {
    if s.len == 0 { return 0xFFFD, 0, false; }
    let lead = s[0] as i64;
    if lead < 0x80 { return lead, 1, true; }
    if lead < 0xC2 || lead > 0xF4 { return 0xFFFD, 1, false; }
    let width = if lead < 0xE0 { 2 } else if lead < 0xF0 { 3 } else { 4 };
    var cp = lead & (0x7F >> width);
    for i in 1..width {
        if i == s.len { return 0xFFFD, i, false; }
        let b = s[i] as i64;
        if b < 0x80 || b > 0xBF { return 0xFFFD, i, false; }
        if i == 1 && ((lead == 0xE0 && b < 0xA0) || (lead == 0xED && b > 0x9F)
                  || (lead == 0xF0 && b < 0x90) || (lead == 0xF4 && b > 0x8F)) {
            return 0xFFFD, 1, false;
        }
        cp = (cp << 6) | (b & 0x3F);
    }
    return cp, width, true;
}

// Decode the final Unicode scalar, returning (codepoint, consumed bytes,
// valid). Invalid input yields U+FFFD for the final malformed subpart;
// empty input yields (U+FFFD, 0, false).
//
// ```goose
// let cp, size, valid = goostr::decode_last_utf8("!é");
// assert(cp == 0xE9 && size == 2 && valid);
// ```
fn decode_last_utf8(s: const u8[:]) -> i64, i64, bool {
    if s.len == 0 { return 0xFFFD, 0, false; }
    var start = s.len - 1;
    let limit = max(0, s.len - 4);
    while start > limit && s[start] >= 0x80 && s[start] <= 0xBF { start -= 1; }
    let cp, size, valid = decode_utf8(s[start..]);
    if start + size != s.len { return 0xFFFD, 1, false; }
    return cp, size, valid;
}

// Return (codepoint, consumed bytes) from the start, replacing a malformed
// maximal subpart with U+FFFD. Empty input returns (U+FFFD, 0).
//
// ```goose
// let cp, size = goostr::decode_utf8_lossy("\xE2\x82!");
// assert(cp == 0xFFFD && size == 2);
// ```
fn decode_utf8_lossy(s: const u8[:]) -> i64, i64 {
    let cp, size, valid = decode_utf8(s);
    return cp, size;
}

// Return (codepoint, consumed bytes) from the end, replacing the final
// malformed subpart with U+FFFD. Empty input returns (U+FFFD, 0).
//
// ```goose
// let cp, size = goostr::decode_last_utf8_lossy("!\xE2\x82");
// assert(cp == 0xFFFD && size == 2);
// ```
fn decode_last_utf8_lossy(s: const u8[:]) -> i64, i64 {
    let cp, size, valid = decode_last_utf8(s);
    return cp, size;
}

// Call F(start, end, codepoint) for each decoded scalar or malformed maximal
// subpart, from left to right. Offsets refer to the original bytes; end is
// exclusive. Malformed subparts yield U+FFFD; empty input makes no calls.
//
// ```goose
// var starts: i64[>..] = [];
// goostr::char_indices("aé\xFF") { start, end, cp =>
//     starts.push(start);
//     if cp == 0xE9 { assert(start == 1 && end == 3); }
// }
// assert(starts.len == 3 && starts[2] == 3);
// ```
fn char_indices<F>(s: const u8[:]) {
    var i = 0;
    while i < s.len {
        let cp, size, valid = decode_utf8(s[i..]);
        F(i, i + size, cp);
        i += size;
    }
}

// Call F(codepoint) for each decoded scalar, replacing malformed maximal
// subparts with U+FFFD. Empty input makes no calls.
//
// ```goose
// var points: i64[>..] = [];
// goostr::chars("é\xFF") { cp => points.push(cp); }
// assert(points.len == 2 && points[0] == 0xE9 && points[1] == 0xFFFD);
// ```
fn chars<F>(s: const u8[:]) {
    char_indices(s) { start, end, cp => F(cp); }
}

// Returns (valid_up_to, error_len). error_len is 0 on success, -1 for an
// incomplete trailing sequence, or 1..3 for a malformed subpart.
//
// ```goose
// let end, error = goostr::validate_utf8("ok\xE2\x82");
// assert(end == 2 && error == -1);
// let valid_end, no_error = goostr::validate_utf8("é");
// assert(valid_end == 2 && no_error == 0);
// ```
fn validate_utf8(s: const u8[:]) -> i64, i64 {
    var i = 0;
    while i < s.len {
        let cp, size, valid = decode_utf8(s[i..]);
        if !valid {
            let incomplete = i + size == s.len && s[i] >= 0xC2 && s[i] <= 0xF4;
            return i, if incomplete { -1 } else { size };
        }
        i += size;
    }
    return s.len, 0;
}

// Return whether all bytes form valid UTF-8. Empty input is valid.
//
// ```goose
// assert(goostr::is_utf8("café"));
// assert(!goostr::is_utf8("caf\xFF"));
// ```
fn is_utf8(s: const u8[:]) -> bool {
    let end, error = validate_utf8(s);
    return error == 0;
}

// F(valid_bytes, invalid_bytes). Each invalid piece is one maximal subpart;
// both arguments borrow s. Empty input has no chunks.
//
// ```goose
// var valid_parts: const u8[:][>..] = [];
// var invalid_parts: const u8[:][>..] = [];
// goostr::utf8_chunks("ok\xFFé") { valid, invalid =>
//     valid_parts.push(valid);
//     invalid_parts.push(invalid);
// }
// assert(valid_parts.len == 2 && valid_parts[0] == "ok" && valid_parts[1] == "é");
// assert(invalid_parts[0] == "\xFF" && invalid_parts[1] == "");
// ```
fn utf8_chunks<F>(s: const u8[:]) {
    var start = 0;
    var i = 0;
    while i < s.len {
        let cp, size, valid = decode_utf8(s[i..]);
        if !valid { F(s[start..i], s[i..i + size]); start = i + size; }
        i += size;
    }
    if start < s.len { F(s[start..], s[s.len..]); }
}

// Append valid UTF-8 to out, replacing each malformed maximal subpart with
// U+FFFD. Does not clear out; valid bytes are preserved unchanged.
//
// ```goose
// var out: u8[>..] = [];
// out.append("name: ");
// goostr::to_str_lossy_into("goose\xFF", out);
// assert(out == "name: goose�");
// ```
fn to_str_lossy_into(s: const u8[:], out: u8[>..]&) {
    utf8_chunks(s) { valid, invalid =>
        out.append(valid);
        if invalid.len > 0 { out.append("�"); }
    }
}

// Return an owned UTF-8 copy, replacing each malformed maximal subpart with
// U+FFFD. Valid input is copied unchanged.
//
// ```goose
// assert(goostr::to_str_lossy("a\xE2\x82!é") == "a�!é");
// ```
fn to_str_lossy(s: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    to_str_lossy_into(s, out);
    return out;
}

// Unicode White_Space, not ASCII-only whitespace or grapheme segmentation.
//
// ```goose
// assert(goostr::is_whitespace(0xA0)); // Non-breaking space.
// assert(!goostr::is_whitespace(0x200B)); // Zero-width space is not White_Space.
// ```
fn is_whitespace(cp: i64) -> bool {
    return (cp >= 0x09 && cp <= 0x0D) || cp == 0x20 || cp == 0x85 || cp == 0xA0
        || cp == 0x1680 || (cp >= 0x2000 && cp <= 0x200A) || cp == 0x2028
        || cp == 0x2029 || cp == 0x202F || cp == 0x205F || cp == 0x3000;
}

// Return a view borrowing s with leading codepoints satisfying P(cp)
// removed. Predicates see U+FFFD for malformed maximal subparts.
//
// ```goose
// let name = goostr::trim_start_with("--name--") { cp => cp == '-' };
// assert(name == "name--");
// ```
fn trim_start_with<P>(s: const u8[:]) -> const u8[:] {
    var start = 0;
    while start < s.len {
        let cp, size, valid = decode_utf8(s[start..]);
        if !P(cp) { break; }
        start += size;
    }
    return s[start..];
}

// Return a view borrowing s with trailing codepoints satisfying P(cp)
// removed. Predicates see U+FFFD for malformed maximal subparts.
//
// ```goose
// let name = goostr::trim_end_with("--name--") { cp => cp == '-' };
// assert(name == "--name");
// ```
fn trim_end_with<P>(s: const u8[:]) -> const u8[:] {
    var end = s.len;
    while end > 0 {
        let cp, size, valid = decode_last_utf8(s[..end]);
        if !P(cp) { break; }
        end -= size;
    }
    return s[..end];
}

// Return a view borrowing s with codepoints satisfying P(cp) removed from
// both ends. Predicates see U+FFFD for malformed maximal subparts.
//
// ```goose
// let name = goostr::trim_with("--first-last--") { cp => cp == '-' };
// assert(name == "first-last");
// ```
fn trim_with<P>(s: const u8[:]) -> const u8[:] {
    return trim_end_with(trim_start_with(s, P), P);
}

// Return a view borrowing s without leading Unicode White_Space.
//
// ```goose
// assert(goostr::trim_start("\xC2\xA0name \t") == "name \t"); // Leading NBSP.
// ```
fn trim_start(s: const u8[:]) -> const u8[:] { trim_start_with(s, is_whitespace) }
// Return a view borrowing s without trailing Unicode White_Space.
//
// ```goose
// assert(goostr::trim_end("\t name\xC2\xA0") == "\t name"); // Trailing NBSP.
// ```
fn trim_end(s: const u8[:]) -> const u8[:] { trim_end_with(s, is_whitespace) }
// Return a view borrowing s without Unicode White_Space at either end.
//
// ```goose
// assert(goostr::trim("\xC2\xA0 first last \t") == "first last");
// ```
fn trim(s: const u8[:]) -> const u8[:] { trim_with(s, is_whitespace) }

// Call F(field) for nonempty borrowed fields separated by codepoints for
// which P(cp) is true. Predicates see U+FFFD for malformed maximal subparts;
// the field views retain their original bytes. Empty input makes no calls.
//
// ```goose
// fn comma(cp: i64) -> bool { cp == ',' }
// var parts: const u8[:][>..] = [];
// goostr::fields_with(",one,,two,", comma) { part => parts.push(part); }
// assert(parts.len == 2 && parts[0] == "one" && parts[1] == "two");
// ```
fn fields_with<P, F>(s: const u8[:]) {
    var start = 0;
    char_indices(s) { a, b, cp =>
        if P(cp) {
            if start < a { F(s[start..a]); }
            start = b;
        }
    }
    if start < s.len { F(s[start..]); }
}

// Call F(field) for nonempty borrowed fields separated by Unicode
// White_Space. Empty or entirely whitespace input makes no calls.
//
// ```goose
// var words: const u8[:][>..] = [];
// goostr::fields(" one\xC2\xA0two\t ") { word => words.push(word); }
// assert(words.len == 2 && words[0] == "one" && words[1] == "two");
// ```
fn fields<F>(s: const u8[:]) { fields_with(s, is_whitespace, F); }
