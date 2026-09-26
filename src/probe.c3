<*
 The one thing a port scanner actually does: try to open a TCP connection
 and classify the outcome.

 This is a *connect* scan, which is the only kind that is both accurate and
 portable without raw sockets. Every probe:

   1. creates a non-blocking TCP socket,
   2. starts a connect and lets it run in the background,
   3. waits for it with `poll`, bounded by the caller's timeout,
   4. reads SO_ERROR to find out how the attempt ended.

 Using a non-blocking socket plus poll is what makes a timeout meaningful.
 A plain blocking connect can hang for the kernel's full SYN retry period
 (often 75+ seconds), which is useless for scanning.

 Note on the data flow: results are reported through the `PortState` enum
 rather than through C3 faults. Faults are fine for "the program could not
 run", but a refused port is an ordinary, expected scan result, and keeping
 it out of the error channel makes the scanner logic much easier to follow.
*>
module c3port::probe;

import std::io, std::net, std::net::os, std::time, libc, c3port::target;

enum PortState
{
	OPEN,       // the host completed a TCP handshake
	CLOSED,     // the host actively refused the connection
	FILTERED,   // no answer at all, or the network is unreachable
	ERROR,      // the probe itself could not be carried out
}

<*
 The outcome of a single probe, plus enough detail to explain it in verbose
 mode.
*>
struct Outcome
{
	PortState state;
	Duration elapsed;
	int detail;   // errno-style value, 0 when there is nothing to report
}

<*
 Probe one port on one endpoint.

 @param ep : "the endpoint to connect to"
 @param port : "the port to try"
 @param timeout : "how long to wait for the connection to settle"
*>
fn Outcome probe(target::Endpoint* ep, int port, Duration timeout)
{
	Outcome outcome = { .state = PortState.ERROR, .elapsed = time::DURATION_ZERO, .detail = 0 };
	Clock started = clock::now();

	// A local copy of the template, so concurrent probes against the same
	// endpoint cannot see each other's port.
	char[target::SOCKADDR_MAX] addr = ep.addr;
	target::set_port_raw(&addr, port);

	net::os::NativeSocket fd = os::socket(ep.family, ep.socktype, ep.protocol);
	if (!fd.is_valid())
	{
		return finish(&outcome, &started, PortState.ERROR, (int)libc::errno());
	}
	defer (void)fd.close();

	// Without this a "timeout" would be the kernel's, not ours.
	if (@catch(fd.set_non_blocking(true)))
	{
		return finish(&outcome, &started, PortState.ERROR, (int)libc::errno());
	}

	if (os::connect(fd, (net::os::SockAddrPtr)&addr, ep.addrlen) == 0)
	{
		// Connected before it could possibly block (typical on loopback).
		return finish(&outcome, &started, PortState.OPEN, 0);
	}

	int err = (int)libc::errno();
	if (!is_connect_in_flight(err))
	{
		return finish(&outcome, &started, classify_error(err), err);
	}

	// The connect is now running. Wait for it to become writable, which
	// happens either when it succeeds or when the peer sends a RST.
	net::Poll waiter = { .socket = fd, .events = net::PollSubscribe.ANY_WRITE };
	usz ready = net::poll_ms((&waiter)[:1], timeout.to_ms()) ?? 0;

	if (ready == 0)
	{
		// No event before the deadline: the packet was dropped somewhere, or
		// poll() itself failed. Either way there is no answer from the host.
		return finish(&outcome, &started, PortState.FILTERED, 0);
	}

	// SO_ERROR is where a completed-but-failed connect reports its verdict.
	// Reading it also clears it, which is why this is a single shot.
	CInt pending = 0;
	net::os::Socklen_t optlen = CInt::size;
	if (os::getsockopt(fd, os::SOL_SOCKET, os::SO_ERROR, &pending, &optlen) != 0)
	{
		return finish(&outcome, &started, PortState.ERROR, (int)libc::errno());
	}
	if (pending != 0)
	{
		return finish(&outcome, &started, classify_error((int)pending), (int)pending);
	}

	return finish(&outcome, &started, PortState.OPEN, 0);
}

<*
 Human readable name for a state, used by the results table.
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
 Did connect() fail because the attempt is still running, rather than
 because it failed outright?

 EWOULDBLOCK is the same value as EAGAIN on Linux and macOS, so the
 comparison is written with `||` rather than a switch to avoid duplicate
 switch cases.
*>
macro bool is_connect_in_flight(int err)
{
	return err == libc::Errno.EINPROGRESS
		|| err == libc::Errno.EAGAIN
		|| err == libc::Errno.EWOULDBLOCK
		|| err == libc::Errno.EALREADY;
}

<*
 Map a failed connect onto a scan result.
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

<*
 Stamp the elapsed time and the detail code onto an outcome and return it.
 Written as a helper so every exit path above reports timing consistently.
*>
macro Outcome finish(Outcome* outcome, Clock* started, PortState state, int detail)
{
	outcome.state = state;
	outcome.detail = detail;
	outcome.elapsed = started.to_now().to_duration();
	return *outcome;
}
