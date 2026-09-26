<*
 Parsing of the `-p` / `--ports` argument into a concrete list of ports.

 Accepted forms:

     22                 a single port
     1-1024             an inclusive range
     8000-              8000 up to the maximum port
     80,443,8080        a comma separated mix of all of the above
     top100             the first 100 entries of services::KNOWN
     top                the same as services::DEFAULT_TOP_COUNT
     all                every port in 1..65535

 Duplicates are removed while the order the user asked for is preserved, so
 `-p 443,80,443` scans 443 then 80 exactly once.

 Results come back as a `PortSet` rather than a `usz[]?`. A rejected port
 spec is ordinary user input rather than a program failure, and modelling it
 as data instead of a C3 fault means the caller can print a precise message
 (see `describe`) and the parser stays easy to unit test.

 This module deliberately contains no networking code.
*>
module c3port::ports;

import std::core::mem::alloc, std::io, c3port::services;

const int PORT_MIN = 1;
const int PORT_MAX = 65535;
const sz PORT_SPACE = (sz)PORT_MAX + 1;

const String TOP_KEYWORD = "top";
const String ALL_KEYWORD = "all";

enum ParseError
{
	NONE,
	EMPTY,        // the spec was blank
	INVALID,      // the spec did not parse
	OUT_OF_RANGE, // a port was below 1 or above 65535
	TOO_MANY,     // the spec expanded past the caller's cap
	NO_MEMORY,    // an allocation failed
}

<*
 The outcome of parsing a port spec. `ports` is only meaningful when
 `error` is NONE, and is owned by the allocator passed to `parse`.
*>
struct PortSet
{
	usz[] ports;
	ParseError error;
}

fn PortSet failed(ParseError error) => { .ports = {}, .error = error };

<*
 A growable usz array.

 A hand rolled buffer rather than a List because the result has to be handed
 back as a plain slice anyway. `push` refuses to grow past `limit`, which is
 how the caller's port cap is enforced in exactly one place.
*>
struct PortBuf
{
	usz[] data;
	sz len;
	sz cap;
	sz limit;
	Allocator allocator;
}

fn PortBuf* PortBuf.init(PortBuf* self, Allocator allocator, sz limit)
{
	self.allocator = allocator;
	self.limit = limit;
	self.len = 0;
	self.cap = limit < 64 ? limit : 64;
	usz[]? data = allocator.alloc_array_try(usz, self.cap);
	if (!@ok(data)) return null;
	self.data = data!!;
	return self;
}

fn void PortBuf.free(PortBuf* self)
{
	if (self.data) alloc::free(self.allocator, self.data);
	self.data = {};
	self.len = 0;
	self.cap = 0;
}

<*
 Append a value. Returns false when the limit is reached, without storing.
*>
fn bool PortBuf.push(PortBuf* self, usz value)
{
	if (self.len >= self.limit) return false;
	if (self.len == self.cap && !grow(self)) return false;
	self.data[self.len++] = value;
	return true;
}

fn bool grow(PortBuf* self)
{
	sz cap = self.cap * 2;
	if (cap > self.limit) cap = self.limit;
	usz[]? resized = alloc::realloc_array_try(self.allocator, self.data, usz, cap);
	if (!@ok(resized)) return false;
	self.data = resized!!;
	self.cap = cap;
	return true;
}
