<*
 A single TCP connect probe.

 One probe is: create a non-blocking socket, connect, wait for writability with
 a timeout, then read SO_ERROR to find out what the kernel thought. SO_ERROR is
 what distinguishes a refused connection from a successful one, because
 non-blocking connect reports "still in progress" for both.

 The result is a plain enum rather than a fault. A closed or filtered port is
 the normal, expected outcome of a scan, not a program failure, so there is
 nothing to unwind and nothing for the caller to catch.

 This is where the libc dependency lives, and it is the only module that needs
 one: errno values are the standard way to say why a connect failed.
*>
module c3port::probe;

import std::io, std::net, std::net::os, std::time, libc, c3port::target;

<*
 What a probe concluded about a port.
*>
enum PortState
{
	OPEN,     // the connect completed
	CLOSED,   // the host refused, so almost certainly nothing is listening
	FILTERED, // dropped by something in between, or unreachable
	ERROR,    // the probe itself failed
}

<*
 The result of probing one port against one address.
*>
struct Outcome
{
	PortState state;
	Duration elapsed;
	int detail;   // the errno style code, only shown with --verbose
}

<*
 Human readable state name, for the results table.
*>
fn String state_name(PortState state)
{
	switch (state)
	{
		case PortState.OPEN: return "open";
		case PortState.CLOSED: return "closed";
		case PortState.FILTERED: return "filtered";
		case PortState.ERROR: return "error";
	}
}

<*
 Is this errno one of the "the connect is still on its way" codes?

 A non-blocking connect returns immediately with one of these when the answer
 is not ready yet, which is the normal case for any host that is not on the
 local machine.
*>
macro bool is_connect_in_flight(int err)
{
	// EWOULDBLOCK is the same value as EAGAIN on Linux and macOS, so the
	// second test is redundant there but not on every platform.
	return err == libc::Errno.EINPROGRESS
		|| err == libc::Errno.EAGAIN
		|| err == libc::Errno.EWOULDBLOCK
		|| err == libc::Errno.EALREADY;
}

<*
 Turn a connect errno into a port state.

 The distinction that matters most is ECONNREFUSED, which is a definite answer
 from the host, versus a timeout or an unreachable network, which is silence
 and so usually means a firewall dropped the packet.
*>
fn PortState classify_error(int err)
{
	switch (err)
	{
		case libc::Errno.ECONNREFUSED: return PortState.CLOSED;
		case libc::Errno.ECONNRESET: return PortState.CLOSED;
		case libc::Errno.EHOSTUNREACH: return PortState.FILTERED;
		case libc::Errno.ENETUNREACH: return PortState.FILTERED;
		case libc::Errno.ENETDOWN: return PortState.FILTERED;
		case libc::Errno.ETIMEDOUT: return PortState.FILTERED;
		case libc::Errno.EACCES: return PortState.FILTERED;   // a local firewall ate it
		default: return PortState.ERROR;
	}
}
