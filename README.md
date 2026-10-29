# goostr

A native [Goose](https://github.com/aardappel/goose) port of the byte-string
core of Rust's [bstr](https://github.com/BurntSushi/bstr), targeting **bstr
1.13.1 semantics**. Arbitrary bytes, including NUL and malformed UTF-8, are
supported. Search is ported from **memchr 2.8.3**, bstr's search engine:
Goose implements preprocessing, Rabin–Karp, and Two-Way; a bundled C file
provides SIMD byte and packed-pair kernels. Goose builds that file through
`goostr.build`. A C compiler is required, including for JIT use; there is no
Rust runtime dependency. Rust is used only for testing and benchmarking.

**This is a core port, not the complete bstr API or universal performance parity.**
The supported operations and remaining gaps are listed below.

## Use it

Declare the local package in your program's root file. The path is relative
to that file, and must point to this directory:

```goose
import goostr from "../goostr";

fn main() {
    let bytes = "name=goose\xFF\r\ncount=42\n";
    goostr::lines(bytes) { line =>
        let key, value, found = goostr::split_once_str(line, "=");
        if found { print(key, ": ", goostr::to_str_lossy(value)); }
    }
    print(goostr::replace("a\0b\0c", "\0", " / "));
}
```

From this directory, run the included example:

```sh
goose run examples/basic.goose
```

Tested on macOS ARM64 with `goose version` reporting runtime `4d3da949e563`,
using both its in-process JIT and a native Clang build, and on Linux x86-64
(Ryzen 9 3950X) with the JIT and native GCC builds. AVX2 execution was confirmed
with coverage instrumentation. The search suite also passes under x86 emulation
with and without AVX2. Other platforms have not yet been verified.

## Goose API conventions

- Use `goostr::name(...)` to avoid collisions with `std` functions. For example,
  Goose's standard-library `split` treats an empty separator differently.
- Inputs are `const u8[:]`, accepting byte arrays, builders, and literals.
  Mutable operations take `u8[:]`. Goose already provides byte-string storage:
  use `u8[>..]` for a builder and `u8[]` for owned inline data; no `BStr` or
  `BString` wrapper is needed.
- Search positions are `i64` byte offsets, with **-1 for not found**.
- Iterators use Goose callbacks, not Rust iterator objects. For example:
  `goostr::split_str(data, ",") { part => print(part); }`.
  A `return` inside a block exits your enclosing named function, allowing
  early termination without collecting results.
- Splits, lines, fields, trimming, and UTF-8 chunks produce borrowed views.
  Keep their input alive. To collect views, push into `const u8[:][>..]`.
  To own copies, push into `u8[][>..]`.
- Transformations return `u8[>..]`. Functions ending in `_into` **append** to
  a caller-provided builder; they do not clear it. The output is the last
  argument: `goostr::replace_into(data, old, replacement, out)`.
- `splitn_str(data, separator, n)` limits **pieces**; `replacen(data, old,
  replacement, n)` limits **replacements**. Zero is valid; negative counts
  fail an assertion. Reverse splitting follows the same convention.
- `split_once_str` and its reverse return `(left, right, found)` as Goose
  multiple results. Both views are empty when `found` is false.
- `decode_utf8` and `decode_last_utf8` return `(codepoint, size, valid)`.
  Codepoints are `i64`. Malformed input yields U+FFFD with `valid = false`;
  an actual encoded U+FFFD has `valid = true`. Empty input consumes zero
  bytes and is not a successful decode. `_lossy` variants omit the flag.
- `validate_utf8` returns `(valid_up_to, error_len)`. Error length is zero
  for success, -1 for incomplete trailing UTF-8, or 1–3 for a malformed
  subpart. `char_indices` calls its block with `(start, end, codepoint)`;
  offsets always refer to the original bytes. `utf8_chunks` passes
  `(valid_bytes, invalid_bytes)` without a separate incomplete flag.

## Supported operations

| Area | Functions in `goostr` |
| --- | --- |
| Search | `find`, `rfind`, `finder`, `finder_reverse`, `contains_str`, `starts_with_str`, `ends_with_str`, `find_byte`, `rfind_byte`, `find_byteset`, `rfind_byteset`, `find_not_byteset`, `rfind_not_byteset`, `find_iter`, `rfind_iter` |
| Split | `split_str`, `rsplit_str`, `splitn_str`, `rsplitn_str`, `split_once_str`, `rsplit_once_str` |
| Replace | `replace`, `replacen`, `replace_into`, `replacen_into`, `repeatn` |
| Lines | `lines`, `lines_with_terminator` |
| Whitespace | `fields`, `fields_with`, `trim`, `trim_start`, `trim_end`, `trim_with`, `trim_start_with`, `trim_end_with`, `is_whitespace` |
| UTF-8 | `decode_utf8`, `decode_last_utf8`, `decode_utf8_lossy`, `decode_last_utf8_lossy`, `validate_utf8`, `is_utf8`, `chars`, `char_indices`, `utf8_chunks`, `to_str_lossy`, `to_str_lossy_into` |
| Byte transformations | `is_ascii`, `find_non_ascii_byte`, `to_ascii_lowercase`, `to_ascii_uppercase`, `make_ascii_lowercase`, `make_ascii_uppercase`, `reverse_bytes`, `reverse_chars`, `escape_bytes` |

Predicates passed to `_with` functions receive decoded codepoints, with
U+FFFD for malformed subparts. `fields_with(data, predicate) { part => ... }`
accepts a named predicate and a trailing block. `trim_with(data) { cp => ... }`
accepts a predicate block directly.

### Semantics worth knowing

- Matches do not overlap. Forward and reverse searches can choose different
  matches: `"ababa"` contains `"aba"` at offset 0 forward, 2 backward.
- Empty patterns match **every byte boundary**, including inside multibyte
  UTF-8 and both ends. Splitting `"é"` on `""` produces `""`, `"\xC3"`,
  `"\xA9"`, `""`. Replacing the empty pattern inserts between bytes.
- Lines end at LF or CRLF, not a bare CR. A final terminator does not add
  a trailing empty line; empty input yields no lines.
- UTF-8 decoding uses Unicode maximal-subpart replacement, preserving the
  byte offsets of malformed input. `reverse_chars` preserves those malformed
  bytes instead of expanding them to replacement characters.
- Trimming and fields use Unicode `White_Space`, including NBSP and ideographic
  space, but not U+200B or BOM. ASCII case conversion never changes non-ASCII
  bytes.
- `escape_bytes` preserves valid non-ASCII UTF-8. It escapes malformed bytes
  separately, uses uppercase hex, and escapes ASCII space as `\x20`, matching
  bstr rather than Rust string-literal escaping.

### Optimized substring search

- One-shot searches of haystacks shorter than 64 bytes use Rabin–Karp,
  avoiding finder preprocessing. That size bound limits its worst case.
- Forward searches for 2–32-byte needles use SIMD packed-pair search, selecting
  two predictive bytes using memchr's byte-frequency ranks. Candidate matches
  are verified against the entire needle; this is not a probabilistic search.
- Longer needles use linear-time Two-Way search, critical factorization,
  an approximate byte set, and a SIMD prefilter that disables itself when
  ineffective. Periodic and nonperiodic search loops are specialized.
- Reverse substring search uses reverse Two-Way, matching memchr's design.
  Single-byte searches in either direction use unrolled SIMD scans.
- SIMD targets are ARM64 NEON and runtime-dispatched x86-64 AVX2, with SSE2
  fallback on older x86-64 CPUs and scalar fallback on other architectures.
  Only AVX2 functions receive the AVX2 compiler target; the rest of the binary
  does not require it. Dispatch checks CPU/OS support and uses 32-byte vectors
  only when there are enough bytes or substring candidates. Wasm SIMD is not
  implemented. Native performance measurements below cover ARM64 and x86-64.

For repeated searches, preprocess the needle once:

```goose
let f = goostr::finder("needle");
let at = goostr::find(f, haystack);
let r = goostr::finder_reverse("needle");
let last = goostr::rfind(r, haystack);
```

Finders borrow their needle: keep it alive and **do not mutate it** until
finished with the finder. Use the constructors rather than constructing or
modifying finder fields. `find_iter`, `rfind_iter`, splitting, and replacement
reuse preprocessing within each operation. Search allocates no heap memory.

### Byte-set search

All four byte-set operations bypass Goose's standard-library `ByteSet`.
Sets of one, two, or three bytes use four-vector-unrolled SIMD comparisons,
including reverse searches and searches for bytes **outside** the set.
Larger sets use a 256-byte stack membership table: one zero-fill, one pass
over the set, and a scalar scan. Empty sets and empty inputs are handled
directly; full sets are detected before scanning the haystack. Duplicate
members, NUL, and high-bit bytes are supported.

### Remaining gaps

Not implemented: Unicode case mapping, grapheme/word/sentence segmentation
and grapheme reversal, character-search
conveniences, Rust-style double-ended iterator objects, and bstr's OS/path,
I/O, and serde integrations. Use Goose's arrays and standard library for
ordinary ownership, byte iteration, joining, and I/O. There is no distinct
UTF-8 string type to convert into; use `validate_utf8` when validation is needed.

Byte-set searches with more than three input set bytes and Unicode decoding
remain scalar. UTF-8 optimization is outside this search work.

## Tests

The native suite requires Goose and its C toolchain:

```sh
goose run tests/test.goose --debug
goose run tests/test.goose --debug -O0
goose build tests/test.goose --debug -O2
./tests/test
goose run tests/search.goose --debug
goose build tests/search.goose -O2
./tests/search
```

The search suite checks 40,929 haystack/needle pairs against an independent
naive oracle, including exhaustive short binary inputs, aligned and unaligned
hits at SIMD/dispatch boundaries, periodic patterns, ineffective prefilters,
and seeded random inputs. It checks one-shot searches, reused finders,
non-overlapping iterators, and all four byte-set operations. Another 21,240
byte-set cases cover every position around vector/unroll boundaries, empty
and full sets, duplicates, NUL, and high-bit bytes.

The public search suite passes on native ARM64, native x86-64 AVX2, and under
QEMU x86-64 with Haswell (AVX2) and Nehalem (SSE2) CPU models. Separate development checks ran
12,832,068 guard-page kernel checks per backend: NEON, SSE2 under Rosetta,
and scalar with ASan/UBSan, plus AVX2 and SSE2 under QEMU without sanitizers.
These are correctness checks, not native x86 performance measurements.

Differential testing additionally requires Cargo, Python 3, and a C compiler
usable by `goose build`. Cargo downloads the pinned Rust test dependencies
on first use; none are runtime dependencies of goostr.

```sh
python3 tests/differential.py
```

The differential suite compares search, splitting, replacement, decoding,
lossy conversion, chunks, escaping, reversal, case conversion, whitespace,
and line results directly with **bstr 1.13.1**. Its 71,195 deterministic cases
include every one- and two-byte input, UTF-8 boundary/truncation cases, Unicode
whitespace, overlapping patterns, and longer random binary and Unicode data.

## Reproduce the performance comparison

```sh
python3 bench/compare.py --output search-results.json
python3 bench/compare.py --suite byteset --output byteset-results.json
```

This builds Goose with `-O2` and the pinned Rust oracle in release mode, then
compares 17 deterministic datasets in four modes: one-shot `find`/`rfind` and
prepared `Finder`/`FinderReverse`. Inputs include small requests, 1 MiB text
and random binary, start/end hits, misses, 32/33-byte dispatch boundaries,
single-byte search, periodic/adversarial patterns, and a 2048-byte needle.
The byte-set suite compares 13 datasets across all four byte-set operations,
including short requests, large misses, complements, duplicates, and empty
and full sets.

Both runners use the same separately compiled opaque C barrier to prevent
hoisting searches out of the timed loop. Input I/O, process startup, and
prepared-finder construction are outside the timer; one-shot preprocessing
is included. Each workload calibrates to at least 50 ms (with an iteration
cap), then records five alternating samples per implementation and their
medians. Each process discards a full warm-up pass before measuring. Every
run checks a checksum against Python's independent byte search.
Byte-set checks use an independent Python membership oracle.
JSON records timings, iterations, input/source/executable hashes, and toolchain
versions. Ratios are **Goose time / bstr time**: lower is better. macOS runners
request the same user-initiated QoS; no CPU core is pinned.

The script uses a fresh `GOOSE_HOME` for each build. Goose runtime
`4d3da949e563` otherwise reuses native-package C objects across debug and
release builds, which can silently benchmark unoptimized kernels. Use
separate `GOOSE_HOME` directories for your own debug/release builds too.

### Measured results, not universal parity

Two earlier runs and a final rerun on an Apple M1 Pro (2026-10-29), with
Goose runtime `4d3da949e563`, Apple Clang 21, and Rust 1.97.1, produced these
**medians of the 17 per-dataset time ratios**. These are not weighted by
workload frequency; each dataset's time is itself a median of five samples.
The final run includes the byte-set replacement and new shared SIMD kernels.

| Search mode | Earlier run 1 | Earlier run 2 | Current |
| --- | ---: | ---: | ---: |
| One-shot forward | 1.04× | 1.05× | 1.04× |
| Reused forward finder | 1.08× | 1.06× | 1.08× |
| One-shot reverse | 1.22× | 1.10× | 1.07× |
| Reused reverse finder | 1.06× | 1.03× | 1.01× |

Forward 1 MiB text/binary misses took 1.04–1.11× bstr's time. The largest
repeatable gap was a reverse end hit with a 16-byte needle: 1.76–1.77×,
falling to 1.06–1.14× when reusing the reverse finder. Other remaining gaps
include about 1.30× for a prepared forward match of the 2048-byte needle.
Host scheduling/frequency variation was visible despite warm-up and QoS,
so small percentage differences should not be treated as guarantees.
This is near parity for the principal forward scans, **not parity for every
workload**, and says nothing about throughput on unmeasured CPUs.

### Byte-set measurements

On the same M1 Pro, five-sample medians with the new byte-set suite gave the
following results. The baseline rebuilds the former `ByteSet` strategy in an
isolated copy, using the same benchmark runner and release flags.

| Forward operation | ByteSet baseline | Current | bstr |
| --- | ---: | ---: | ---: |
| Short request, two-byte set miss | 251.5 ns | 4.6 ns | 3.6 ns |
| 1 MiB, one-byte set miss | 24.7 µs | 13.1 µs | 12.5 µs |
| 1 MiB, two-byte set miss | 348.8 µs | 22.3 µs | 24.0 µs |
| 1 MiB, three-byte set miss | 335.3 µs | 33.5 µs | 34.6 µs |
| 1 MiB, four-byte set miss | 338.3 µs | 345.7 µs | 361.0 µs |
| 1 MiB, no byte outside a one-byte set | 333.9 µs | 13.9 µs | 28.4 µs |

Large scans are close to bstr, but small early-hit cases still have several
nanoseconds of overhead; the slowest relative case took 9.9 ns versus 2.5 ns.
The replacement is not faster than `ByteSet` on every input: a three-byte
set containing the same byte three times took 32.6 µs versus 24.5 µs before
(bstr: 34.1 µs), because the old classifier deduplicated it to a one-byte scan.
The full-set shortcut is retained: searching for an outside byte returns
without scanning the haystack. These M1 timings measure NEON; native AVX2
measurements follow.

### Native AVX2 measurements

Two complete runs on Marvin's AMD Ryzen 9 3950X (Linux x86-64, 2026-10-29)
used Goose runtime `4d3da949e563`, GCC 13.3.0 `-O2`, and Rust 1.97.1 release.
Both implementations were pinned to logical CPU 2 with `taskset -c 2`; each
workload recorded five alternating samples after warm-up. No global AVX2 or
`-march=native` flag was used. The public search and bstr differential suites
passed natively, and instrumented runs confirmed AVX2 dispatch was exercised.

Median of the 17 substring dataset time ratios (Goose / bstr):

| Search mode | Run 1 | Run 2 |
| --- | ---: | ---: |
| One-shot forward | 0.83× | 0.83× |
| Reused forward finder | 1.13× | 1.14× |
| One-shot reverse | 0.97× | 0.97× |
| Reused reverse finder | 0.93× | 0.93× |

The 1 MiB two-byte **byte-set** miss took 12.15–12.22 µs versus bstr's
13.04–13.09 µs. The two-byte **substring** miss remained slower: 23.49–23.58 µs
versus 15.90–15.98 µs (1.48×). Other repeatable gaps included the 33-byte
needle end hit (1.25×) and prepared reverse periodic miss (1.41×).
Byte-set complement calls that return immediately took up to 2.72× bstr's
time (8.7 versus 3.2 ns). Native AVX2 works, but does not establish universal
performance parity.

Reproduce on Linux with `taskset -c 2 python3 bench/compare.py --output results.json`
and the corresponding `--suite byteset` invocation; choose an available CPU.

### ASCII conversion

The in-place ASCII transforms use range-selected masks and unconditional
OR/XOR stores, following [Goose PR #124](https://github.com/aardappel/goose/pull/124).
Tests cover all 256 byte values, an unaligned slice with unchanged neighboring
bytes, and empty slices. ARM64 and native x86-64 differential tests pass.

Using that PR's 8 MiB mixed-ASCII restore-and-convert benchmark (128 iterations),
adapted to call goostr's functions, mean whole-process times on Marvin were:

| Compiler, generic `-O2` | Lower: before → after | Upper: before → after |
| --- | ---: | ---: |
| GCC 13.3 | 1031.4 → 376.5 ms (2.74×) | 918.2 → 378.6 ms (2.43×) |
| Clang 18.1 | 424.8 → 108.7 ms (3.91×) | 422.4 → 105.8 ms (3.99×) |

Hyperfine used five warmups and twenty runs, `--shell=none`, and CPU-2 affinity.
Times include initialization, copies, conversion, and checksum; GCC baseline
timings were more variable. Assembly inspection confirmed unconditional SIMD
stores after the change; Clang's original loop extracted and stored individual
lanes conditionally. These are bulk-input results, not a claim for every size.

## License and attribution

MIT; see [LICENSE](LICENSE). This port follows bstr's documented behavior and
adapts its reverse-character algorithm and memchr's search algorithms and
frequency table. bstr and memchr are by Andrew Gallant and contributors;
their copyright notices are retained. The library imports Goose's standard
library rather than vendoring it.
