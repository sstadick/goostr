use bstr::{decode_last_utf8, decode_utf8, ByteSlice, ByteVec};
use std::fmt::Write;
use std::io::{self, BufRead, BufWriter, Write as IoWrite};

fn hex(out: &mut String, bytes: &[u8]) {
    out.push('[');
    for b in bytes {
        write!(out, "{b:02x}").unwrap();
    }
    out.push(']');
}

fn pos(p: Option<usize>) -> i64 {
    p.map_or(-1, |n| n as i64)
}

fn snapshot(s: &[u8], needle: &[u8], n: usize) -> String {
    let mut out = String::new();
    let (cp, size) = decode_utf8(s);
    let (rcp, rsize) = decode_last_utf8(s);
    let (end, error) = match s.to_str() {
        Ok(_) => (s.len(), 0),
        Err(e) => (e.valid_up_to(), e.error_len().map_or(-1, |n| n as i64)),
    };
    write!(
        out,
        "{},{},{},{},{},{},{},{}|",
        cp.unwrap_or('\u{FFFD}') as u32,
        size,
        cp.is_some(),
        rcp.unwrap_or('\u{FFFD}') as u32,
        rsize,
        rcp.is_some(),
        end,
        error
    )
    .unwrap();
    hex(&mut out, s.to_str_lossy().as_bytes());
    hex(&mut out, s.escape_bytes().to_string().as_bytes());
    hex(&mut out, &Vec::unescape_bytes(s.escape_bytes().to_string()));
    hex(&mut out, &Vec::unescape_bytes(s.to_str_lossy()));
    let (ch, size) = decode_utf8(needle);
    let scalar = if size == 0 {
        '\0'
    } else {
        ch.unwrap_or('\u{FFFD}')
    };
    write!(
        out,
        "{},{}|",
        pos(s.find_char(scalar)),
        pos(s.rfind_char(scalar))
    )
    .unwrap();
    hex(&mut out, s.trim());
    hex(&mut out, s.trim_start());
    hex(&mut out, s.trim_end());
    hex(&mut out, &ByteSlice::to_ascii_lowercase(s));
    hex(&mut out, &ByteSlice::to_ascii_uppercase(s));
    let mut reversed = s.to_vec();
    reversed.reverse_chars();
    hex(&mut out, &reversed);
    out.push('|');
    for (a, b, cp) in s.char_indices() {
        write!(out, "{a},{b},{};", cp as u32).unwrap();
    }
    out.push('|');
    for chunk in ByteSlice::utf8_chunks(s) {
        hex(&mut out, chunk.valid().as_bytes());
        hex(&mut out, chunk.invalid());
    }
    out.push('|');
    for p in s.fields() {
        hex(&mut out, p);
    }
    out.push('|');
    for p in ByteSlice::lines(s) {
        hex(&mut out, p);
    }
    out.push('|');
    for p in s.lines_with_terminator() {
        hex(&mut out, p);
    }
    write!(
        out,
        "|{},{},{},{},{},{}|",
        pos(s.find(needle)),
        pos(s.rfind(needle)),
        pos(s.find_byteset(needle)),
        pos(s.rfind_byteset(needle)),
        pos(s.find_not_byteset(needle)),
        pos(s.rfind_not_byteset(needle))
    )
    .unwrap();
    for i in s.find_iter(needle) {
        write!(out, "{i},").unwrap();
    }
    out.push('|');
    for i in s.rfind_iter(needle) {
        write!(out, "{i},").unwrap();
    }
    out.push('|');
    for p in s.split_str(needle) {
        hex(&mut out, p);
    }
    out.push('|');
    for p in s.rsplit_str(needle) {
        hex(&mut out, p);
    }
    out.push('|');
    for p in s.splitn_str(n, needle) {
        hex(&mut out, p);
    }
    out.push('|');
    for p in s.rsplitn_str(n, needle) {
        hex(&mut out, p);
    }
    out.push('|');
    hex(&mut out, &s.replace(needle, b"\xFF!"));
    hex(&mut out, &s.replacen(needle, b"\xFF!", n));
    out
}

fn unhex(s: &str) -> Vec<u8> {
    assert_eq!(s.len() % 2, 0);
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
        .collect()
}

fn main() {
    let mut out = BufWriter::new(io::stdout().lock());
    for line in io::stdin().lock().lines() {
        let line = line.unwrap();
        let parts: Vec<_> = line.split('|').collect();
        assert_eq!(parts.len(), 3);
        writeln!(
            out,
            "{}",
            snapshot(
                &unhex(parts[0]),
                &unhex(parts[1]),
                parts[2].parse().unwrap()
            )
        )
        .unwrap();
    }
}
