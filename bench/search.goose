import goostr from "..";
import goosimd from "github.com/sstadick/goosimd@main";
import os;

// External, opaque to the optimizer in both benchmark programs. Prevents
// repeated searches over invariant input from being hoisted out of the loop.
extern "goostr_bench_opaque" fn opaque_len(s: const u8[:]) -> i64;
extern "goostr_bench_setup" fn setup() -> i64;
fn opaque(s: const u8[:]) -> const u8[:] { s[..opaque_len(s)] }

fn main() {
    assert(setup() == 0);
    let argv = args();
    assert(argv.len == 5);
    var haystack: u8[>..] = [];
    var needle: u8[>..] = [];
    assert(read_file(argv[1], haystack));
    assert(read_file(argv[2], needle));
    let iterations, ok = parse_int(argv[4]);
    assert(ok && iterations > 0);
    var checksum = 0;
    var elapsed = 0;
    let forward = goostr::finder(needle);
    let reverse = goostr::finder_reverse(needle);
    // Discard one full pass to warm code/data and reduce CPU ramp-up noise.
    for pass in 2 {
        checksum = 0;
        let start = clock_ns();
        if argv[3] == "find" {
            for i in iterations { checksum += goostr::find(opaque(haystack), opaque(needle)) + 1; }
        } else if argv[3] == "prepared-find" {
            for i in iterations { checksum += goostr::find(forward, opaque(haystack)) + 1; }
        } else if argv[3] == "prepared-rfind" {
            for i in iterations { checksum += goostr::rfind(reverse, opaque(haystack)) + 1; }
        } else if argv[3] == "find-set" {
            for i in iterations { checksum += goostr::find_byteset(opaque(haystack), opaque(needle)) + 1; }
        } else if argv[3] == "rfind-set" {
            for i in iterations { checksum += goostr::rfind_byteset(opaque(haystack), opaque(needle)) + 1; }
        } else if argv[3] == "find-not-set" {
            for i in iterations { checksum += goostr::find_not_byteset(opaque(haystack), opaque(needle)) + 1; }
        } else if argv[3] == "rfind-not-set" {
            for i in iterations { checksum += goostr::rfind_not_byteset(opaque(haystack), opaque(needle)) + 1; }
        } else {
            assert(argv[3] == "rfind");
            for i in iterations { checksum += goostr::rfind(opaque(haystack), opaque(needle)) + 1; }
        }
        elapsed = clock_ns() - start;
    }
    print(elapsed, " ", checksum);
}
