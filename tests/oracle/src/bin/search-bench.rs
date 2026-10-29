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
