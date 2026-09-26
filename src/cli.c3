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

<*
 Parse the command line.

 @param args : "argv, including the program name at index 0"
 @param options : "receives the parsed options when the result is SCAN"
 @return "SCAN, EXIT or ERROR"
*>
fn Outcome parse(String[] args, Options* options)
{
	options.target = "";
	options.port_spec = DEFAULT_PORT_SPEC;
	options.timeout = millis(DEFAULT_TIMEOUT_MS);
	options.ip_version = IpVersion.AUTO;
	options.show_closed = false;
	options.show_filtered = false;
	options.show_all = false;
	options.verbose = false;

	usz positionals = 0;
	for (usz i = 1; i < args.len; i++)
	{
		String arg = args[i];

		if (arg == "-")
		{
			// A bare dash is a hostname in some tools; treat it as one rather
			// than silently ignoring the argument.
			options.target = arg;
			positionals++;
			continue;
		}

		if (arg.starts_with("-"))
		{
			Outcome outcome = parse_switch(arg, args, &i, options);
			if (outcome != Outcome.SCAN) return outcome;
			continue;
		}

		if (positionals > 0)
		{
			(void)io::eprintfn("%s: unexpected extra argument '%s'", PROGRAM, arg);
			(void)io::eprintfn("Only one target may be given at a time.");
			return Outcome.ERROR;
		}
		options.target = arg;
		positionals++;
	}

	if (options.target.len == 0)
	{
		(void)io::eprintfn("%s: no target given.", PROGRAM);
		(void)io::eprintfn("Usage: %s <host> [-p ports] [options]", PROGRAM);
		(void)io::eprintfn("Try '%s --help' for more information.", PROGRAM);
		return Outcome.ERROR;
	}

	return Outcome.SCAN;
}
