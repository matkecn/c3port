<div align="center">

# c3port

**A small, fast TCP connect port scanner written in [C3](https://c3-lang.org).**

Resolve a host once. Connect to every port you asked for. See what is listening.

[![CI](https://github.com/matkecn/c3port/actions/workflows/ci.yml/badge.svg)](https://github.com/matkecn/c3port/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![C3](https://img.shields.io/badge/built%20with-C3-4a90d9.svg)](https://c3-lang.org)
[![C3 Version](https://img.shields.io/badge/c3c-%3E%3D%200.8.4-blue.svg)](https://c3-lang.org)
[![Tests](https://img.shields.io/badge/tests-34%20passed-success.svg)](test)
[![Lines of Code](https://img.shields.io/badge/src-1.7k%20lines-informational.svg)](src)
[![Dependencies](https://img.shields.io/badge/3rd--party%20deps-0-success.svg)](project.json)
[![Platforms](https://img.shields.io/badge/tested%20on-Linux%20%7C%20macOS-8da0cb.svg)](https://c3-lang.org)
[![Last Commit](https://img.shields.io/github/last-commit/matkecn/c3port)](https://github.com/matkecn/c3port/commits/main)
[![License](https://img.shields.io/github/license/matkecn/c3port)](LICENSE)

[Features](#-features) · [Install](#-getting-started) · [Usage](#-usage) · [Examples](#-examples) ·
[Architecture](#-architecture) · [Extending](#-extending-it) · [Contributing](#-contributing)

</div>

---

## 📖 About

`c3port` is a deliberately small port scanner. It resolves a host **once**,
then attempts a non-blocking TCP connect to each requested port and reports
which ones accepted the connection.

It does one thing and does it honestly:

<table>
<tr>
<td width="50%">

**✅ What it does well**

- 🔍 Resolves the host **once per scan**, not once per port
- ⚡ Non-blocking connects with a per-port timeout
- 🧩 Clean module boundaries, one file per concern
- 📝 **34 unit tests** on the logic where a mistake is silent
- 🪶 **Zero dependencies** beyond the C3 standard library
- 🧮 Rich port spec: `1-1024`, `80,443,8080`, `top`, `all`
- 🌐 IPv4 and IPv6, with `-4` / `-6` filters
- 🎯 Four-state result model, not a boolean
- 🚪 Meaningful exit codes for scripting

</td>
<td width="50%">

**🚫 What it does not do**

- ❌ No `SYN` scan / raw sockets / root required
- ❌ No UDP or ICMP probing *(see [Extending](#-extending-it))*
- ❌ No service version fingerprinting
- ❌ No XML / HTML / Nmap output
- ❌ No scan persistence or resume
- ❌ No multithreading *(see [Extending](#-extending-it))*

**This is a connect scan, not a port scanner that pretends to be Nmap.**
It is here to be read, modified, and trusted.

</td>
</tr>
</table>

---

## ✨ Features

| | Feature | Detail |
| :-: | --- | --- |
| ⚡ | **Resolve once** | One `getaddrinfo` per scan. The two port bytes are patched into the returned `sockaddr`, so a 65 000-port scan is one DNS lookup, not 65 000. |
| 🧵 | **Non-blocking probes** | Each connect is non-blocking with a poll timeout, so a filtered port costs its timeout instead of hanging the scan. |
| 🧭 | **Precise port specs** | `22`, `1-1024`, `8000-`, `80,443,8080`, `top`, `top1000`, `all`. Whitespace tolerant, duplicates collapsed, your order preserved. |
| 🌐 | **IPv4 + IPv6** | Dual-stack by default, with `-4` and `-6` to restrict. Addresses are formatted to RFC 5952. |
| 🎯 | **Four honest states** | `open`, `closed`, `filtered`, `error` are distinguished instead of lumped into "up or down". |
| 🧪 | **34 unit tests** | Covering the parser, the service table's binary-search invariants, and IPv6 rendering. |
| 🪶 | **No dependencies** | Just the C3 standard library. Nothing to audit, nothing to update. |
| 🚪 | **Script-friendly** | Exit `0` = found something, `1` = nothing found, `2` = bad input. |

---

## 🚀 Getting Started

### 📋 Requirements

- The [C3 compiler](https://c3-lang.org) **0.8.4 or newer**, with `c3c` on your `PATH`
- A C toolchain (`gcc` / `clang` / MSVC) — C3 uses it as the linker backend

<details>
<summary>Installing the C3 compiler</summary>

**macOS (Homebrew)**

```bash
brew install c3c
```

**Linux — prebuilt static binary (self-contained)**

```bash
curl -fsSL https://github.com/c3lang/c3c/releases/latest/download/c3-linux-static.tar.gz \
  | sudo tar -xz -C /opt
export PATH="/opt/c3:$PATH"
```

**Arch**

```bash
sudo pacman -S c3c
```

**Any platform — official install script**

```bash
curl -fsSL https://raw.githubusercontent.com/c3lang/c3c/refs/heads/master/install/install.sh | bash
```

**From source**

```bash
sudo apt-get install cmake git clang libcurl4-openssl-dev
git clone https://github.com/c3lang/c3c.git && cd c3c
cmake -B build -S . -DC3_FETCH_LLVM=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

</details>

### 🔨 Build and test

```bash
git clone https://github.com/matkecn/c3port.git
cd c3port

c3c build      # produces build/c3port
c3c test       # builds and runs the unit tests
```

<details>
<summary>Expected test output</summary>

```text
Test Result: PASSED: 34 passed, 0 failed, 0 skipped.
Program linked to executable 'build/testrun'.
Launching ./build/testrun
Program completed with exit code 0.
```

</details>

---

## 💻 Usage

```text
c3port <host> [-p <ports>] [options]
```

| Option | Description | Default |
| --- | --- | --- |
| `-p`, `--ports <spec>` | Which ports to scan | `top` |
| `-t`, `--timeout <ms>` | Per-port connect timeout, in milliseconds | `1000` |
| `-4` | Resolve to IPv4 addresses only | |
| `-6` | Resolve to IPv6 addresses only | |
| `-a`, `--all-states` | Show closed, filtered **and** error ports too | |
| `-c`, `--closed` | Also show closed ports | |
| `-f`, `--filtered` | Also show filtered ports | |
| `-v`, `--verbose` | Add per-port timing and error detail | |
| `-h`, `--help` | Show help | |
| `--version` | Show the version | |

`--long=value` works as well as `--long value`, so `c3port host --ports=22,80` is fine.

> [!TIP]
> Only `open` ports are shown by default. That is also what keeps a wide scan
> cheap: filtered results are **counted** but not **stored** unless you ask for them.

---

## 🎯 Examples

### A typical scan

```console
$ c3port 127.0.0.1 -p 22,18099,3333 -c -v

c3port 0.1.0 - scanning 127.0.0.1
ports: 22,18099,3333 (3)   timeout: 1000ms   family: auto   states: open+closed

resolved 1 address:
  127.0.0.1

PORT        STATE     SERVICE          ADDRESS                      TIME
22/tcp      closed    ssh              127.0.0.1                      0ms  [code 61]
18099/tcp   open      -                127.0.0.1                      0ms
3333/tcp    closed    -                127.0.0.1                      0ms  [code 61]

Scanned 3 port(s) across 1 address(es) in 817us
1 open, 2 closed, 0 filtered, 0 error
```

### The 100 most common ports

```bash
c3port scanme.example
```

### A web server range

```bash
c3port 10.0.0.5 -p 1-1024 --closed
```

### Everything, with a short timeout

```bash
c3port 10.0.0.5 -p all -t 200 --all-states
```

### IPv6 only

```bash
c3port -6 scanme.example -p 22,80,443
```

### In a script

```bash
# Exit 0 means "something answered", so this is safe under set -e
if c3port 10.0.0.5 -p 443 >/dev/null; then
    echo "HTTPS is up"
else
    echo "nothing open on 443"
fi
```

---

## 📖 Port spec grammar

| Form | Meaning |
| --- | --- |
| `22` | A single port |
| `1-1024` | An **inclusive** range |
| `8000-` | 8000 up to the last port (65535) |
| `80,443,8080` | A comma-separated mix of the above |
| `top` | The 100 most commonly used ports |
| `top<n>` | The first `<n>` entries of the service table |
| `all` | Every port from 1 to 65535 |

```bash
c3port host -p "443,80,443"   # 2 ports: 443 then 80, order preserved
c3port host -p " 1 - 3 "      # whitespace is ignored
c3port host -p top100000      # clamps to the whole table, no error
```

> [!NOTE]
> Duplicates collapse, and **the order you write is the order that gets scanned.**
> A count larger than the service table clamps rather than failing.

---

## 🚦 Port states

| State | Icon | Meaning |
| --- | :-: | --- |
| `open` | 🟢 | The connect completed — something is listening. |
| `closed` | 🔴 | The host actively refused. The port is almost certainly unused. |
| `filtered` | 🟡 | Timed out or unreachable. A firewall probably dropped it. |
| `error` | ⚪ | The probe itself failed for some other reason. |

Only `open` is shown by default. Reveal the rest with `-c` (closed), `-f`
(filtered) or `-a` (everything).

<details>
<summary>What a filtered port looks like</summary>

```console
$ c3port 10.255.255.1 -p 81 -t 300 -a

PORT        STATE     SERVICE          ADDRESS
81/tcp      filtered  http-alt         10.255.255.1

Scanned 1 port(s) across 1 address(es) in 301ms
0 open, 0 closed, 1 filtered, 0 error
```

</details>

---

## 🚪 Exit codes

| Code | Meaning |
| --- | --- |
| `0` | The scan ran and found **at least one open port** |
| `1` | The scan ran and found **no open ports**, or the host did not resolve |
| `2` | The command line or port spec was invalid |

```bash
c3port host -p 22-80 ; echo $?   # 0 found · 1 nothing · 2 bad input
```

---

## 🏗️ Architecture

```text
                    ┌──────────────┐
                    │  src/main.c3 │   entry point, exit codes
                    └──────┬───────┘
                           │
      ┌────────────────────┼────────────────────┐
      │                    │                    │
┌─────▼──────┐      ┌──────▼───────┐      ┌─────▼──────┐
│ src/cli.c3 │      │ src/ports.c3 │      │            │
│  arguments │      │  port specs  │      │            │
└─────┬──────┘      └──────┬───────┘      │            │
      │                    │              │            │
      │              ┌─────▼──────┐       │            │
      │              │src/services│       │            │
      │              │  .c3 table │       │            │
      │              └─────┬──────┘       │            │
      │                    │              │            │
      │      ┌─────────────┴──────────┐   │            │
      │      │                        │   │            │
┌─────▼──────▼───┐   ┌─────────┐  ┌────▼────┐  ┌─────▼─────┐
│ src/scanner.c3 │◄──┤  probe  │  │ target  │  │  report   │
│ orchestration  │   │ connect │  │ resolve │  │  output   │
└────────────────┘   └────┬────┘  └────┬────┘  └───────────┘
                          │            │
                          └────────────┘
```

The dependency direction is **one way**. `main` calls into the modules.
`scanner` uses `probe`, `target` and `services`; `report` only *reads* the
`Report` struct; `probe` uses `target` for the endpoint it connects to. At the
bottom, `services` depends on nothing at all, and `ports` depends only on
`services`, because the `top` preset is defined as a prefix of that table.

Nothing below `scanner` knows about formatting. Only `probe` and `target`
know about sockets. So every piece can be changed — or tested — on its own.

| File | Responsibility | Depends on |
| --- | --- | --- |
| `src/main.c3` | Entry point, exit codes, wiring only | `cli`, `ports`, `scanner`, `target`, `report` |
| `src/cli.c3` | Argument parsing, help text | `services` |
| `src/ports.c3` | Port spec parsing and dedup — **no networking** | `services` |
| `src/services.c3` | The port → service name table | *nothing* |
| `src/target.c3` | Resolution, endpoints, sockaddr patching, address labels | — |
| `src/probe.c3` | One non-blocking connect, and classifying the result | `target` |
| `src/scanner.c3` | Orchestration, counters, display filters | `probe`, `target`, `services` |
| `src/report.c3` | Terminal output | `cli`, `probe`, `scanner` |

---

## 🧠 Design notes

A few decisions that are not obvious from the code alone:

<details>
<summary><b>💡 The host is resolved once per scan, not once per port</b></summary>

`getaddrinfo` is called with port `0`, and each probe copies the returned
`sockaddr` and overwrites the two port bytes. Re-resolving per port would mean
a DNS lookup per port, which dominates the runtime of a wide scan — and DNS
servers rate-limit.

</details>

<details>
<summary><b>🧵 Scanning is sequential and single-threaded</b></summary>

This keeps output stable and easy to reason about. A wide scan is I/O-bound on
timeouts, so concurrency is the obvious next win — and it is a change confined
to `src/scanner.c3`. See [Extending](#-extending-it).

</details>

<details>
<summary><b>🎯 State is modelled as data, not as C3 faults</b></summary>

A port that is closed is an ordinary result, not a program failure. So
`probe::PortState` is a plain enum, and `ports::ParseError` is returned inside
a `PortSet`. This keeps the output path free of fault handling and makes both
straightforward to unit test.

</details>

<details>
<summary><b>📝 <code>String?</code> is avoided for "not found"</b></summary>

`String` is a struct, and a zero-initialised `String?` is indistinguishable
from a present empty string — so an optional return cannot reliably express
absence. Lookups like `services::name_of` return a `bool` and fill an out
parameter instead.

</details>

<details>
<summary><b>🌐 Addresses are formatted by hand, not via <code>inet_ntop</code></b></summary>

That keeps the module free of any libc dependency, at the cost of implementing
the RFC 5952 rules for IPv6 zero-run compression. `test/target_test.c3` pins
those rules down: leading run, trailing run, two equal-length runs, and a lone
zero group that must *not* be compressed.

</details>

<details>
<summary><b>⚠️ Note for C3 0.8.x: range slices are inclusive</b></summary>

Both ends are included, so `s[0..4]` on a five-character string is the whole
string. `s[..]` is the open-ended form. Getting this wrong silently drops or
duplicates a character rather than failing to compile.

</details>

---

## 🧪 Tests

```bash
c3c test
```

| File | Tests | Covers |
| --- | :-: | --- |
| `test/ports_test.c3` | 16 | Every spec form, every rejection, dedup, growth past initial capacity |
| `test/target_test.c3` | 11 | IPv4/IPv6 labels, RFC 5952 compression, sockaddr port byte order |
| `test/services_test.c3` | 7 | Sortedness, duplicate-freedom, full-table round trip |

The tests concentrate on the places where a mistake is **silent**: the parser
turns untrusted text into a list of integers, and a wrong answer there just
quietly probes the wrong ports. `name_of` binary searches, so an unsorted table
returns the wrong name without crashing. Both are asserted, not assumed.

---

## 🧩 Extending it

<details>
<summary><b>➕ Add a service name</b></summary>

Append to the `KNOWN` table in `src/services.c3`. It **must stay sorted by
port**, because `name_of` binary searches it — `test/services_test.c3` fails
if it does not.

</details>

<details>
<summary><b>➕ Add a port spec form</b></summary>

Add a keyword branch in `ports::parse` and a parser that returns a
`ParseError`. Add the case to `ports::describe` at the same time;
`test_describe_covers_every_error` fails if a new error goes undescribed.

</details>

<details>
<summary><b>➕ Add a probe method (UDP, ICMP)</b></summary>

A new state in `probe::PortState`, plus a new `probe::probe_*` entry point
alongside the existing `probe::probe`, then a `case` in `Report.wants` and in
`scanner::count`. C3 will point at the switch that needs updating.

</details>

<details>
<summary><b>➕ Add an output format (JSON, CSV)</b></summary>

`src/report.c3` only *reads* the `Report` struct, so a new writer there needs
nothing from the scanner. This is the main reason the data model is kept
separate from presentation.

</details>

<details>
<summary><b>⚡ Parallelise</b></summary>

`scanner::run` walks ports and addresses in a nested loop over materialised
endpoints. Fanning the inner loop out across workers would not require changes
to any other file.

</details>

---

## 🤝 Contributing

Contributions are welcome.

1. **Open an issue** describing what you want to change and why.
2. **Fork** and create a branch: `git checkout -b my-change`.
3. **Keep it honest.** If you change behaviour, update `README.md` and the
   `--help` text in the same commit.
4. **Add a test** if the change touches parsing, rendering, or the service
   table. Those are the parts where a bug is silent.
5. **Run the suite:** `c3c build && c3c test`.
6. **Open a pull request** and let CI confirm it.

> [!IMPORTANT]
> `README.md` is not a decoration. Every number, sample command, and exit code
> in it is checked against real output. If you change the program, change the
> README in the same commit.

---

## 📄 License

MIT © 2026 м — see [LICENSE](LICENSE).

<div align="center">
<sub>Built with ❤️ in C3 · <a href="https://c3-lang.org">c3-lang.org</a></sub>
</div>
