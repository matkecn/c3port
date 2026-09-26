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

<*
 Probe one port on one endpoint.

 @param ep : "the address to connect to; not modified"
 @param port : "the TCP port to try"
 @param timeout : "how long to wait for the connect to resolve"
 @return "the state, how long it took, and the errno behind it"
*>
fn Outcome probe(target::Endpoint* ep, int port, Duration timeout)
{
	Outcome outcome = { .state = PortState.ERROR, .elapsed = time::DURATION_ZERO, .detail = 0 };
	Clock clock = clock::now();

	// A local copy of the template, so probes against the same endpoint
	// cannot see each other's port.
	char[target::SOCKADDR_MAX] addr = ep.addr;
	target::set_port_raw(&addr, port);

	net::NativeSocket fd = net::os::socket(ep.family, ep.socktype, ep.protocol);
	if (fdINVALID == fd)
	{
		return finish(outcome, PortState.ERROR, clock, (int)libc::errno());
	}
	defer net::os::close(fd);

	if (catch @err = net::os::set_non_blocking(fd, true))
	{
		return finish(outcome, PortState.ERROR, clock, (int)@err);
	}

	int err = 0;
	if (catch connect_err = net::os::connect(fd, (void*)&addr, ep.addrlen))
	{
		err = (int)connect_err;
		if (!is_connect_in_flight(err))
		{
			// A definite refusal, or a failure to even start.
			return finish(outcome, classify_error(err), clock, err);
		}
	}

	// Either connect returned EINPROGRESS or it succeeded immediately. Poll
	// for writability to find out which; a socket that is already writable
	// means the connect finished.
	int? ready = net::poll_ms(&fd, 1, (int)timeout.to_ms());
	if (!@ok(ready))
	{
		// poll() reporting an error is not the same as the port being
		// closed, so keep whatever errno is pending.
		return finish(outcome, PortState.ERROR, clock, (int)libc::errno());
	}
	if (ready!! == 0)
	{
		// Writable but not yet ready to report success, or simply too slow.
		if (!pending_error_is_clear(fd)) return finish(outcome, PortState.FILTERED, clock, 0);
	}

	int? so_error = net::os::getsockopt_int(fd, net::os::SOL_SOCKET, net::os::SO_ERROR);
	if (!@ok(so_error))
	{
		return finish(outcome, PortState.ERROR, clock, (int)libc::errno());
	}
	if (so_error!! != 0)
	{
		return finish(outcome, classify_error(so_error!!), clock, so_error!!);
	}

	return finish(outcome, PortState.OPEN, clock, 0);
}

<*
 Stamp the timing and detail onto an outcome and hand it back.

 Done in one place so every early return above records how long it took,
 rather than only the paths that fall through to the end.
*>
fn Outcome finish(Outcome outcome, PortState state, Clock clock, int detail)
{
	outcome.state = state;
	outcome.detail = detail;
	outcome.elapsed = clock.to_now().to_duration();
	return outcome;
}
