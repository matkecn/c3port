# c3port

A small TCP connect port scanner written in [C3](https://c3-lang.org).

`c3port` resolves a host once, then attempts a non-blocking TCP connect to each
requested port and reports which ones accepted a connection. It is deliberately
small: one file per concern, no dependencies beyond the C3 standard library, and
a test suite for the parts where a mistake is silent.

```console
$ c3port 127.0.0.1 -p 22,80,443,3333 -c -v

c3port 0.1.0 - scanning 127.0.0.1
ports: 22,80,443,3333 (4)   timeout: 1000ms   family: auto   states: open+closed

resolved 1 address:
  127.0.0.1

PORT        STATE     SERVICE     ADDRESS                      TIME
22/tcp      closed    ssh         127.0.0.1                      0ms  [code 61]
80/tcp      open      http        127.0.0.1                      0ms
443/tcp      closed    https      127.0.0.1                      0ms  [code 61]
3333/tcp    open      -           127.0.0.1                      0ms

Scanned 4 port(s) across 1 address(es) in 223us
2 open, 2 closed, 0 filtered, 0 error
```

## Requirements

- The [C3 compiler](https://c3-lang.org) `0.8.4` or newer (`c3c` on your `PATH`).

## Build and test

```console
c3c build      # produces build/c3port
c3c test       # builds and runs the unit tests
```

## Usage

```text
c3port <host> [-p <ports>] [options]
```

| Option | Meaning |
| --- | --- |
| `-p`, `--ports <spec>` | which ports to scan (default: `top`) |
| `-t`, `--timeout <ms>` | per port connect timeout in ms (default: `1000`) |
| `-4` | resolve to IPv4 addresses only |
| `-6` | resolve to IPv6 addresses only |
| `-a`, `--all-states` | show closed, filtered and error ports too |
| `-c`, `--closed` | also show closed ports |
| `-f`, `--filtered` | also show filtered ports |
| `-v`, `--verbose` | add timing and error detail per port |
| `-h`, `--help` | show help |
| `--version` | show the version |

`--long=value` is accepted as well as `--long value`, so
`c3port host --ports=22,80` works.

### Port spec grammar

| Form | Meaning |
| --- | --- |
| `22` | a single port |
| `1-1024` | an inclusive range |
| `8000-` | 8000 up to the last port |
| `80,443,8080` | a comma separated mix of the above |
| `top` | the 100 most commonly used ports |
| `top100` | the first 100 entries of the service table |
| `all` | every port from 1 to 65535 |

Whitespace around any of these is ignored, so ` 1 - 3 ` is a valid range.
Duplicates collapse and the order you wrote is the order that gets scanned, so
`-p 443,80,443` tries 443 then 80, once each. A count above the size of the
service table (`top100000`) clamps to the whole table rather than failing.

### Port states

| State | Meaning |
| --- | --- |
| `open` | the connect completed, something is listening |
| `closed` | the host actively refused, so the port is almost certainly unused |
| `filtered` | the attempt timed out or was unreachable, so a firewall dropped it |
| `error` | the probe itself failed for some other reason |

Only `open` is shown by default. The rest are opt in with `-c` / `-f` / `-a`,
which is also what keeps a wide scan cheap: filtered results are counted but
not stored unless asked for.

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | the scan ran and found at least one open port |
| `1` | the scan ran and found no open ports, or the host did not resolve |
| `2` | the command line or port spec was invalid |

## Design notes

A few decisions that are not obvious from the code alone:

**The host is resolved once per scan, not once per port.** `getaddrinfo` is
called with port 0, and each probe copies the returned `sockaddr` and overwrites
the two port bytes. Re-resolving per port would mean a DNS lookup per port,
which dominates the runtime of a wide scan.

**Scanning is sequential and single threaded.** This keeps output stable and
easy to reason about. Concurrency would be a change confined to
`src/scanner.c3`.

**State is modelled as data, not as C3 faults.** A port that is closed is an
ordinary result, not a program failure, so `probe::PortState` is a plain enum
and `ports::ParseError` is returned inside a `PortSet`. This keeps the output
path free of fault handling and makes both straightforward to unit test.

**`String?` is avoided for "not found".** `String` is a struct, and a zero
initialised `String?` is indistinguishable from a present empty string, so an
optional return cannot reliably express absence. Lookups such as
`services::name_of` use a `bool` return with an out parameter instead.

**Addresses are formatted by hand rather than through `inet_ntop`.** That keeps
the module free of any libc dependency, at the cost of implementing the RFC 5952
rules for IPv6 zero-run compression. `test/target_test.c3` pins those rules
down.

**Note for C3 0.8.x:** range slices are inclusive at both ends, so `s[0..4]` on
a five character string is the whole string. `s[..]` is the open ended form.

## Layout

| File | Responsibility |
| --- | --- |
| `src/main.c3` | entry point, exit codes, wiring only |
| `src/cli.c3` | argument parsing, help text |
| `src/ports.c3` | port spec parsing and deduplication, no networking |
| `src/services.c3` | the port to service name table |
| `src/target.c3` | resolution, endpoints, sockaddr patching, address labels |
| `src/probe.c3` | one non-blocking connect, and classifying the result |
| `src/scanner.c3` | orchestration, counters, display filters |
| `src/report.c3` | terminal output |

The dependency direction is one way: `main` calls into the modules, `scanner`
uses `probe` / `target` / `services`, and `ports` and `services` depend on
nothing but the standard library. Nothing below `scanner` knows about
formatting, and nothing but `target` knows about sockets, so each piece can be
changed or tested on its own.

## Extending it

**Add a service name.** Append to the `KNOWN` table in `src/services.c3`. It
must stay sorted by port, since `name_of` binary searches it;
`test/services_test.c3` fails if it does not.

**Add a port spec form.** Add a keyword branch in `ports::parse` and a parser
that returns a `ParseError`. Add the cases to `ports::describe` at the same
time; the tests check no error is left undescribed.

**Add a probe method.** UDP or ICMP would be a new state in `probe::PortState`
plus a `probe::probe_*` function, then a `case` in `Report.wants` and in
`scanner::count`. C3 will point at the switch that needs updating.

**Add an output format.** `src/report.c3` only reads the `Report` struct, so a
JSON or CSV writer is a new function there that needs nothing from the scanner.

**Parallelise.** `scanner::run` walks ports and addresses in a nested loop over
materialised endpoints. Fanning the inner loop out across workers would not
require changes to any other file.

## Legal

`LICENSE` is empty. Add your licence before publishing.
