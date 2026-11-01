# goostr

Search, split, and transform byte strings in [Goose](https://github.com/aardappel/goose).
Use it for text or arbitrary bytes, including NUL and malformed UTF-8.
goostr follows the core byte-string behavior of Rust's
[bstr](https://github.com/BurntSushi/bstr).

**[API reference and examples](API.md)** · [Releases](https://github.com/sstadick/goostr/releases)

## Get started

Save this as `main.goose`. Goose downloads the packages; no local library
checkout is needed. Declare both imports in your program's root file:

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

```sh
goose run main.goose
# name: goose�
# count: 42
# a / b / c

goose build main.goose -O2 -o demo
```

Use a Goose compiler with package `c_headers` support. TinyCC works without
an external C compiler; native builds need GCC or Clang. Tested on Linux
x86-64; ARM and Windows are unverified. The examples follow `main`; pin
imports to commits for reproducible builds. The goosimd dependency is experimental.

## Find bytes and patterns

Search returns a **byte offset**, or **-1** when nothing matches. These
examples go inside `main()` with the imports above:

```goose
assert(goostr::find("café menu", "menu") == 6);
assert(goostr::rfind("ababa", "aba") == 2);
assert(goostr::find_byteset("name=value;", "=;") == 4);
assert(goostr::find("goose", "duck") == -1);
assert(goostr::find_char("café", 0xE9) == 3); // Unicode scalar, byte offset.

// Reuse a finder when searching for the same pattern in several inputs.
let f = goostr::finder("error");
assert(goostr::find(f, "an error occurred") == 3);
assert(goostr::find(f, "all clear") == -1);
```

Finders borrow their pattern. Keep its bytes alive and unchanged while using
the finder. An empty pattern matches every byte boundary, including both ends.

## Split and transform

Iterators call your block once per result. Splits, lines, fields, and trimming
return borrowed views: keep the input alive while using them.

```goose
var parts: const u8[:][>..] = [];
goostr::split_str("red,green,blue", ",") { part => parts.push(part); }
assert(parts.len == 3 && parts[1] == "green");

assert(goostr::trim(" \tgoose\r\n") == "goose");
assert(goostr::replace("one-two-three", "-", "/") == "one/two/three");

// Functions ending in _into append to your builder; they do not clear it.
var out: u8[>..] = [];
out.append("result: ");
goostr::replace_into("a-b", "-", "/", out);
assert(out == "result: a/b");
```

Use Goose's own byte arrays and builders: inputs are `const u8[:]`, mutable
operations take `u8[:]`, and owned results use `u8[>..]`. There is no extra
string wrapper to convert to or from.

## Work with imperfect text

Byte operations do not require UTF-8. When you need readable text, use lossy
conversion to replace malformed sequences with `�`, or validate first:

```goose
assert(!goostr::is_utf8("hello\xFF"));
assert(goostr::to_str_lossy("hello\xFF") == "hello�");

let end, error = goostr::validate_utf8("ok\xE2\x82");
assert(end == 2 && error == -1); // Incomplete UTF-8 after "ok".
```

For a printable representation that preserves arbitrary bytes, use
`escape_bytes`. Decode it with `unescape_bytes`:

```goose
let bytes = "line\n\xFF";
let escaped = goostr::escape_bytes(bytes);
assert(escaped == "line\\n\\xFF");
assert(goostr::unescape_bytes(escaped) == bytes);
assert(goostr::unescape_bytes("\\q") == "\\q"); // Unknown escapes stay literal.
```

`unescape_bytes` recognizes `\0`, `\n`, `\r`, `\t`, `\\`, and `\xHH`.
It does not decode Unicode escapes such as `\u{1234}`.

## Choose an operation

| Task | Start with |
| --- | --- |
| Search forward or backward | `find`, `rfind`, `finder`, `finder_reverse` |
| Search for individual bytes or a set | `find_byte`, `find_byteset`, `find_not_byteset` and their reverse variants |
| Search for a Unicode codepoint | `find_char`, `rfind_char` (return byte offsets) |
| Iterate matches or split input | `find_iter`, `split_str`, `splitn_str`, `split_once_str` |
| Replace or repeat bytes | `replace`, `replacen`, `replace_into`, `repeatn` |
| Read lines or words | `lines`, `lines_with_terminator`, `fields` |
| Trim text | `trim`, `trim_start`, `trim_end`, `trim_with` |
| Decode or validate UTF-8 | `chars`, `char_indices`, `utf8_chunks`, `validate_utf8`, `to_str_lossy` |
| Change or inspect bytes | `is_ascii`, `to_ascii_lowercase`, `reverse_bytes`, `reverse_chars`, `escape_bytes` |
| Decode escaped bytes | `unescape_bytes` |

See the [API reference](API.md) for all signatures and examples. A few rules
are worth knowing before choosing an operation:

- Matches from iterators, splitting, and replacement do not overlap. Forward
  and reverse searches can therefore choose different matches.
- `splitn_str` limits pieces; `replacen` limits replacements.
- Lines end at LF or CRLF, not a bare CR. A final terminator adds no extra line.
- Trimming and fields recognize Unicode whitespace. ASCII case conversion
  changes only ASCII letters.
- `reverse_chars` reverses codepoints, not grapheme clusters. Unicode case
  mapping and grapheme/word/sentence segmentation are not provided.

This is not the complete bstr API, and performance parity is not guaranteed.
For optimized native searches, build with GCC or Clang. Clang on x86-64
selects supported SIMD instructions at runtime for long scans; short searches
and early matches avoid dispatch. GCC uses the build target, and TinyCC uses
scalar code. To enable runtime selection:

```sh
goose build main.goose --cc clang -O2 -o demo
```

Goose's runtime AVX2 selection also requires FMA, BMI1/2, LZCNT, POPCNT, and
OS support. Compiling emitted C with `-DGS_SIMD=0` disables runtime selection;
adding `-mavx2` selects AVX2 at compile time and requires an AVX2 CPU.

## Search performance

These warm-cache microbenchmarks compare goostr
[`e2774d7`](https://github.com/sstadick/goostr/commit/e2774d73d76cc61e96207c188a840b9226d42b0f)
with bstr 1.13.1 (memchr 2.8.3) on a Ryzen 9 3950X, Linux x86-64.
Goostr uses Goose `b4609902` and Clang 18.1.3; bstr uses Rust 1.97.1.
Both use optimization level 2 and runtime SIMD selection, with AVX2 available.

Times are medians of nine measured batches, calibrated to at least 50 ms,
pinned to CPU 4. Both runners use identical inputs and the same opaque C
barrier, warm up before timing, rotate execution order, and check results.
File I/O and process startup are excluded. Prepared searches exclude finder
construction on both sides; ordinary substring searches include it.

**Ratio = goostr / bstr; lower is better for goostr.** This selection includes
wins and losses from 296 case/operation comparisons, not an overall score.

| Input / scenario | Operation | goostr | bstr | Ratio |
| --- | --- | ---: | ---: | ---: |
| 23 B, substring hit | `find` | 5.6 ns | 35.8 ns | 0.15× |
| Same, reusable finder | prepared `find` | 5.1 ns | 8.3 ns | 0.61× |
| 63 B, one-byte miss | `rfind` | 88.1 ns | 18.8 ns | 4.70× |
| 64 B, three-byte miss | prepared `find` | 19.3 ns | 7.8 ns | 2.48× |
| 1 MiB text, substring miss | `find` | 16.45 µs | 15.94 µs | 1.03× |
| Same, searching backward | `rfind` | 23.38 µs | 146.25 µs | 0.16× |
| 1 MiB random bytes, substring miss | `find` | 16.69 µs | 23.18 µs | 0.72× |
| 1 MiB, one-byte miss | `find` | 10.92 µs | 10.69 µs | 1.02× |
| 1 MiB + 33 B, 33-byte needle at end | `rfind` | 160.2 ns | 110.4 ns | 1.45× |
| 1 MiB repetitive data, 256-byte needle miss | `find` | 1,217 µs | 1,700 µs | 0.72× |
| 1 MiB, two-byte set miss | `find_byteset` | 14.36 µs | 13.38 µs | 1.07× |
| 1 MiB, three-byte set miss | `find_byteset` | 17.65 µs | 16.50 µs | 1.07× |
| 1 MiB, four-byte set miss | `find_byteset` | 369.81 µs | 541.03 µs | 0.68× |
| 768 KiB, all bytes in a three-byte set | `find_not_byteset` | 13.29 µs | 410.40 µs | 0.03× |

Compiler settings matter. In 19 additional controls using Rust's default
release optimization level 3, the text-miss comparison was 17.23 µs versus
25.22 µs. The small reverse-search loss and two-/three-byte-set gaps remained.
These results do not predict cold-cache, other-platform, or whole-library
performance. See the benchmark commands below to measure your workload.

## Contributing

Run the library tests from this checkout:

```sh
goose run tests/test.goose --debug
goose run tests/search.goose --debug
python3 tests/differential.py
```

The bstr comparison requires Python 3, Cargo, and a native C compiler.
Compare search performance against bstr with the same inputs and checked results:

```sh
python3 bench/compare.py --cc clang --target runtime --suite substring --output substring.json
python3 bench/compare.py --cc clang --target runtime --suite byteset --output byteset.json
python3 bench/compare.py --cc gcc --target baseline --suite boundary --output boundary.json
```

The boundary suite covers lengths around scalar/SIMD and search-algorithm
cutoffs. Use `--target avx2` only on a capable CPU, `--case 'tiny-*'` to select
cases, or `--baseline-exe` to compare with a previously built version. Timings
exclude file I/O, include a warm-up pass, and retain individual samples and
compiler/CPU details in JSON. Pin the benchmark to one CPU where possible;
run compiler/target comparisons sequentially. See `--help` for other options.

For the table's matched-O2 configuration on Linux, use:

```sh
CARGO_PROFILE_RELEASE_OPT_LEVEL=2 taskset -c 4 python3 bench/compare.py \
  --cc clang --target runtime --suite substring --samples 9 --sample-ms 50 \
  --output substring-o2.json
```

Repeat with `--suite byteset` or `--suite boundary` for those operations.
Choose an available CPU on your machine. Without the environment variable,
Cargo uses release optimization level 3; the Goose C build still uses `-O2`.

API documentation comes from source comments. With
[goosdoc v0.2.0](https://github.com/sstadick/goosdoc/releases/tag/v0.2.0)
checked out at `../goosdoc`, run:

```sh
scripts/docs.sh
scripts/docs.sh --check
scripts/doctest.sh
scripts/doctest.sh --cc gcc
scripts/doctest.sh --cc clang
```

Set `GOOSDOC=/path/to/goosdoc/main.goose` for another location. Edit source
comments, not `API.md`. Every API declaration needs an executable example;
see the [example conventions](https://github.com/sstadick/goosdoc#executable-examples).
CI checks the reference and runs examples and tests before publishing releases.

## License

MIT; see [LICENSE](LICENSE). goostr adapts bstr and memchr code by Andrew
Gallant and contributors; their copyright notices are retained.
