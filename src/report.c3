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

<*
 The list of addresses the host resolved to, so it is obvious how many hosts
 are really being scanned and which family each result came from.
*>
fn void print_addresses(scanner::Report* report)
{
	if (report.endpoints.size == 0) return;

	(void)io::printfn("");
	if (report.endpoints.size == 1)
	{
		(void)io::printn("resolved 1 address:");
	}
	else
	{
		(void)io::printfn("resolved %d addresses:", report.endpoints.size);
	}

	for (sz i = 0; i < report.endpoints.size; i++)
	{
		(void)io::printfn("  %s", report.endpoints.entries[i].address());
	}
}

<*
 The results table. Prints nothing when no finding passed the filters, so a
 scan that found nothing but closed ports says so in one line below.
*>
fn void print_results(scanner::Report* report, cli::Options* options)
{
	(void)io::printn("");
	if (report.findings.size == 0)
	{
		(void)io::printn("no results matched the selected states");
		return;
	}

	(void)io::printn("PORT        STATE     SERVICE          ADDRESS                      TIME");
	for (sz i = 0; i < report.findings.size; i++)
	{
		scanner::Finding* finding = &report.findings.entries[i];
		(void)io::printfn("%s   %s   %s   %s   %s",
			port_text(finding.port),
			probe::state_name(finding.state),
			finding.service,
			finding.address,
			duration_text(finding.elapsed));

		if (options.verbose && finding.detail != 0)
		{
			(void)io::printfn("            [code %d]", finding.detail);
		}
	}
}

<*
 The trailing totals: how long the scan took and what it found.

 The filtered and error counts are always shown even when those findings were
 not stored, so the numbers add up to what was actually probed.
*>
fn void print_summary(scanner::Report* report)
{
	(void)io::printn("");
	(void)io::printfn("Scanned %d port(s) across %d address(es) in %s",
		report.ports_requested, report.endpoints.size, duration_text(report.elapsed));
	(void)io::printfn("%d open, %d closed, %d filtered, %d error",
		report.open_count, report.closed_count, report.filtered_count, report.error_count);
}

fn String port_text(usz port) => string::format(tmem, "%d/tcp", port);

<*
 Format a duration compactly, picking a unit that keeps the number readable.
 A local loop scan reports single digit microseconds, a remote one reports
 hundreds of milliseconds, and neither wants seven digits on screen.
*>
fn String duration_text(Duration duration)
{
	long us = (long)duration;
	if (us < 1_000) return string::format(tmem, "%dus", us);
	if (us < 1_000_000) return string::format(tmem, "%dms", us / 1_000);
	return string::format(tmem, "%.1fs", (double)us / 1_000_000.0);
}
