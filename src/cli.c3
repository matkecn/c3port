<*
 Command line parsing.

 Kept apart from main so the argument grammar can be read, and changed, on its
 own. Every switch returns through `Outcome`, so the caller never has to look
 at a partially filled Options to decide what happened.

 A rejected command line is ordinary user input, not a program failure, so it
 comes back as Outcome.ERROR rather than a fault.
*>
module c3port::cli;

import std::io, std::net, std::time;

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
	options.timeout = DEFAULT_TIMEOUT_MS * time::MS;
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

<*
 Handle one switch.

 @param arg : "the argument as typed, for example -p or --ports=22"
 @param index : "cursor into args; advanced past a value if one was consumed"
 @return "SCAN to keep parsing, or EXIT / ERROR"
*>
fn Outcome parse_switch(String arg, String[] args, usz* index, Options* options)
{
	String inline_value;

	// --long=value form.
	//
	// C3 range slices include both ends, so the pieces either side of the
	// '=' are [0..equals - 1] and [equals + 1..len - 1]. The second one is
	// empty when the user wrote a bare "--ports=", which the value readers
	// below treat as "no inline value" and fall back to the next argument.
	if (arg.contains_char('=') && arg.starts_with("--"))
	{
		sz equals = arg.index_of_char('=')!!;
		inline_value = equals + 1 <= arg.len - 1 ? arg[equals + 1..arg.len - 1] : "";
		arg = equals > 0 ? arg[0..equals - 1] : "";
	}

	if (arg == "-h" || arg == "--help")
	{
		print_usage();
		return Outcome.EXIT;
	}
	if (arg == "--version")
	{
		(void)io::printfn("%s %s", PROGRAM, VERSION);
		return Outcome.EXIT;
	}
	if (arg == "-4")
	{
		options.ip_version = IpVersion.V4;
		return Outcome.SCAN;
	}
	if (arg == "-6")
	{
		options.ip_version = IpVersion.V6;
		return Outcome.SCAN;
	}
	if (arg == "-a" || arg == "--all-states")
	{
		options.show_all = true;
		options.show_closed = true;
		options.show_filtered = true;
		return Outcome.SCAN;
	}
	if (arg == "-c" || arg == "--closed")
	{
		options.show_closed = true;
		return Outcome.SCAN;
	}
	if (arg == "-f" || arg == "--filtered")
	{
		options.show_filtered = true;
		return Outcome.SCAN;
	}
	if (arg == "-v" || arg == "--verbose")
	{
		options.verbose = true;
		return Outcome.SCAN;
	}
	if (arg == "-p" || arg == "--ports")
	{
		String value = take_value(inline_value, args, index, arg);
		if (value.len == 0) return Outcome.ERROR;
		options.port_spec = value;
		return Outcome.SCAN;
	}
	if (arg == "-t" || arg == "--timeout")
	{
		String value = take_value(inline_value, args, index, arg);
		if (value.len == 0) return Outcome.ERROR;
		int? ms = value.to_int();
		if (!@ok(ms) || ms!! <= 0)
		{
			(void)io::eprintfn("%s: --timeout expects a positive number of milliseconds, got '%s'", PROGRAM, value);
			return Outcome.ERROR;
		}
		options.timeout = ms!! * time::MS;
		return Outcome.SCAN;
	}

	(void)io::eprintfn("%s: unknown option '%s'", PROGRAM, arg);
	(void)io::eprintfn("Try '%s --help' for more information.", PROGRAM);
	return Outcome.ERROR;
}

<*
 Get the value for a switch, from either --opt=value or the next argument.

 @param inline_value : "the part after '=', empty if there was none"
 @param args : "argv"
 @param index : "cursor, advanced when a following argument is consumed"
 @param arg : "the switch as typed, for the error message"
 @return "the value, or empty on error with the reason already printed"
*>
fn String take_value(String inline_value, String[] args, usz* index, String arg)
{
	if (inline_value.len > 0) return inline_value;

	if (*index + 1 >= args.len)
	{
		(void)io::eprintfn("%s: %s needs a value", PROGRAM, arg);
		return "";
	}
	*index += 1;
	return args[*index];
}

<*
 Print the usage text.

 The port spec grammar is documented here rather than only in the README,
 because this is the one screen a user sees when they get something wrong.
*>
fn void print_usage()
{
	(void)io::printfn("%s %s - a small TCP connect port scanner", PROGRAM, VERSION);
	(void)io::printn("");
	(void)io::printn("USAGE");
	(void)io::printn("    c3port <host> [-p <ports>] [options]");
	(void)io::printn("");
	(void)io::printn("ARGUMENTS");
	(void)io::printn("    <host>                hostname or IP literal to scan");
	(void)io::printn("");
	(void)io::printn("OPTIONS");
	(void)io::printfn("    -p, --ports <spec>    which ports to scan (default: %s)", DEFAULT_PORT_SPEC);
	(void)io::printfn("    -t, --timeout <ms>    per port connect timeout in ms (default: %d)", DEFAULT_TIMEOUT_MS);
	(void)io::printn("    -4                    resolve to IPv4 addresses only");
	(void)io::printn("    -6                    resolve to IPv6 addresses only");
	(void)io::printn("    -a, --all-states      show closed, filtered and error ports too");
	(void)io::printn("    -c, --closed          also show closed ports");
	(void)io::printn("    -f, --filtered        also show filtered ports");
	(void)io::printn("    -v, --verbose         add timing and error detail per port");
	(void)io::printn("    -h, --help            show this help");
	(void)io::printn("        --version         show the version");
	(void)io::printn("");
	(void)io::printn("PORT SPEC");
	(void)io::printn("    22                    a single port");
	(void)io::printn("    1-1024                an inclusive range");
	(void)io::printn("    8000-                 8000 up to 65535");
	(void)io::printn("    80,443,8080           a comma separated mix of the above");
	(void)io::printn("    top                   the 100 most commonly used ports");
	(void)io::printn("    top<n>                the first <n> ports from that list");
	(void)io::printn("    all                   every port from 1 to 65535");
	(void)io::printn("");
	(void)io::printn("EXAMPLES");
	(void)io::printn("    c3port 127.0.0.1");
	(void)io::printn("    c3port scanme.example -p 22,80,443 -t 2000");
	(void)io::printn("    c3port 10.0.0.5 -p 1-1024 --closed");
}
