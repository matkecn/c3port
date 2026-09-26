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
