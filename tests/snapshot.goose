// Differential-test driver. Input: hex haystack|hex needle|split limit.
import goostr from "..";
import goosimd from "github.com/sstadick/goosimd@a619a2e1d6c194be4555b01beb63ef2042131ad3";
import os;

fn unhex(s: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    assert(s.len % 2 == 0);
    var i = 0;
    while i < s.len {
        let value, ok = parse_int(s[i..i + 2], 16);
        assert(ok);
        out.push(value as u8);
        i += 2;
    }
    return out;
}

fn hex(out: u8[>..]&, s: const u8[:]) {
    let digits = "0123456789abcdef";
    out.push('[');
    for b in s { out.push(digits[b >> 4]); out.push(digits[b & 15]); }
    out.push(']');
}

fn snapshot(s: const u8[:], needle: const u8[:], n: i64) {
    var out: u8[>..] = [];
    let cp, size, valid = goostr::decode_utf8(s);
    let rcp, rsize, rvalid = goostr::decode_last_utf8(s);
    let end, error = goostr::validate_utf8(s);
    format(out, cp, ",", size, ",", valid, ",", rcp, ",", rsize, ",", rvalid, ",", end, ",", error, "|");
    hex(out, goostr::to_str_lossy(s));
    hex(out, goostr::escape_bytes(s));
    hex(out, goostr::trim(s));
    hex(out, goostr::trim_start(s));
    hex(out, goostr::trim_end(s));
    hex(out, goostr::to_ascii_lowercase(s));
    hex(out, goostr::to_ascii_uppercase(s));
    var rev: u8[>..] = [];
    rev.append(s);
    goostr::reverse_chars(rev);
    hex(out, rev);
    out.push('|');
    goostr::char_indices(s) { a, b, cp => format(out, a, ",", b, ",", cp, ";"); }
    out.push('|');
    goostr::utf8_chunks(s) { good, bad => hex(out, good); hex(out, bad); }
    out.push('|');
    goostr::fields(s) { hex(out, it); }
    out.push('|');
    goostr::lines(s) { hex(out, it); }
    out.push('|');
    goostr::lines_with_terminator(s) { hex(out, it); }
    format(out, "|", goostr::find(s, needle), ",", goostr::rfind(s, needle), ",",
        goostr::find_byteset(s, needle), ",", goostr::rfind_byteset(s, needle), ",",
        goostr::find_not_byteset(s, needle), ",", goostr::rfind_not_byteset(s, needle), "|");
    goostr::find_iter(s, needle) { format(out, it, ","); }
    out.push('|');
    goostr::rfind_iter(s, needle) { format(out, it, ","); }
    out.push('|');
    goostr::split_str(s, needle) { hex(out, it); }
    out.push('|');
    goostr::rsplit_str(s, needle) { hex(out, it); }
    out.push('|');
    goostr::splitn_str(s, needle, n) { hex(out, it); }
    out.push('|');
    goostr::rsplitn_str(s, needle, n) { hex(out, it); }
    out.push('|');
    hex(out, goostr::replace(s, needle, "\xFF!"));
    hex(out, goostr::replacen(s, needle, "\xFF!", n));
    print(out);
}

fn main() {
    while true {
        var line: u8[>..] = [];
        if !read_line(line) { break; }
        let fields = split(line, '|');
        assert(fields.len == 3);
        let s = unhex(fields[0]);
        let needle = unhex(fields[1]);
        let n, ok = parse_int(fields[2]);
        assert(ok);
        snapshot(s, needle, n);
    }
}
