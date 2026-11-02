#!/usr/bin/env python3
"""Repeatable bstr comparison; timings exclude input I/O and process startup."""
import argparse
from datetime import datetime, timezone
import fnmatch
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import re
import statistics
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SUBSTRING_MODES = ["find", "rfind", "prepared-find", "prepared-rfind"]
BYTESET_MODES = ["find-set", "rfind-set", "find-not-set", "rfind-not-set"]
COUNT_MODES = ["count", "rcount"]
MEMCHR_REVISION = "5fdb40c054e1fff359a2f7bdf7f87a13b34b465d"
RECORDS_SHA256 = "94d895dd9be5e5c38c786b7056d2aba8c7066444c259af043a4f990b35525be5"


def upstream_cases(checkout):
    """Read the pinned memchr literal-count definitions without modifying inputs."""
    import tomllib

    revision = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
    if revision != MEMCHR_REVISION:
        raise ValueError(f"memchr checkout must be at {MEMCHR_REVISION}")
    subprocess.run(["git", "-C", str(checkout), "diff", "--exit-code", "HEAD", "--", "benchmarks"],
                   check=True, stdout=subprocess.DEVNULL)
    root = checkout / "benchmarks"
    selected, sources = [], {}
    # sliceslice.toml uses multi-needle models, not single-literal count.
    for relative in ("code.toml", "byterank.toml", "pathological.toml",
                     "subtitles/never.toml", "subtitles/rare.toml", "subtitles/common.toml"):
        definition = root / "definitions/memmem" / relative
        for case in tomllib.loads(definition.read_text())["bench"]:
            assert case["model"] == "count"
            pattern = case["regex"].encode("utf-8")
            # The only byte escapes used by these pinned definitions are \xHH.
            assert b"\\" not in re.sub(rb"\\x[0-9a-fA-F]{2}", b"", pattern)
            pattern = re.sub(rb"\\x([0-9a-fA-F]{2})", lambda m: bytes([int(m[1], 16)]), pattern)
            haystack = root / "haystacks" / case["haystack"]["path"]
            data = haystack.read_bytes()
            assert data.count(pattern) == case["count"], case["name"]
            name = relative.removesuffix(".toml") + "/" + case["name"]
            selected.append((name, data, pattern))
            sources[name] = dict(definition=str(definition.relative_to(root)),
                                 definition_sha256=hashlib.sha256(definition.read_bytes()).hexdigest(),
                                 haystack=case["haystack"]["path"],
                                 haystack_sha256=hashlib.sha256(data).hexdigest(),
                                 pattern_hex=pattern.hex(), upstream_count=case["count"])
    return selected, dict(repository="https://github.com/BurntSushi/memchr", revision=revision,
                          cases=sources)


def cases():
    rng = random.Random(1731)
    text = (b"The quick brown fox jumps over the lazy dog. Byte strings keep arbitrary data.\n" * 14000)[:1 << 20]
    binary = rng.randbytes(1 << 20)
    tail = b"0123456789abcdef" * 2 + b"!"
    false_tail = tail[:16] + b"?" + tail[17:]
    long = text[13:2061]
    irregular = b"".join(b"\0" * 7 + bytes([rng.randrange(1, 32)]) for _ in range(256))
    triples = (b"zza" * ((1 << 20) // 3 + 1))[:1 << 20]
    near_periodic = b"z" * 114 + b"az"
    for name, haystack, needle in [
        ("tiny-hit", b"GET /api/items HTTP/1.1", b"items"),
        ("tiny-miss", b"GET /api/items HTTP/1.1", b"users"),
        ("text-miss", text, b"needle"),
        ("text-end", text + b"unique-needle", b"unique-needle"),
        ("text-start", b"unique-needle" + text, b"unique-needle"),
        ("text-common", text, b"over the lazy"),
        ("binary-miss", binary, b"0123456789abcdef"),
        ("binary-end", binary + b"0123456789abcdef", b"0123456789abcdef"),
        ("needle-32-end", binary + b"0123456789abcdef" * 2, b"0123456789abcdef" * 2),
        ("needle-33-end", binary + b"0123456789abcdef" * 2 + b"!", b"0123456789abcdef" * 2 + b"!"),
        ("needle-33-near-end", binary + tail + b"padding", tail),
        ("needle-33-false-tail", binary + tail + false_tail, tail),
        ("needle-33-tail-miss", binary + false_tail, tail),
        ("long-needle-end", binary + long, long),
        ("long-needle-near-end", binary + long + b"padding", long),
        ("long-needle-tail-miss", binary + long[:1024] + b"\x00" + long[1025:], long),
        ("long-period-7-miss", b"\xff" * 4096, bytes(i % 7 for i in range(2048))),
        ("long-period-8-miss", b"\xff" * 4096, bytes(range(8)) * 256),
        ("long-irregular-miss", b"\xff" * 4096, irregular),
        ("two-byte-miss", b"a" * (1 << 20), b"ab"),
        ("one-byte-miss", b"a" * (1 << 20), b"b"),
        ("periodic-miss", b"a" * (1 << 20), b"a" * 255 + b"b"),
        ("periodic-reverse", b"a" * (1 << 20), b"b" + b"a" * 255),
        ("periodic-middle-miss", b"a" * (1 << 20), b"a" * 127 + b"b" + b"a" * 128),
        ("periodic-hit", b"ab" * (1 << 19), b"ab" * 128),
        ("false-pairs", (b"az" * (1 << 19)), b"az" * 63 + b"bz"),
        ("duplicate-pair-reject", b"\0x\xddz" * (1 << 18), b"\0\0\xdd\xdd\0"),
        ("duplicate-pair-dense", b"\0" * (1 << 20), b"\0\0\xdd\xdd\0"),
        ("near-periodic-miss", triples, near_periodic),
        ("near-periodic-end", triples + near_periodic, near_periodic),
        ("long-needle", text, text[13:2061]),
    ]:
        yield name, haystack, needle


def byteset_cases():
    return [
        ("tiny-two-miss", b"GET /api/items HTTP/1.1", b"\r\n"),
        ("tiny-four-hit", b"GET /api/items HTTP/1.1", b" GET"),
        ("tiny-reverse-hit", b"GET /api/items HTTP/1.1\n", b"\r\n"),
        ("tiny-not-two", b" \t abc", b" \t"),
        ("large-one-miss", b"a" * (1 << 20), b"b"),
        ("large-two-miss", b"a" * (1 << 20), b"bc"),
        ("large-three-miss", b"a" * (1 << 20), b"bc\xff"),
        ("large-four-miss", b"a" * (1 << 20), b"bcde"),
        ("large-not-one-miss", b"a" * (1 << 20), b"a"),
        ("large-not-three-miss", b"a\x80\xff" * (1 << 18), b"a\x80\xff"),
        ("duplicates", b"a" * (1 << 20), b"bbb"),
        ("full-set", bytes(range(256)) * 4096, bytes(range(256))),
        ("empty-set", b"GET /api/items HTTP/1.1", b""),
    ]


def boundary_cases():
    # Both sides of the scalar, 16/32-byte vector, small-search, and unroll cutoffs.
    for size in (0, 1, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 129,
                 255, 256, 257, 1023, 1024, 1025, 1026, 1055, 1056, 1057):
        for pattern in (b"!", b"x!z", b"x" * 16 + b"!" + b"z" * 16):
            data = b"a" * size
            yield f"n{size}-p{len(pattern)}-miss", data, pattern
            if len(pattern) <= size:
                at = (size - len(pattern)) // 2
                yield f"n{size}-p{len(pattern)}-middle", data[:at] + pattern + data[at + len(pattern):], pattern


def run(exe, haystack, needle, mode, iterations, expected):
    result = subprocess.run([str(exe), str(haystack), str(needle), mode, str(iterations)],
                            capture_output=True, text=True, check=True)
    elapsed, checksum = map(int, result.stdout.split())
    assert checksum == (expected + 1) * iterations, (mode, checksum, expected, iterations)
    return elapsed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose-exe", type=Path, help="use an already built baseline")
    parser.add_argument("--baseline-exe", type=Path, help="also time the former goostr implementation")
    parser.add_argument("--save-exe", type=Path, help="retain the Goose executable")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--samples", type=int, help="measured batches (default 5, or 3 for quick)")
    parser.add_argument("--sample-ms", type=int, help="minimum batch time in ms (default 50, or 5 for quick)")
    parser.add_argument("--cc", choices=["clang", "gcc"], default="clang")
    parser.add_argument("--target", choices=["runtime", "baseline", "avx2", "scalar"], default="runtime",
                        help="AVX2 requires a capable CPU; runtime dispatch requires Clang/x86")
    parser.add_argument("--suite", choices=["substring", "byteset", "boundary", "upstream", "records", "quick"], default="substring")
    parser.add_argument("--memchr-checkout", type=Path, help="memchr 2.8.3 checkout for upstream/quick suites (Python 3.11+)")
    parser.add_argument("--record-corpus", type=Path, help="find-memchr's in.gz for --suite records")
    parser.add_argument("--case", action="append", help="case name glob; repeat to select multiple groups")
    parser.add_argument("--modes", nargs="+", choices=SUBSTRING_MODES + BYTESET_MODES + COUNT_MODES + ["records"])
    options = parser.parse_args()
    if options.samples is None:
        options.samples = 3 if options.suite == "quick" else 5
    if options.sample_ms is None:
        options.sample_ms = 5 if options.suite == "quick" else 50
    if options.samples < 3:
        parser.error("--samples must be at least 3")
    if options.sample_ms < 1:
        parser.error("--sample-ms must be positive")
    target_ns = options.sample_ms * 1_000_000
    allowed_modes = BYTESET_MODES if options.suite == "byteset" else SUBSTRING_MODES
    if options.suite in ("upstream", "quick"):
        allowed_modes = SUBSTRING_MODES + COUNT_MODES
    elif options.suite == "records":
        allowed_modes = ["records"]
    modes = options.modes or (COUNT_MODES + ["prepared-find"] if options.suite == "quick" else allowed_modes)
    if any(mode not in allowed_modes for mode in modes):
        parser.error("--modes must match --suite")
    upstream = None
    if options.suite in ("upstream", "quick"):
        if not options.memchr_checkout:
            parser.error(f"--suite {options.suite} requires --memchr-checkout")
        selected, upstream = upstream_cases(options.memchr_checkout)
        if options.suite == "quick":
            selected = [case for case in selected if case[0] in (
                "byterank/binary", "pathological/defeat-simple-vector-alphabet",
                "pathological/rare-repeated-small-match", "subtitles/common/huge-en-that",
                "subtitles/common/huge-en-you", "subtitles/common/huge-zh-that")]
            selected += [case for case in cases() if case[0] in (
                "tiny-hit", "tiny-miss", "needle-33-tail-miss", "long-needle-tail-miss",
                "periodic-miss", "periodic-reverse", "false-pairs", "near-periodic-miss", "near-periodic-end",
                "duplicate-pair-reject", "duplicate-pair-dense")]
            selected += [case for case in boundary_cases() if case[0] in (
                "n64-p3-miss", "n65-p33-middle")]
    elif options.suite == "records":
        if not options.record_corpus:
            parser.error("--suite records requires --record-corpus")
        data = gzip.decompress(options.record_corpus.read_bytes())
        if hashlib.sha256(data).hexdigest() != RECORDS_SHA256:
            parser.error("record corpus differs from find-memchr's published in.gz")
        selected = [("aspell-records", data, b"|")]
        upstream = dict(repository="https://github.com/gsauthof/find-memchr",
                        revision="6b0e99b54c9b60b9aaf615d33437a8139162524f",
                        haystack="in.gz", haystack_sha256=RECORDS_SHA256,
                        model="in-memory newline/pipe prefix offsets; no I/O or output formatting")
    else:
        selected = list({"substring": cases, "byteset": byteset_cases, "boundary": boundary_cases}[options.suite]())
    if options.case:
        selected = [case for case in selected if any(fnmatch.fnmatchcase(case[0], glob) for glob in options.case)]
    if not selected:
        parser.error("no cases matched")
    flags = ["-O3"] + {"runtime": [], "baseline": ["-DGS_SIMD=0"],
                       "avx2": ["-DGS_SIMD=0", "-mavx2"],
                       "scalar": ["-DGS_SIMD=0", "-DGOOSIMD_SCALAR"]}[options.target]
    with tempfile.TemporaryDirectory(prefix="goostr-bench-") as tmp:
        tmp = Path(tmp)
        barrier = tmp / "opaque.o"
        subprocess.run(["clang", "-O3", "-c", str(ROOT / "bench/opaque.c"), "-o", str(barrier)], check=True)
        subprocess.run(["cargo", "rustc", "--locked", "--release", "--manifest-path",
                        str(ROOT / "tests/oracle/Cargo.toml"), "--features", "bench", "--bin", "search-bench",
                        "--", "-C", f"link-arg={barrier}"], check=True,
                       env={**os.environ, "CARGO_PROFILE_RELEASE_OPT_LEVEL": "3"})
        rust = ROOT / "tests/oracle/target/release/search-bench"
        goose = (options.goose_exe or options.save_exe or tmp / "search").resolve()
        if not options.goose_exe:
            cfile = tmp / "search.c"
            # Goose's -O2 is its maximum inlining level, not the C compiler's.
            subprocess.run(["goose", "--standalone", "-O2", "-o", str(cfile),
                            str(ROOT / "bench/search.goose")], check=True)
            libs = ["-lm", "-pthread"] + (["-ldl"] if platform.system() == "Linux" else [])
            subprocess.run([options.cc, *flags, str(cfile), str(barrier), "-o", str(goose), *libs], check=True)
        programs = [("goose", goose), ("bstr", rust)]
        if options.baseline_exe:
            programs.append(("baseline", options.baseline_exe.resolve()))
        rows = []
        for name, data, pattern in selected:
            haystack, needle = tmp / "haystack", tmp / "needle"
            haystack.write_bytes(data)
            needle.write_bytes(pattern)
            for mode in modes:
                if options.suite == "byteset":
                    members = set(pattern)
                    positions = range(len(data) - 1, -1, -1) if mode.startswith("rfind") else range(len(data))
                    expected = next((i for i in positions if (data[i] in members) != ("-not-" in mode)), -1)
                elif mode in COUNT_MODES:
                    expected = data[::-1].count(pattern[::-1]) if mode == "rcount" else data.count(pattern)
                elif mode == "records":
                    expected = sum(line.find(b"|") + 1 for line in data.split(b"\n"))
                else:
                    expected = data.rfind(pattern) if mode.endswith("rfind") else data.find(pattern)
                iterations = {}
                for label, exe in programs:
                    count = 1
                    while True:
                        elapsed = run(exe, haystack, needle, mode, count, expected)
                        if elapsed >= target_ns or count >= 100_000_000:
                            break
                        count *= min(100, max(2, (target_ns * 6 // 5) // max(1, elapsed)))
                    iterations[label] = count
                times = {label: [] for label, _ in programs}
                for sample in range(options.samples):
                    start = sample % len(programs)
                    order = programs[start:] + programs[:start]
                    for label, exe in order:
                        count = iterations[label]
                        times[label].append(run(exe, haystack, needle, mode, count, expected) / count)
                g, r = statistics.median(times["goose"]), statistics.median(times["bstr"])
                row = dict(case=name, mode=mode, haystack=len(data), needle=len(pattern),
                           sha256=hashlib.sha256(data + pattern).hexdigest(),
                           expected=expected, goose_ns=g, bstr_ns=r, ratio=g/r,
                           iterations=iterations, samples=times)
                if options.baseline_exe:
                    row["baseline_ns"] = statistics.median(times["baseline"])
                    row["baseline_ratio"] = g / row["baseline_ns"]
                rows.append(row)
                print(f"{name:20} {mode:6} Goose {g:12.1f} ns  bstr {r:12.1f} ns  {g/r:7.2f}x", flush=True)
        options.output.parent.mkdir(parents=True, exist_ok=True)
        versions = {}
        for label, command in (("goose", ["goose", "version"]), ("rustc", ["rustc", "--version"]),
                               ("clang", ["clang", "--version"]), ("gcc", ["gcc", "--version"])):
            result = subprocess.run(command, capture_output=True, text=True, check=True)
            versions[label] = (result.stdout + result.stderr).strip()
        cpu = platform.processor()
        if platform.system() == "Darwin":
            cpu = subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip()
        elif platform.system() == "Linux":
            cpu = next((line.split(":", 1)[1].strip() for line in Path("/proc/cpuinfo").read_text().splitlines()
                        if line.startswith("model name")), cpu)
        metadata = dict(platform=platform.platform(), machine=platform.machine(), cpu=cpu, versions=versions,
                        timestamp_utc=datetime.now(timezone.utc).isoformat(),
                        goose_sha256=hashlib.sha256(Path(goose).read_bytes()).hexdigest(),
                        bstr_sha256=hashlib.sha256(rust.read_bytes()).hexdigest(),
                        bstr="1.13.1", memchr="2.8.3", goose_flags=None if options.goose_exe else flags,
                        cc=None if options.goose_exe else options.cc,
                        target=None if options.goose_exe else options.target, rust_profile="release",
                        rust_opt_level="3",
                        suite=options.suite, calibration_target_ms=options.sample_ms, samples=options.samples,
                        prebuilt_goose=bool(options.goose_exe), warmup_passes=1,
                        scheduling=(f"CPU affinity {sorted(os.sched_getaffinity(0))}"
                                    if hasattr(os, "sched_getaffinity") else "user-initiated QoS on macOS"),
                        checkout_sources={path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
                                 for path in ("goostr.goose", "search.goose", "goostr.build", "src/dispatch.h", "bench/search.goose",
                                              "bench/opaque.c", "tests/oracle/src/bin/search-bench.rs")})
        if options.baseline_exe:
            metadata["baseline_sha256"] = hashlib.sha256(options.baseline_exe.read_bytes()).hexdigest()
        if upstream:
            metadata["upstream"] = upstream
        options.output.write_text(json.dumps(dict(environment=metadata, results=rows), indent=2) + "\n")


if __name__ == "__main__":
    main()
