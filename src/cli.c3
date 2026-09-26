<*
 Command line parsing.

 Kept separate from main so the option set can grow without touching the
 scan logic, and so parsing can be tested against a plain `String[]`.

 Error handling note: switches are consumed by helpers that return `bool`
 and print their own diagnostics, rather than signalling through C3 faults.
 That keeps the control flow here flat and readable. Faults are still used
 for genuine failures, such as a host that will not resolve.
*>
module c3port::cli;

import std::io, std::net, std::time, c3port::services;

const String PROGRAM = "c3port";
const String VERSION = "0.1.0";

const Duration DEFAULT_TIMEOUT = time::SEC;

enum Outcome
{
	SCAN,   // options are filled in, go and scan
	EXIT,   // --help or --version was handled, just exit successfully
	ERROR,  // a diagnostic has already been printed
}

enum IpVersion
{
	AUTO,
	V4,
	V6,
}

struct Options
{
	String target;
	String port_spec;
	Duration timeout;
	IpVersion ip_version;
	bool show_closed;
	bool show_filtered;
	bool verbose;
}

fn Options* Options.init(&self)
{
	self.target = "";
	// Scanning the most common ports by default keeps a bare `c3port host`
	// both useful and quick.
	self.port_spec = "top";
	self.timeout = DEFAULT_TIMEOUT;
	self.ip_version = IpVersion.AUTO;
	self.show_closed = false;
	self.show_filtered = false;
	self.verbose = false;
	return self;
}

<*
 Translate the options into the address family the resolver should ask for.
*>
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
 Parse `args`, including the program name at index 0.

 `options` is always initialised first, so the caller can inspect what was
 understood even when the outcome is ERROR.
*>
fn Outcome parse(String[] args, Options* options)
{
	options.init();
	usz positionals = 0;

	for (usz i = 1; i < args.len; i++)
	{
		String arg = args[i];
		if (arg.len == 0) continue;

		// A leading dash means a switch. A bare "-" is treated as a host,
		// which is harmless because it will simply fail to resolve.
		if (arg[0] == '-' && arg.len > 1)
		{
			Outcome step = parse_switch(arg, args, &i, options);
			if (step != Outcome.SCAN) return step;
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
		String value;
		if (!read_value(args, index, arg, inline_value, &value)) return Outcome.ERROR;
		options.port_spec = value;
		return Outcome.SCAN;
	}

	if (arg == "-t" || arg == "--timeout")
	{
		String value;
		if (!read_value(args, index, arg, inline_value, &value)) return Outcome.ERROR;
		long ms = value.to_int() ?? -1;
		if (ms < 1)
		{
			(void)io::eprintfn("%s: --timeout needs a positive number of milliseconds, got '%s'", PROGRAM, value);
			return Outcome.ERROR;
		}
		options.timeout = time::ms(ms);
		return Outcome.SCAN;
	}

	(void)io::eprintfn("%s: unknown option '%s'", PROGRAM, arg);
	(void)io::eprintfn("Try '%s --help' for more information.", PROGRAM);
	return Outcome.ERROR;
}

<*
 Fetch a switch's value, from either `--opt=value` or the next argument.
*>
fn bool read_value(String[] args, usz* index, String option, String inline_value, String* out)
{
	if (inline_value.len > 0)
	{
		*out = inline_value;
		return true;
	}
	if (*index + 1 >= args.len)
	{
		(void)io::eprintfn("%s: %s needs a value", PROGRAM, option);
		return false;
	}
	*index += 1;
	*out = args[*index];
	return true;
}

<*
 Print the help text.

 Written as a run of small print calls rather than one big literal so that
 the layout stays easy to edit and no escaping is needed.
*>
fn void print_usage()
{
	io::printn("");
	(void)io::printfn("%s %s - a small TCP connect port scanner", PROGRAM, VERSION);
	io::printn("");
	io::printn("USAGE");
	(void)io::printfn("    %s <host> [-p <ports>] [options]", PROGRAM);
	io::printn("");
	io::printn("ARGUMENTS");
	io::printn("    <host>                hostname or IP literal to scan");
	io::printn("");
	io::printn("OPTIONS");
	io::printn("    -p, --ports <spec>    which ports to scan (default: top)");
	(void)io::printfn("    -t, --timeout <ms>    per port connect timeout in ms (default: %d)", DEFAULT_TIMEOUT.to_ms());
	io::printn("    -4                    resolve to IPv4 addresses only");
	io::printn("    -6                    resolve to IPv6 addresses only");
	io::printn("    -a, --all-states      show closed, filtered and error ports too");
	io::printn("    -c, --closed          also show closed ports");
	io::printn("    -f, --filtered        also show filtered ports");
	io::printn("    -v, --verbose         add timing and error detail per port");
	io::printn("    -h, --help            show this help");
	io::printn("        --version         show the version");
	io::printn("");
	io::printn("PORT SPEC");
	io::printn("    22                    a single port");
	io::printn("    1-1024                an inclusive range");
	io::printn("    8000-                 8000 up to 65535");
	io::printn("    80,443,8080           a comma separated mix of the above");
	(void)io::printfn("    top                   the %d most commonly used ports", services::DEFAULT_TOP_COUNT);
	io::printn("    top<n>                the first <n> ports from that list");
	io::printn("    all                   every port from 1 to 65535");
	io::printn("");
	io::printn("EXAMPLES");
	(void)io::printfn("    %s 127.0.0.1", PROGRAM);
	(void)io::printfn("    %s scanme.example -p 22,80,443 -t 2000", PROGRAM);
	(void)io::printfn("    %s 10.0.0.5 -p 1-1024 --closed", PROGRAM);
	io::printn("");
}
