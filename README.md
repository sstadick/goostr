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

## Choose an operation

| Task | Start with |
| --- | --- |
| Search forward or backward | `find`, `rfind`, `finder`, `finder_reverse` |
| Search for individual bytes or a set | `find_byte`, `find_byteset`, `find_not_byteset` and their reverse variants |
| Iterate matches or split input | `find_iter`, `split_str`, `splitn_str`, `split_once_str` |
| Replace or repeat bytes | `replace`, `replacen`, `replace_into`, `repeatn` |
| Read lines or words | `lines`, `lines_with_terminator`, `fields` |
| Trim text | `trim`, `trim_start`, `trim_end`, `trim_with` |
| Decode or validate UTF-8 | `chars`, `char_indices`, `utf8_chunks`, `validate_utf8`, `to_str_lossy` |
| Change or inspect bytes | `is_ascii`, `to_ascii_lowercase`, `reverse_bytes`, `reverse_chars`, `escape_bytes` |

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
For optimized native searches, build with GCC or Clang. TinyCC uses scalar
code; AVX2-only builds require an AVX2 CPU. goostr does not select AVX2 at runtime.

## Contributing

Run the library tests from this checkout:

```sh
goose run tests/test.goose --debug
goose run tests/search.goose --debug
python3 tests/differential.py
```

The bstr comparison requires Python 3, Cargo, and a native C compiler.
To run search benchmarks against bstr, start with
`python3 bench/compare.py --help`.

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
