import goostr from "..";
import goosimd from "github.com/sstadick/goosimd@d030164f014e366a05bcd45f508e699edec10b89";

// Slice elements compare by identity in this Goose release. Check bytes.
fn expect_parts(actual: const u8[:][:], expected: const u8[:][:]) {
    assert(actual.len == expected.len);
    for part, i in actual { assert(part == expected[i]); }
}

fn search() {
    assert(goostr::find("ab\0aba\xFF", "aba") == 3);
    assert(goostr::rfind("ababa", "aba") == 2);
    assert(goostr::find("ab", "abc") == -1);
    assert(goostr::rfind("ab", "abc") == -1);
    assert(goostr::find("abc", "") == 0);
    assert(goostr::rfind("abc", "") == 3);
    assert(goostr::find("", "") == 0);
    assert(goostr::contains_str("a\xFFb", "\xFF"));
    assert(!goostr::contains_str("abc", "d"));
    assert(goostr::starts_with_str("abc", "ab"));
    assert(!goostr::starts_with_str("ab", "abc"));
    assert(goostr::ends_with_str("abc", "bc"));
    assert(!goostr::ends_with_str("abc", "ab"));
    assert(goostr::find_byte("\0x\0", 0) == 0);
    assert(goostr::rfind_byte("\0x\0", 0) == 2);
    assert(goostr::find_byte("", 0) == -1);
    assert(goostr::rfind_byte("abc", 0) == -1);
    assert(goostr::find_byteset("abc\xFFx", "x\xFF") == 3);
    assert(goostr::rfind_byteset("abc\xFFx", "x\xFF") == 4);
    assert(goostr::find_not_byteset("aaab", "a") == 3);
    assert(goostr::rfind_not_byteset("baaa", "a") == 0);
    assert(goostr::find_byteset("abc", "") == -1);
    assert(goostr::find_not_byteset("abc", "") == 0);
    assert(goostr::rfind_not_byteset("abc", "") == 2);
    assert(goostr::rfind_byteset("", "a") == -1);
    assert(goostr::find_not_byteset("aaa", "a") == -1);
    var forward: i64[>..] = [];
    goostr::find_iter("ababa", "aba") { forward.push(it); }
    assert(forward == [0]);
    var backward: i64[>..] = [];
    goostr::rfind_iter("ababa", "aba") { backward.push(it); }
    assert(backward == [2]);
    var empty: i64[>..] = [];
    goostr::rfind_iter("é", "") { empty.push(it); }
    assert(empty == [2, 1, 0]);
}

fn splitting() {
    var parts: const u8[:][>..] = [];
    goostr::split_str("|a||b|", "|") { parts.push(it); }
    expect_parts(parts, ["", "a", "", "b", ""]);
    var reverse: const u8[:][>..] = [];
    goostr::rsplit_str("ababa", "aba") { reverse.push(it); }
    expect_parts(reverse, ["", "ab"]);
    var bytes: const u8[:][>..] = [];
    goostr::split_str("é", "") { bytes.push(it); }
    expect_parts(bytes, ["", "\xC3", "\xA9", ""]);
    var revbytes: const u8[:][>..] = [];
    goostr::rsplit_str("é", "") { revbytes.push(it); }
    expect_parts(revbytes, ["", "\xA9", "\xC3", ""]);
    var blank: const u8[:][>..] = [];
    goostr::split_str("", "") { blank.push(it); }
    expect_parts(blank, ["", ""]);
    var limited: const u8[:][>..] = [];
    goostr::splitn_str("a:b:c", ":", 2) { limited.push(it); }
    expect_parts(limited, ["a", "b:c"]);
    var revlimited: const u8[:][>..] = [];
    goostr::rsplitn_str("a:b:c", ":", 2) { revlimited.push(it); }
    expect_parts(revlimited, ["c", "a:b"]);
    var n = 0;
    goostr::splitn_str("a:b", ":", 0) { n += 1; }
    goostr::rsplitn_str("a:b", ":", 0) { n += 1; }
    assert(n == 0);
    goostr::splitn_str("a:b", ":", 1) { assert(it == "a:b"); n += 1; }
    assert(n == 1);
    let left, right, found = goostr::split_once_str("a=b=c", "=");
    assert(found && left == "a" && right == "b=c");
    let rl, rr, rf = goostr::rsplit_once_str("a=b=c", "=");
    assert(rf && rl == "a=b" && rr == "c");
    let nl, nr, nf = goostr::split_once_str("abc", "!");
    assert(!nf && nl.len == 0 && nr.len == 0);
    let el, er, ef = goostr::rsplit_once_str("abc", "");
    assert(ef && el == "abc" && er == "");
}

fn replacement() {
    assert(goostr::replace("ababa", "aba", "X") == "Xba");
    assert(goostr::replace("a\0b", "\0", "\xFF") == "a\xFFb");
    assert(goostr::replace("é", "", "-") == "-\xC3-\xA9-");
    assert(goostr::replace("", "", "X") == "X");
    assert(goostr::replace("abc", "b", "") == "ac");
    assert(goostr::replacen("aaa", "a", "bb", 2) == "bbbba");
    assert(goostr::replacen("abc", "", "-", 2) == "-a-bc");
    assert(goostr::replacen("abc", "", "-", 0) == "abc");
    var out: u8[>..] = [];
    out.append("prefix:");
    goostr::replace_into("a:a", ":", "=", out);
    goostr::replacen_into("bab", "b", "!", 1, out);
    assert(out == "prefix:a=a!ab");
    assert(goostr::repeatn("a\xFF", 3) == "a\xFFa\xFFa\xFF");
    assert(goostr::repeatn("abc", 0) == "");
    assert(goostr::repeatn("", 100) == "");
}

fn text() {
    var lines: const u8[:][>..] = [];
    goostr::lines("a\r\n\nb\rc\nlast\r") { lines.push(it); }
    expect_parts(lines, ["a", "", "b\rc", "last\r"]);
    var terminated: const u8[:][>..] = [];
    goostr::lines_with_terminator("a\r\n\nb\n") { terminated.push(it); }
    expect_parts(terminated, ["a\r\n", "\n", "b\n"]);
    var n = 0;
    goostr::lines("") { n += 1; }
    assert(n == 0);
    goostr::lines("\n") { assert(it == ""); n += 1; }
    assert(n == 1);
    assert(goostr::trim("\x0B\x0C \xFF雪　\n") == "\xFF雪");
    assert(goostr::trim("\xFF x \xFF") == "\xFF x \xFF");
    assert(goostr::trim("​x​") == "​x​"); // U+200B is NOT White_Space.
    assert(goostr::trim_start(" x ") == "x ");
    assert(goostr::trim_end(" x　") == " x");
    assert(goostr::trim_with("\xE2\x98x\xFF") { it == 0xFFFD } == "x");
    var fields: const u8[:][>..] = [];
    goostr::fields(" \x0Bα \xFF　beta\r\n") { fields.push(it); }
    expect_parts(fields, ["α", "\xFF", "beta"]);
    var custom: const u8[:][>..] = [];
    fn separator(cp: i64) -> bool { cp == ',' || cp == 0xFFFD }
    goostr::fields_with(",a\xE2\x98b,,", separator) { custom.push(it); }
    expect_parts(custom, ["a", "b"]);
    assert(goostr::is_ascii("a\0\x7F"));
    assert(!goostr::is_ascii("é"));
    assert(goostr::find_non_ascii_byte("ab\xFF") == 2);
    assert(goostr::to_ascii_lowercase("AZ[É\xFF") == "az[É\xFF");
    assert(goostr::to_ascii_uppercase("az{é\xFF") == "AZ{é\xFF");
    var lower: u8[258] = [0; 258];
    var upper: u8[258] = [0; 258];
    for i in 256 { lower[i + 1] = i as u8; upper[i + 1] = i as u8; }
    lower[0] = 'A'; lower[257] = 'Z';
    upper[0] = 'a'; upper[257] = 'z';
    goostr::make_ascii_lowercase(lower[1..257]);
    goostr::make_ascii_uppercase(upper[1..257]);
    for i in 256 {
        assert(lower[i + 1] == (if i >= 65 && i <= 90 { i + 32 } else { i }) as u8);
        assert(upper[i + 1] == (if i >= 97 && i <= 122 { i - 32 } else { i }) as u8);
    }
    goostr::make_ascii_lowercase(lower[1..1]);
    goostr::make_ascii_uppercase(upper[1..1]);
    assert(lower[0] == 'A' && lower[257] == 'Z');
    assert(upper[0] == 'a' && upper[257] == 'z');
    var mutable: u8[>..] = [];
    mutable.append("aZ\xFF");
    goostr::make_ascii_uppercase(mutable);
    assert(mutable == "AZ\xFF");
    goostr::make_ascii_lowercase(mutable);
    assert(mutable == "az\xFF");
    goostr::reverse_bytes(mutable);
    assert(mutable == "\xFFza");
    assert(goostr::escape_bytes(" é\xFF\0\t\r\n\\\"\x7F") == "\\x20é\\xFF\\0\\t\\r\\n\\\\\"\\x7F");
}

fn utf8() {
    assert(goostr::is_utf8("aé雪🦆�"));
    assert(goostr::is_utf8(""));
    assert(!goostr::is_utf8("\xED\xA0\x80"));
    assert(!goostr::is_utf8("\xF4\x90\x80\x80"));
    assert(!goostr::is_utf8("\xC0\x80"));
    let cp, size, valid = goostr::decode_utf8("\xE2\x98!");
    assert(cp == 0xFFFD && size == 2 && !valid);
    let last, lastsize, lastvalid = goostr::decode_last_utf8("a\xE2\x98");
    assert(last == 0xFFFD && lastsize == 2 && !lastvalid);
    let repl, replsize, replvalid = goostr::decode_utf8("�");
    assert(repl == 0xFFFD && replsize == 3 && replvalid);
    let a, b = goostr::decode_utf8_lossy("🦆");
    assert(a == 0x1F986 && b == 4);
    let c, d = goostr::decode_last_utf8_lossy("xé");
    assert(c == 0xE9 && d == 2);
    let end, error = goostr::validate_utf8("ok\xF0\x90\x80");
    assert(end == 2 && error == -1);
    let end2, error2 = goostr::validate_utf8("ok\xF0\x90!");
    assert(end2 == 2 && error2 == 2);
    let end3, error3 = goostr::validate_utf8("\xFF");
    assert(end3 == 0 && error3 == 1);
    assert(goostr::to_str_lossy("a\xE2\x98!\xED\xA0\x80") == "a�!���");
    var out: u8[>..] = [];
    out.append("prefix:");
    goostr::to_str_lossy_into("\xFFé", out);
    assert(out == "prefix:�é");
    var indices: i64[>..] = [];
    goostr::char_indices("aé\xE2\x98!") { start, end, cp =>
        indices.push(start); indices.push(end); indices.push(cp);
    }
    assert(indices == [0, 1, 97, 1, 3, 233, 3, 5, 65533, 5, 6, 33]);
    var points: i64[>..] = [];
    goostr::chars("é\xFF") { points.push(it); }
    assert(points == [233, 65533]);
    var chunks: const u8[:][>..] = [];
    goostr::utf8_chunks("a\xE2\x98!\xFFé") { valid, invalid =>
        chunks.push(valid); chunks.push(invalid);
    }
    expect_parts(chunks, ["a", "\xE2\x98", "!", "\xFF", "é", ""]);
    var reversed: u8[>..] = [];
    reversed.append("a☃\xE2\x98!");
    goostr::reverse_chars(reversed);
    assert(reversed == "!\xE2\x98☃a");
}

// A caller can stop any callback iterator with a non-local return.
fn first_field(s: const u8[:]) -> const u8[:] {
    goostr::fields(s) { return it; }
    return s[..0];
}

fn main() {
    search();
    splitting();
    replacement();
    text();
    utf8();
    assert(first_field(" a b ") == "a");
    print("goostr tests passed");
}
