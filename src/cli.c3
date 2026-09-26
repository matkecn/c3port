<*
 Command line parsing.

 Kept apart from main so the argument grammar can be read, and changed, on its
 own. Every switch returns through `Outcome`, so the caller never has to look
 at a partially filled Options to decide what happened.

 A rejected command line is ordinary user input, not a program failure, so it
 comes back as Outcome.ERROR rather than a fault.
*>
module c3port::cli;

import std::io, std::net;

const String PROGRAM = "c3port";
const String VERSION = "0.1.0";

const String DEFAULT_PORT_SPEC = "top";
const int DEFAULT_TIMEOUT_MS = 1000;

enum IpVersion
{
	AUTO,
	V4,
	V6,
}

enum Outcome
{
	SCAN,   // carry on and run a scan
	EXIT,   // help or version was printed, stop with success
	ERROR,  // the command line was invalid
}

struct Options
{
	String target;
	String port_spec;
	Duration timeout;
	IpVersion ip_version;
	bool show_closed;
	bool show_filtered;
	bool show_all;
	bool verbose;
}

fn net::IpProtocol Options.protocol(Options* self)
{
	switch (self.ip_version)
	{
		case IpVersion.V4: return net::IpProtocol.IPV4;
		case IpVersion.V6: return net::IpProtocol.IPV6;
		case IpVersion.AUTO: return net::IpProtocol.UNSPECIFIED;
	}
}
