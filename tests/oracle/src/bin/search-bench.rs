use bstr::ByteSlice;
use std::{env, fs, time::Instant};

#[repr(C)]
struct ByteSliceAbi { data: *const u8, len: i64 }
extern "C" {
    fn goostr_bench_opaque(s: ByteSliceAbi) -> i64;
    fn goostr_bench_setup() -> i64;
}

fn opaque(s: &[u8]) -> &[u8] {
    // The separately compiled benchmark barrier returns its input's length.
    let len = unsafe { goostr_bench_opaque(ByteSliceAbi { data: s.as_ptr(), len: s.len() as i64 }) };
    &s[..len as usize]
}

// Match Goose and memchr's one-shot, non-overlapping count model.
fn count_matches(s: &[u8], needle: &[u8]) -> u64 {
    let mut count = 0;
    let mut start = 0;
    while start <= s.len() {
        let Some(at) = s[start..].find(needle) else { break };
        count += 1;
        start += at + needle.len().max(1);
    }
    count
}

fn count_reverse(s: &[u8], needle: &[u8]) -> u64 {
    let mut count = 0;
    let mut end = s.len();
    loop {
        let Some(at) = s[..end].rfind(needle) else { break };
        count += 1;
        end = if needle.is_empty() {
            let Some(end) = at.checked_sub(1) else { break };
            end
        } else { at };
    }
    count
}

fn record_prefixes(s: &[u8]) -> u64 {
    let mut checksum = 0;
    let mut start = 0;
    while start < s.len() {
        let end = s[start..].find_byte(b'\n').map_or(s.len(), |at| start + at);
        checksum += s[start..end].find_byte(b'|').map_or(0, |at| at as u64 + 1);
        start = end + 1;
    }
    checksum
}

fn main() {
    assert_eq!(unsafe { goostr_bench_setup() }, 0);
    let args: Vec<_> = env::args().collect();
    let haystack = fs::read(&args[1]).unwrap();
    let needle = fs::read(&args[2]).unwrap();
    let iterations: u64 = args[4].parse().unwrap();
    let mut checksum = 0u64;
    let mut elapsed = 0;
    let forward = bstr::Finder::new(&needle);
    let reverse = bstr::FinderReverse::new(&needle);
    // Match Goose: discard a full warm-up pass before recording a sample.
    for _ in 0..2 {
        checksum = 0;
        let start = Instant::now();
        match args[3].as_str() {
            "find" => for _ in 0..iterations {
                checksum += opaque(&haystack).find(opaque(&needle)).map_or(0, |p| p as u64 + 1);
            },
            "count" => for _ in 0..iterations {
                checksum += count_matches(opaque(&haystack), opaque(&needle)) + 1;
            },
            "rcount" => for _ in 0..iterations {
                checksum += count_reverse(opaque(&haystack), opaque(&needle)) + 1;
            },
            "records" => for _ in 0..iterations {
                checksum += record_prefixes(opaque(&haystack)) + 1;
            },
            "prepared-find" => for _ in 0..iterations {
                checksum += forward.find(opaque(&haystack)).map_or(0, |p| p as u64 + 1);
            },
            "prepared-rfind" => for _ in 0..iterations {
                checksum += reverse.rfind(opaque(&haystack)).map_or(0, |p| p as u64 + 1);
            },
            "rfind" => for _ in 0..iterations {
                checksum += opaque(&haystack).rfind(opaque(&needle)).map_or(0, |p| p as u64 + 1);
            },
            "find-set" => for _ in 0..iterations {
                checksum += opaque(&haystack).find_byteset(opaque(&needle)).map_or(0, |p| p as u64 + 1);
            },
            "rfind-set" => for _ in 0..iterations {
                checksum += opaque(&haystack).rfind_byteset(opaque(&needle)).map_or(0, |p| p as u64 + 1);
            },
            "find-not-set" => for _ in 0..iterations {
                checksum += opaque(&haystack).find_not_byteset(opaque(&needle)).map_or(0, |p| p as u64 + 1);
            },
            "rfind-not-set" => for _ in 0..iterations {
                checksum += opaque(&haystack).rfind_not_byteset(opaque(&needle)).map_or(0, |p| p as u64 + 1);
            },
            _ => panic!("unknown mode"),
        }
        elapsed = start.elapsed().as_nanos();
    }
    println!("{} {}", elapsed, checksum);
}
