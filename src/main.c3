<*
 c3port - a small TCP port scanner.

 Entry point only: read options, parse the port spec, resolve the host, run
 the scan, print the results. Everything of substance lives in the sibling
 modules so each piece can be tested and changed on its own.

 Exit codes:
     0   the scan ran and found at least one open port
     1   the scan ran and found no open ports, or the host did not resolve
     2   the command line or port spec was invalid
*>
module c3port;

import std::io, c3port::cli, c3port::ports, c3port::report, c3port::scanner, c3port::target;

const int EXIT_OK = 0;
const int EXIT_NO_OPEN_PORTS = 1;
const int EXIT_USAGE = 2;

fn int main(String[] args)
{
	cli::Options options;
	cli::Outcome outcome = cli::parse(args, &options);
	if (outcome == cli::Outcome.EXIT) return EXIT_OK;
	if (outcome == cli::Outcome.ERROR) return EXIT_USAGE;

	// Parse the port spec before touching the network, so a typo is reported
	// immediately instead of after a scan has already started.
	ports::PortSet requested = ports::parse(tmem, options.port_spec);
	if (requested.error != ports::ParseError.NONE)
	{
		(void)io::eprintfn("%s: bad --ports value: %s", cli::PROGRAM, ports::describe(requested.error));
		return EXIT_USAGE;
	}
	if (requested.ports.len == 0)
	{
		(void)io::eprintfn("%s: the port spec selected no ports", cli::PROGRAM);
		return EXIT_USAGE;
	}

	// `@ok` reports whether a `T?` holds a value, so a false result means the
	// resolution failed.
	target::Resolution? maybe = target::resolve(options.target, options.protocol());
	if (!@ok(maybe))
	{
		(void)io::eprintfn("%s: cannot resolve '%s'", cli::PROGRAM, options.target);
		(void)io::eprintfn("Check the spelling, check your network, or pass an IP address instead.");
		return EXIT_NO_OPEN_PORTS;
	}

	target::Resolution resolved = maybe!!;
	defer resolved.close();

	scanner::Report scan;
	scan.init(mem);
	defer scan.free();
	scan.target = options.target;
	scan.port_spec = options.port_spec;
	scan.show_closed = options.show_closed;
	scan.show_filtered = options.show_filtered;
	scan.show_verbose = options.verbose;

	scanner::run(&scan, &resolved, requested.ports, options.timeout);

	report::print_header(&scan, &options);
	report::print_addresses(&scan);
	report::print_results(&scan, &options);
	report::print_summary(&scan);

	return scan.open_count > 0 ? EXIT_OK : EXIT_NO_OPEN_PORTS;
}
