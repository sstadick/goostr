#!/usr/bin/env python3
"""Repeatable bstr comparison; timings exclude input I/O and process startup."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import statistics
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SUBSTRING_MODES = ["find", "rfind", "prepared-find", "prepared-rfind"]
BYTESET_MODES = ["find-set", "rfind-set", "find-not-set", "rfind-not-set"]


def cases():
    rng = random.Random(1731)
    text = (b"The quick brown fox jumps over the lazy dog. Byte strings keep arbitrary data.\n" * 14000)[:1 << 20]
    binary = rng.randbytes(1 << 20)
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
        ("two-byte-miss", b"a" * (1 << 20), b"ab"),
        ("one-byte-miss", b"a" * (1 << 20), b"b"),
        ("periodic-miss", b"a" * (1 << 20), b"a" * 255 + b"b"),
        ("periodic-reverse", b"a" * (1 << 20), b"b" + b"a" * 255),
        ("periodic-hit", b"ab" * (1 << 19), b"ab" * 128),
        ("false-pairs", (b"az" * (1 << 19)), b"az" * 63 + b"bz"),
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
    parser.add_argument("--samples", type=int, default=5)
    parser.add_argument("--suite", choices=["substring", "byteset"], default="substring")
    parser.add_argument("--modes", nargs="+", choices=SUBSTRING_MODES + BYTESET_MODES)
    options = parser.parse_args()
    if options.samples < 3:
        parser.error("--samples must be at least 3")
    allowed_modes = BYTESET_MODES if options.suite == "byteset" else SUBSTRING_MODES
    modes = options.modes or allowed_modes
    if any(mode not in allowed_modes for mode in modes):
        parser.error("--modes must match --suite")
    with tempfile.TemporaryDirectory(prefix="goostr-bench-") as tmp:
        tmp = Path(tmp)
        barrier = tmp / "opaque.o"
        subprocess.run(["clang", "-O2", "-c", str(ROOT / "bench/opaque.c"), "-o", str(barrier)], check=True)
        subprocess.run(["cargo", "rustc", "--locked", "--release", "--manifest-path",
                        str(ROOT / "tests/oracle/Cargo.toml"), "--features", "bench", "--bin", "search-bench",
                        "--", "-C", f"link-arg={barrier}"], check=True)
        rust = ROOT / "tests/oracle/target/release/search-bench"
        goose = (options.goose_exe or options.save_exe or tmp / "search").resolve()
        if not options.goose_exe:
            # Goose v2026.3's native-package cache omits optimization/debug
            # flags. A fresh home prevents reusing -O0 objects from tests.
            env = dict(os.environ, GOOSE_HOME=str(tmp / "goose-home"))
            subprocess.run(["goose", "build", str(ROOT / "bench/search.goose"), "-O2", "-v", "-o", str(goose)],
                           env=env, check=True)
        programs = [("goose", goose), ("bstr", rust)]
        if options.baseline_exe:
            programs.append(("baseline", options.baseline_exe.resolve()))
        rows = []
        for name, data, pattern in (byteset_cases() if options.suite == "byteset" else cases()):
            haystack, needle = tmp / "haystack", tmp / "needle"
            haystack.write_bytes(data)
            needle.write_bytes(pattern)
            for mode in modes:
                if options.suite == "byteset":
                    members = set(pattern)
                    positions = range(len(data) - 1, -1, -1) if mode.startswith("rfind") else range(len(data))
                    expected = next((i for i in positions if (data[i] in members) != ("-not-" in mode)), -1)
                else:
                    expected = data.rfind(pattern) if mode.endswith("rfind") else data.find(pattern)
                iterations = {}
                for label, exe in programs:
                    count = 1
                    while True:
                        elapsed = run(exe, haystack, needle, mode, count, expected)
                        if elapsed >= 50_000_000 or count >= 100_000_000:
                            break
                        count *= min(100, max(2, 60_000_000 // max(1, elapsed)))
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
                               ("clang", ["clang", "--version"])):
            result = subprocess.run(command, capture_output=True, text=True, check=True)
            versions[label] = (result.stdout + result.stderr).strip()
        cpu = platform.processor()
        if platform.system() == "Darwin":
            cpu = subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip()
        metadata = dict(platform=platform.platform(), machine=platform.machine(), cpu=cpu, versions=versions,
                        timestamp_utc=datetime.now(timezone.utc).isoformat(),
                        goose_sha256=hashlib.sha256(Path(goose).read_bytes()).hexdigest(),
                        bstr_sha256=hashlib.sha256(rust.read_bytes()).hexdigest(),
                        bstr="1.13.1", memchr="2.8.3", goose_flags="-O2", rust_profile="release",
                        suite=options.suite, calibration_target_ms=50, samples=options.samples,
                        prebuilt_goose=bool(options.goose_exe), warmup_passes=1,
                        scheduling=(f"CPU affinity {sorted(os.sched_getaffinity(0))}"
                                    if hasattr(os, "sched_getaffinity") else "user-initiated QoS on macOS"),
                        checkout_sources={path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
                                 for path in ("goostr.goose", "search.goose", "goostr.build", "bench/search.goose",
                                              "bench/opaque.c", "tests/oracle/src/bin/search-bench.rs")})
        if options.baseline_exe:
            metadata["baseline_sha256"] = hashlib.sha256(options.baseline_exe.read_bytes()).hexdigest()
        options.output.write_text(json.dumps(dict(environment=metadata, results=rows), indent=2) + "\n")


if __name__ == "__main__":
    main()
