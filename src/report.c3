<*
 All terminal output lives here.

 Keeping presentation out of the scanner means the scan data model can
 change without worrying about formatting, and makes it easy to bolt on a
 second output format (JSON, CSV) later by adding a sibling module.
*>
module c3port::report;

import std::io, std::time, c3port::cli, c3port::probe, c3port::scanner;

<*
 Print the banner and the settings the scan is about to run with.
*>
fn void print_header(scanner::Report* scan, cli::Options* options)
{
	(void)io::printfn("%s %s - scanning %s", cli::PROGRAM, cli::VERSION, scan.target);
	(void)io::printfn("ports: %s (%d)   timeout: %dms   family: %s   states: %s",
		scan.port_spec,
		scan.ports_requested,
		options.timeout.to_ms(),
		family_name(options),
		state_filter_name(scan));
}

<*
 Print the addresses the host resolved to, so it is obvious what was
 actually probed.
*>
fn void print_addresses(scanner::Report* scan)
{
	sz count = scan.endpoints.size;
	if (count == 0) return;

	io::printn("");
	(void)io::printfn("resolved %d address%s:", count, count == 1 ? "" : "es");
	for (sz i = 0; i < count; i++)
	{
		(void)io::printfn("  %s", scan.endpoints.entries[i].address());
	}
}

<*
 Print the results table.

 Nothing is printed at all when the scan found nothing worth showing, because
 "no ports matched" plus a summary reads better than a table of headers with
 no rows under them.
*>
fn void print_results(scanner::Report* scan, cli::Options* options)
{
	sz count = scan.findings.size;

	if (count == 0)
	{
		io::printn("");
		io::printn("No ports matched the selected states.");
		if (!scan.show_closed && !scan.show_filtered)
		{
			io::printn("Re-run with --all-states to also see closed and filtered ports.");
		}
		return;
	}

	io::printn("");
	if (options.verbose)
	{
		(void)io::printfn("%-11s %-9s %-16s %-24s %8s", "PORT", "STATE", "SERVICE", "ADDRESS", "TIME");
	}
	else
	{
		(void)io::printfn("%-11s %-9s %-16s %s", "PORT", "STATE", "SERVICE", "ADDRESS");
	}

	for (sz i = 0; i < count; i++)
	{
		scanner::Finding* finding = &scan.findings.entries[i];

		if (options.verbose)
		{
			(void)io::printfn("%-11s %-9s %-16s %-24s %7dms%s",
				port_text(finding.port),
				probe::state_name(finding.state),
				finding.service,
				finding.address,
				finding.elapsed.to_ms(),
				detail_text(finding));
		}
		else
		{
			(void)io::printfn("%-11s %-9s %-16s %s",
				port_text(finding.port),
				probe::state_name(finding.state),
				finding.service,
				finding.address);
		}
	}
}

<*
 Print the closing tally.
*>
fn void print_summary(scanner::Report* scan)
{
	io::printn("");
	(void)io::printfn("Scanned %d port(s) across %d address(es) in %s",
		scan.ports_requested, scan.endpoints.size, format_duration(scan.elapsed));
	(void)io::printfn("%d open, %d closed, %d filtered, %d error",
		scan.open_count, scan.closed_count, scan.filtered_count, scan.error_count);
}

<*
 A port number with its transport, e.g. "443/tcp".
*>
fn String port_text(usz port) => string::format(tmem, "%d/tcp", port);

<*
 The extra column --verbose adds. An errno-style code is only worth showing
 when the probe itself failed, not for a port that was merely closed.
*>
fn String detail_text(scanner::Finding* finding)
{
	if (finding.detail == 0) return "";
	return string::format(tmem, "  [code %d]", finding.detail);
}

fn String family_name(cli::Options* options)
{
	switch (options.ip_version)
	{
		case cli::IpVersion.V4: return "IPv4";
		case cli::IpVersion.V6: return "IPv6";
		case cli::IpVersion.AUTO: return "auto";
	}
}

fn String state_filter_name(scanner::Report* scan)
{
	if (scan.show_closed && scan.show_filtered) return "all";
	if (scan.show_closed) return "open+closed";
	if (scan.show_filtered) return "open+filtered";
	return "open";
}

<*
 Render a duration at a sensible precision for whichever magnitude it is.
*>
fn String format_duration(Duration duration)
{
	NanoDuration ns = duration.to_nano();
	if (ns >= time::SEC.to_nano())
	{
		return string::format(tmem, "%.1fs", (double)duration.to_ms() / 1000.0);
	}
	if (ns >= time::MS.to_nano())
	{
		return string::format(tmem, "%dms", duration.to_ms());
	}
	return string::format(tmem, "%dus", ns / 1000);
}
