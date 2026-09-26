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
