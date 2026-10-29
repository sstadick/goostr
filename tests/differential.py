#!/usr/bin/env python3
"""Compare public operations with Rust bstr. Requires Goose, Cargo and Python 3."""
import itertools
from pathlib import Path
import random
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def corpus():
    # Every one- and two-byte input, then UTF-8 boundaries and longer data.
    yield b""
    for n in (1, 2):
        for values in itertools.product(range(256), repeat=n):
            yield bytes(values)
    for cp in (0, 0x7F, 0x80, 0x7FF, 0x800, 0xD7FF, 0xE000, 0xFFFF,
               0x10000, 0x10FFFF, 0xFFFD, 0x1F986):
        encoded = chr(cp).encode()
        for n in range(len(encoded) + 1):
            yield encoded[:n]
            yield b"a" + encoded[:n] + b"!"
            yield encoded[:n] + b"\xFF"
    for cp in (9, 10, 11, 12, 13, 32, 0x85, 0xA0, 0x1680, *range(0x2000, 0x200C),
               0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF):
        space = chr(cp).encode()
        yield space + b"a" + space + b"\xFFb" + space
    for data in (b"ababa", b"aaaaaaa", b"a\r\n\nb\rc\n", b"\n", b"\r\n",
                 b"\xED\xA0\x80", b"\xF4\x90\x80\x80", b"\xF0\x80\x80\x80"):
        # Repeat so every needle/limit choice below is exercised.
        yield from itertools.repeat(data, 30)
    rng = random.Random(0xB57)
    for _ in range(4000):
        alphabet = rng.choice([bytes(range(256)), b"ab\0\r\n", "aé雪🦆 　".encode()])
        yield bytes(rng.choice(alphabet) for _ in range(rng.randrange(3, 100)))
    for _ in range(1000):
        yield "".join(chr(rng.choice([0x20, 0xE9, 0x96EA, 0x1F986, 0xFFFD, 0xA0]))
                      for _ in range(rng.randrange(1, 30))).encode()


def main():
    subprocess.run(["cargo", "build", "--locked", "--quiet", "--manifest-path",
                    str(ROOT / "tests/oracle/Cargo.toml")], check=True)
    cases = []
    for i, data in enumerate(corpus()):
        needles = [b"", b"a", b"ab", b"aba", data[:2], data[len(data) // 2:]]
        cases.append(f"{data.hex()}|{needles[i % len(needles)].hex()}|{i % 5}")
    inputs = ("\n".join(cases) + "\n").encode()
    oracle = subprocess.run([str(ROOT / "tests/oracle/target/debug/goostr-oracle")],
                            input=inputs, stdout=subprocess.PIPE, check=True).stdout.splitlines()
    with tempfile.TemporaryDirectory(prefix="goostr-test-") as temp:
        exe = str(Path(temp) / "snapshot")
        subprocess.run(["goose", "build", str(ROOT / "tests/snapshot.goose"),
                        "--debug", "-O2", "-o", exe], check=True)
        actual = subprocess.run([exe], input=inputs, stdout=subprocess.PIPE, check=True).stdout.splitlines()
    assert len(actual) == len(oracle) == len(cases), "wrong number of snapshots"
    for i, (got, want) in enumerate(zip(actual, oracle)):
        if got != want:
            raise AssertionError(f"case {i}: {cases[i]}\nGoose: {got!r}\n bstr: {want!r}")
    print(f"{len(cases):,} differential cases matched bstr 1.13.1")


if __name__ == "__main__":
    main()
