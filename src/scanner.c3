<*
 Scan orchestration: walk the port list against every resolved address and
 collect the results worth showing.

 Deliberately sequential and single threaded. That keeps the output stable
 and easy to reason about, and it leaves concurrency as a self contained
 change to this one file -- see the roadmap in README.md.
*>
module c3port::scanner;

import std::collections::list, std::io, std::net, std::net::os, std::time, c3port::probe, c3port::services, c3port::target;

const String UNKNOWN_SERVICE = "-";

<*
 One reported finding: a port that the caller asked to see.
*>
struct Finding
{
	usz port;
	probe::PortState state;
	String address;   // which resolved address this was on
	String service;   // UNKNOWN_SERVICE when the port is not in services::KNOWN
	Duration elapsed;
	int detail;       // errno-style code, only meaningful with --verbose
}

<*
 Everything a completed scan produced, plus the display filters that decided
 which findings were kept.

 The filters live here rather than being passed in as a callback because the
 scanner is the thing that has to honour them: they decide what gets stored,
 and storing nothing is what keeps a wide scan cheap.
*>
struct Report
{
	String target;                 // the host exactly as the user typed it
	String port_spec;              // the -p value, for the header line
	usz ports_requested;
	List{target::Endpoint} endpoints;
	List{Finding} findings;        // only the states `wants` accepted
	usz open_count;
	usz closed_count;
	usz filtered_count;
	usz error_count;
	Duration elapsed;
	bool show_closed;
	bool show_filtered;
	bool show_verbose;
}

fn Report* Report.init(&self, Allocator allocator)
{
	self.target = "";
	self.port_spec = "";
	self.ports_requested = 0;
	self.endpoints.init(allocator);
	self.findings.init(allocator);
	self.open_count = 0;
	self.closed_count = 0;
	self.filtered_count = 0;
	self.error_count = 0;
	self.elapsed = time::DURATION_ZERO;
	self.show_closed = false;
	self.show_filtered = false;
	self.show_verbose = false;
	return self;
}

fn void Report.free(&self)
{
	self.endpoints.free();
	self.findings.free();
}

<*
 Should a port in this state be recorded?

 Open ports are always interesting. The rest are opt in, which is what keeps
 the default output short when scanning a wide range.
*>
fn bool Report.wants(Report* self, probe::PortState state)
{
	switch (state)
	{
		case probe::PortState.OPEN: return true;
		case probe::PortState.CLOSED: return self.show_closed;
		case probe::PortState.FILTERED: return self.show_filtered;
		case probe::PortState.ERROR: return self.show_verbose;
	}
}
