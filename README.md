# goostr

**[API reference](API.md)** — function signatures, contracts, and source links.

A native [Goose](https://github.com/aardappel/goose) port of the byte-string
core of Rust's [bstr](https://github.com/BurntSushi/bstr), targeting **bstr
1.13.1 semantics**. Arbitrary bytes, including NUL and malformed UTF-8, are
supported. Search is ported from **memchr 2.8.3**, bstr's search engine:
Goose implements preprocessing, Rabin–Karp, Two-Way, and the SIMD byte,
byte-set, and packed-pair loops. [goosimd](https://github.com/sstadick/goosimd)
supplies header-only load, comparison, and mask primitives. There is no
separately compiled search kernel or Rust runtime dependency. Rust is used
only for testing and benchmarking.

This version requires Goose's [`c_headers` support](https://github.com/aardappel/goose/pull/141)
and the [generic goosimd API](https://github.com/sstadick/goosimd).
Imports use goosimd's `main` branch, so no sibling checkout is needed.
goosimd remains experimental, with no stable API or representation guarantee.

**This is a core port, not the complete bstr API or universal performance parity.**
The supported operations and remaining gaps are listed below.

## Releases

Current version: [v0.1.0](https://github.com/sstadick/goostr/releases/tag/v0.1.0).
Versions are Git tags (`vMAJOR.MINOR.PATCH`). Pushing a version tag runs CI
and publishes a GitHub source release only after tests and the documentation
check pass. Future releases also attach `API.md` with source links pinned to
the release commit. CI runs on branch pushes and pull requests as well.
The examples below track `main`.

## API documentation

[API.md](API.md) is generated from source comments with
[goosdoc v0.1.0](https://github.com/sstadick/goosdoc/releases/tag/v0.1.0).
Edit the comments, not the generated file. `api.txt` selects the supported
API and excludes implementation helpers; all selected overloads need comments.

With Goose on `PATH`, run from this checkout:

```sh
git clone --branch v0.1.0 --depth 1 https://github.com/sstadick/goosdoc.git ../goosdoc
scripts/docs.sh
scripts/docs.sh --check
```

Skip cloning if goosdoc is already beside this repository. For another
location, set `GOOSDOC=/path/to/goosdoc/main.goose`. CI pins the generator's
commit and rejects missing comments or a stale reference. Checked-in source
links are relative; release artifacts use immutable GitHub permalinks.

## Use it in a Goose project

Save this as `main.goose` in your project. Goose fetches both packages from
GitHub. The root file must declare goosimd explicitly as well as goostr:

```goose
import goostr from "github.com/sstadick/goostr@main";
import goosimd from "github.com/sstadick/goosimd@main";

fn main() {
    let bytes = "name=goose\xFF\r\ncount=42\n";
    goostr::lines(bytes) { line =>
        let key, value, found = goostr::split_once_str(line, "=");
        if found { print(key, ": ", goostr::to_str_lossy(value)); }
    }
    print(goostr::replace("a\0b\0c", "\0", " / "));
}
```

Run it or build an executable:

```sh
goose run main.goose
goose build main.goose -O2 -o demo
```

No local checkout or consumer `--include` flag is needed. `@main` follows
the development branches; use commits for reproducible dependencies.
From a goostr checkout, you can also run `goose run examples/basic.goose`.

The goosimd version is tested on Linux x86-64 (Ryzen 9 3950X) with TinyCC,
GCC, and Clang, using SSE2, AVX2, and forced scalar builds. TinyCC runs the
scalar fallback and needs no external C compiler for this package. Native
builds require a C compiler. Earlier bindings passed on Apple ARM64 with
NEON; this generic-API revision has not been verified on ARM or Windows.

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

- One-shot searches of haystacks shorter than 64 bytes avoid finder
  preprocessing: 2–32-byte needles with 16–31 candidate positions use narrow
  SIMD with the needle's first/last bytes; other cases use Rabin–Karp.
  The size bound limits its worst case.
- Searches for 2–32-byte needles use SIMD packed-pair search, selecting
  two predictive bytes using memchr's byte-frequency ranks. Candidate matches
  are verified against the entire needle; this is not a probabilistic search.
- Longer needles use linear-time Two-Way search, critical factorization,
  an approximate byte set, and a forward SIMD prefilter that disables itself when
  ineffective. Periodic and nonperiodic search loops are specialized.
- Reverse SIMD searches inspect the highest candidate bits first. Prepared
  reverse searches with fewer than 16 candidate positions use Two-Way instead.
  Single-byte searches in either direction use unrolled SIMD scans.
- Searches use goosimd's `Vec<u8[16]>`/`Vec<u8[32]>` loads, byte comparisons,
  and typed masks. The generic wrappers inline across the package boundary.
  These scan functions select SIMD at compile time: SSE2 by default on x86-64,
  AVX2 with `-mavx2`, NEON on ARM64, and scalar fallback under TinyCC.
  goosimd supports runtime selection inside `simd fn`, but goostr retains
  **compile-time dispatch**. An AVX2 build requires an AVX2 CPU.
  Logical blocks contain 16 or 32 bytes; vector
  loads stay within the input and only test valid substring start positions.
  Wasm SIMD is not implemented.

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
Larger sets use a zero-initialized 256-byte stack membership table, one pass
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

Use a Goose compiler with `c_headers` support. Native tests also require its C toolchain:

```sh
goose run tests/test.goose --debug
goose run tests/test.goose --debug -O0
goose build tests/test.goose --debug -O2
./tests/test
goose run tests/search.goose --debug
goose build tests/search.goose -O2
./tests/search
```

The search suite checks 44,624 haystack/needle pairs against an independent
naive oracle, including exhaustive short binary inputs, aligned and unaligned
hits at SIMD/dispatch boundaries, periodic patterns, ineffective prefilters,
and seeded random inputs. It checks one-shot searches, reused finders,
non-overlapping iterators, and all four byte-set operations. Another 21,240
byte-set cases cover every position around vector/unroll boundaries, empty
and full sets, duplicates, NUL, and high-bit bytes.

The generic-API revision passes the search suite with TinyCC, GCC and Clang
baseline and AVX2, forced scalar adapters, and Clang ASan/UBSan.
All those native variants also passed 37,740 guard-page cases with haystacks
and needles abutting inaccessible pages at either end.
Earlier Apple ARM64 results used the previous bindings;
earlier QEMU results used the former C kernels, not this migration.

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

The default build uses the native compiler's default target (SSE2 on x86-64).
For AVX2 on a compatible machine, compile the emitted C explicitly:

```sh
OUT=$(mktemp -d)
goose --standalone -o "$OUT/search.c" bench/search.goose
gcc -O2 -mavx2 "$OUT/search.c" bench/opaque.c -o "$OUT/search" -lm -pthread -ldl
taskset -c 2 python3 bench/compare.py --goose-exe "$OUT/search" --output search-avx2.json
taskset -c 2 python3 bench/compare.py --goose-exe "$OUT/search" --suite byteset --output byteset-avx2.json
```

These commands are for Linux; choose an available CPU. Add `--baseline-exe`
to include a previously built goostr binary in the same alternating samples.
The JSON then includes `baseline_ns` and `baseline_ratio` (new / baseline).

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

## Generic API integration results

Compared with the previous concrete goosimd API on Marvin (Ryzen 9 3950X),
using GCC 13.3 and Clang 18.1 at `-O2 -mavx2`, CPU-2 affinity,
alternating implementations, and five samples per workload:

| Operation | Previous API | Generic API |
| --- | ---: | ---: |
| GCC AVX2, prepared tiny hit | 6.41 ns | 5.93 ns |
| GCC AVX2, prepared tiny miss | 5.11 ns | 4.75 ns |
| GCC AVX2, prepared 1 MiB text miss | 20.02 µs | 14.46 µs |
| GCC AVX2, prepared reverse 1 MiB text miss | 183.72 µs | 23.84 µs |
| GCC AVX2, prepared reverse 2048-byte needle | 990.00 ns | 159.23 ns |
| Clang AVX2, prepared tiny hit | 5.21 ns | 4.52 ns |
| Clang AVX2, prepared tiny miss | 3.80 ns | 3.57 ns |

The generic wrappers inline across package boundaries. Matching GCC's
baseline loads and operations at 16 bytes removes redundant aggregate
copies. GCC broadcasts use a scalar operand rather than constructing a
vector lane by lane, avoiding a stack temporary on short searches.

Scanning two blocks together fixes the earlier GCC AVX2 bulk-miss regression.
Reverse searches now use SIMD for short needles and word comparisons inside
Two-Way for long needles. Reusing offset slices avoids repeated bounds and
address calculations in the narrow path. GCC baseline tiny prepared hit/miss
probes measured 6.30/4.99 ns versus 6.89/5.47 ns with the concrete API.

This is not an across-the-board speedup: some Clang byte-set early exits
remain about 0.5–1.2 ns slower (roughly 8–16%). Earlier Clang bulk timings
varied substantially, so the table emphasizes its short-input results.
The final full comparison covered GCC AVX2 substring searches and both
Clang AVX2 suites; the final GCC baseline check was a targeted tiny-input
probe, not another full matrix. ARM and Windows performance is unverified.

## Earlier goosimd tuning results

These measurements predate the generic-API integration. Measured on Marvin's
Ryzen 9 3950X with GCC 13.3.0 `-O2 -mavx2`, the patched
Goose compiler (runtime `f2981814a754`), and bstr 1.13.1. Before/after binaries
and bstr ran in alternating order, pinned to CPU 2, with five samples per
workload. Both goostr versions used the same compiler and global flags.
The baseline is the initial Goose/goosimd migration, before restoring the
16-byte short-input path and removing the redundant table initialization.

| Forward operation | Before tuning | Current | bstr |
| --- | ---: | ---: | ---: |
| Prepared tiny substring hit | 10.54 ns | 6.33 ns | 8.72 ns |
| Prepared tiny substring miss | 14.21 ns | 5.02 ns | 8.29 ns |
| Tiny two-byte set miss | 13.82 ns | 5.54 ns | 7.34 ns |
| Tiny four-byte set first hit | 29.75 ns | 7.76 ns | 6.20 ns |
| 1 MiB text substring miss | 19.50 µs | 19.85 µs | 23.39 µs |
| 1 MiB binary substring miss | 19.75 µs | 20.11 µs | 30.97 µs |
| 1 MiB two-byte substring miss | 18.71 µs | 19.75 µs | 16.01 µs |
| 1 MiB two-byte set miss | 12.17 µs | 12.11 µs | 13.10 µs |
| 1 MiB four-byte set miss | 476.33 µs | 330.51 µs | 530.33 µs |

The 16-byte path uses overlapping blocks without reading outside the input.
It stays separate from the 32-byte substring loop to avoid increasing that
loop's register pressure. Table scans are unrolled four bytes at a time.
Disassembly confirms inlined vector comparisons and masks, and a single
vectorized table clear rather than two fill passes.

The former C kernels took about 7.35/7.95 ns for prepared tiny hits/misses
and 6.47 ns for the four-byte-set first hit. The large regressions are gone,
but **performance parity is not universal**: some early exits still cost
roughly an extra nanosecond. Text/binary misses increased about 2% versus the
untuned migration, and the two-byte substring miss about 6%; the latter
remained slower than bstr. Reverse substring search was still scalar Two-Way
at this stage; the generic-API revision above adds reverse SIMD search.

GCC reports optimization-attribute mismatch warnings at scalar extern
redeclarations in generated C. The builds and checks pass without suppressing
them, and the adapters inline; Clang does not emit these warnings. Runtime
ISA dispatch is not retained: AVX2 is opt-in, and TinyCC uses scalar adapters.

## Historical C-kernel results

The measurements below predate the goosimd migration. They describe the
former separately compiled C kernels and are retained for comparison;
they are not measurements of the current implementation.

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
