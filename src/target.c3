<*
 Turning a user supplied host into concrete socket endpoints.

 A "host" can resolve to more than one address (a name like `localhost`
 usually gives both 127.0.0.1 and ::1, and a public name can give several
 A records). The scanner probes every resolved address, so this module owns
 the getaddrinfo result list for the lifetime of a scan.

 The important trick implemented here: resolve the host ONCE with port 0,
 then for each port under test just overwrite the two port bytes in a copy
 of the returned sockaddr. Re-resolving per port would mean one DNS lookup
 per port, which dominates the runtime of a scan.
*>
module c3port::target;

import std::io, std::net, std::net::os;

<*
 Byte offset of the 16-bit port inside a `sockaddr_in` / `sockaddr_in6`,
 in network (big endian) order.

 Layout:  family at 0..1, port at 2..3, then the address. That holds for
 AF_INET on every supported platform and for AF_INET6 (where bytes 4..7 are
 flowinfo and the address starts at 8). The standard library's own
 `net::decode_port` relies on the same offset.
*>
const usz SOCKADDR_PORT_OFFSET = 2;

const usz SOCKADDR_MAX = 128;
const usz LABEL_MAX = 64;

const char[16] HEX_DIGITS = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' };

<*
 One resolved address, pre-shaped so that probing many ports against it is
 just a two byte patch. Holds no heap memory.
*>
struct Endpoint
{
	os::AIFamily family;
	os::AISockType socktype;
	os::AIProtocol protocol;
	net::os::Socklen_t addrlen;
	char[SOCKADDR_MAX] addr;   // sockaddr template, port field owned by the probe
	char[LABEL_MAX] label;     // NUL terminated printable form of the address
}

<*
 Owns the `getaddrinfo` result chain. Free with `close`.
*>
struct Resolution
{
	os::AddrInfo* list;
	usz count;
}

<*
 Resolve `host` to a chain of endpoints.

 @param host : "a hostname, IPv4 literal or IPv6 literal"
 @param version : "which address family to ask for"
 @return "an owned resolution, or a fault if the name does not resolve"
*>
fn Resolution? resolve(String host, net::IpProtocol version)
{
	// Port 0: we only want the address here, the port is patched per probe.
	os::AddrInfo* list = net::addrinfo(host, 0, version.ai_family, os::SOCK_STREAM)!;

	usz count = 0;
	for (os::AddrInfo* node = list; node; node = node.ai_next) count++;

	return { .list = list, .count = count };
}

fn void Resolution.close(&self)
{
	if (self.list)
	{
		os::freeaddrinfo(self.list);
		self.list = null;
		self.count = 0;
	}
}

<*
 Turn one node of the resolution chain into a probe ready endpoint.

 @param ai : "a node from the chain returned by `net::addrinfo`"
 @return "an endpoint whose `addr` has a zeroed port field"
*>
fn Endpoint make_endpoint(os::AddrInfo* ai)
{
	assert(ai.ai_addrlen > 0 && ai.ai_addrlen <= SOCKADDR_MAX,
		"unexpected sockaddr length %d", ai.ai_addrlen);

	Endpoint ep;
	ep.family = ai.ai_family;
	ep.socktype = ai.ai_socktype;
	ep.protocol = ai.ai_protocol;
	ep.addrlen = ai.ai_addrlen;

	// Zero the whole buffer so the unused tail of `addr` is deterministic and
	// so the port field starts out well defined.
	ep.addr = {};
	mem::copy(&ep.addr, (void*)ai.ai_addr, (usz)ai.ai_addrlen);
	ep.set_port(0);

	format_label(&ep);
	return ep;
}

<*
 Overwrite the port field of a raw sockaddr buffer.

 This is the single place that knows the port's byte layout, so the scanner
 can hand around a `char[]` sockaddr without caring about the details.
*>
macro void set_port_raw(char[] addr, int port)
{
	addr[SOCKADDR_PORT_OFFSET] = (char)((usz)port >> 8);
	addr[SOCKADDR_PORT_OFFSET + 1] = (char)((usz)port & 0xff);
}

<*
 Overwrite the port field of this endpoint's sockaddr template.
*>
macro void Endpoint.set_port(Endpoint* self, int port) => set_port_raw(&self.addr, port);

<*
 Printable address of this endpoint, e.g. "127.0.0.1" or "::1".
*>
fn String Endpoint.address(Endpoint* self)
{
	usz len = 0;
	while (len < self.label.len && self.label[len] != '\0') len++;
	return (String)self.label[:len];
}

<*
 Render the address bytes of the sockaddr into `ep.label`.

 Written by hand rather than via `inet_ntop` so the module has no dependency
 on a libc that may not exist. Only the shapes `getaddrinfo` can hand back for
 AF_INET / AF_INET6 are handled.
*>
fn void format_label(Endpoint* ep)
{
	LabelWriter w;
	w.buf = &ep.label;
	w.pos = 0;

	if (ep.family == os::AF_INET)
	{
		// IPv4 address lives at byte 4.
		for (usz i = 0; i < 4; i++)
		{
			if (i > 0) w.put('.');
			w.put_number(octet(ep.addr[4 + i]));
		}
		ep.label[w.finish()] = '\0';
		return;
	}

	// IPv6: 8 big endian 16 bit groups starting at byte 8. This needs an
	// index loop; `foreach` over the array would bind each group's value.
	usz[8] groups;
	for (usz i = 0; i < 8; i++)
	{
		groups[i] = ((usz)octet(ep.addr[8 + i * 2]) << 8) | (usz)octet(ep.addr[9 + i * 2]);
	}

	format_ipv6(&w, groups[..]);
	ep.label[w.finish()] = '\0';
}

<*
 A cursor over an endpoint's `label` buffer.

 An explicit writer rather than repeated string formatting because the IPv6
 form needs to skip groups entirely, which a single format string cannot do.
 Writes past the end of the buffer are dropped, so `finish` always has room
 for the NUL.
*>
struct LabelWriter
{
	char[] buf;
	usz pos;
}

macro void LabelWriter.put(LabelWriter* self, char c)
{
	if (self.pos + 1 < self.buf.len) self.buf[self.pos++] = c;
}

<*
 Append `value` in decimal.
*>
fn void LabelWriter.put_number(LabelWriter* self, usz value)
{
	char[20] digits;
	usz count = 0;
	do
	{
		digits[count++] = (char)('0' + value % 10);
		value /= 10;
	} while (value > 0);
	for (usz i = 0; i < count; i++)
	{
		self.put(digits[count - i - 1]);
	}
}

<*
 Append `value` in lowercase hex with no leading zeros. Zero renders as "0".
*>
fn void LabelWriter.put_hex(LabelWriter* self, usz value)
{
	char[16] chars;
	usz count = 0;
	do
	{
		chars[count++] = HEX_DIGITS[value & 0xf];
		value >>= 4;
	} while (value > 0);
	for (usz i = 0; i < count; i++)
	{
		self.put(chars[count - i - 1]);
	}
}

<*
 The write position, clamped so the caller can always store a NUL there.
*>
macro usz LabelWriter.finish(LabelWriter* self)
{
	return self.pos < self.buf.len - 1 ? self.pos : self.buf.len - 1;
}

<*
 Render 8 IPv6 groups in the canonical compressed form.

 RFC 5952 asks for the longest run of two or more zero groups to collapse to
 "::", and for hex digits with no leading zeros. Both matter here because the
 common case, "::1", is exactly a run at the start.

 @param w : "destination"
 @param groups : "the 8 groups, already decoded from the sockaddr"
*>
fn void format_ipv6(LabelWriter* w, usz[] groups)
{
	// Find the longest run of zero groups. A single zero group is never
	// compressed, per RFC 5952 4.2.2.
	usz best_start = 0;
	usz best_len = 0;
	usz run_start = 0;
	usz run_len = 0;
	for (usz i = 0; i < 8; i++)
	{
		if (groups[i] == 0)
		{
			if (run_len == 0) run_start = i;
			run_len++;
			if (run_len > best_len)
			{
				best_start = run_start;
				best_len = run_len;
			}
		}
		else
		{
			run_len = 0;
		}
	}
	// A single zero group is never compressed, per RFC 5952 4.2.2. Collapse
	// the "no run worth compressing" case to best_start == best_len so the
	// emit loop below cannot match it and spin.
	if (best_len < 2)
	{
		best_start = 0;
		best_len = 0;
	}

	// `need_sep` rather than "have I printed anything yet", because the "::"
	// that stands in for a zero run already separates whatever follows it.
	bool need_sep = false;
	usz i = 0;
	while (i < 8)
	{
		// The `best_len > 0` test is load bearing. Without it an address with
		// no compressible run would match at i == 0 and then advance i by
		// zero, looping forever.
		if (best_len > 0 && i == best_start)
		{
			w.put(':');
			w.put(':');
			need_sep = false;
			i += best_len;
			continue;
		}
		if (need_sep) w.put(':');
		w.put_hex(groups[i]);
		need_sep = true;
		i++;
	}
}

<*
 Reinterpret a sockaddr byte as an unsigned value. `char` is signed on most
 platforms, so a plain cast would turn 200 into -56.
*>
macro usz octet(char byte) => (usz)(byte & 0xff);
