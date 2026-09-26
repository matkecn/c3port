<*
 Terminal output.

 This module only ever reads the `scanner::Report` it is handed, which is what
 keeps formatting out of the scan path: nothing here can change what was
 probed, and nothing in the scanner knows how a result is displayed.
*>
module c3port::report;

import std::io, std::net, std::time, c3port::cli, c3port::probe, c3port::scanner;

<*
 The banner: what is being scanned, with what options.
*>
fn void print_header(scanner::Report* report, cli::Options* options)
{
	(void)io::printfn("%s %s - scanning %s", cli::PROGRAM, cli::VERSION, report.target);

	String states = report.show_closed
		? (report.show_filtered ? "all states" : "open+closed")
		: (report.show_filtered ? "open+filtered" : "open only");

	(void)io::printfn("ports: %s (%d)   timeout: %dms   family: %s   states: %s",
		report.port_spec, report.ports_requested, options.timeout.to_ms(),
		family_name(options.ip_version), states);
}

fn String family_name(cli::IpVersion version)
{
	switch (version)
	{
		case cli::IpVersion.V4: return "IPv4";
		case cli::IpVersion.V6: return "IPv6";
		case cli::IpVersion.AUTO: return "auto";
	}
}
