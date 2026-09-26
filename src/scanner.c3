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
