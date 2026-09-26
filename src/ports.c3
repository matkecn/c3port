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

<*
 A minimal fixed-size bit set over the whole port space.

 Used to drop duplicate ports without an O(n^2) scan, and to keep the
 parser allocation free. Costs 8 KiB of stack.
*>
struct SeenSet
{
	usz[PORT_SPACE / 64] words;
}

macro void SeenSet.mark(SeenSet* self, usz bit)
{
	self.words[bit / 64] |= (usz)1 << (bit % 64);
}

macro bool SeenSet.contains(SeenSet* self, usz bit)
{
	return (self.words[bit / 64] & ((usz)1 << (bit % 64))) != 0;
}

<*
 Append a port unless it was already collected. Returns false when the cap
 is reached, so the caller can report TOO_MANY once.
*>
fn bool push_unique(PortBuf* buf, SeenSet* seen, usz port)
{
	if (port < (usz)PORT_MIN || port > (usz)PORT_MAX) return true;
	if (seen.contains(port)) return true;
	seen.mark(port);
	return buf.push(port);
}

<*
 Convert a single port token to an int.

 @param text : "the token, digits only"
 @param out : "receives the port number on success"
 @return "NONE on success, otherwise why the token was rejected"
*>
fn ParseError parse_port_number(String text, int* out)
{
	if (text.len == 0) return ParseError.INVALID;
	foreach (char c : text)
	{
		// Digits only. This rejects a leading sign, so "-1" is reported as
		// an invalid token rather than as a range start.
		if (c < '0' || c > '9') return ParseError.INVALID;
	}

	int? value = text.to_int();
	if (!@ok(value)) return ParseError.INVALID;
	if (value!! < PORT_MIN || value!! > PORT_MAX) return ParseError.OUT_OF_RANGE;

	*out = value!!;
	return ParseError.NONE;
}

<*
 Append every port in an inclusive range.
*>
fn ParseError add_range(PortBuf* buf, SeenSet* seen, int from, int to)
{
	for (int port = from; port <= to; port++)
	{
		if (!push_unique(buf, seen, (usz)port)) return ParseError.TOO_MANY;
	}
	return ParseError.NONE;
}

<*
 Handle one comma-delimited element: either `port` or `from-to`.
*>
fn ParseError add_token(PortBuf* buf, SeenSet* seen, String token)
{
	sz? dash_at = token.index_of_char('-');

	if (!@ok(dash_at))
	{
		int port = 0;
		ParseError error = parse_port_number(token, &port);
		if (error != ParseError.NONE) return error;
		if (!push_unique(buf, seen, (usz)port)) return ParseError.TOO_MANY;
		return ParseError.NONE;
	}

	sz split = dash_at!!;

	// A leading '-' has nothing before it, so it can only be a typo.
	if (split == 0) return ParseError.INVALID;

	int from = 0;
	ParseError error = parse_port_number(token[0..split - 1].trim(), &from);
	if (error != ParseError.NONE) return error;

	// An open ended "8000-" means "8000 up to the last port", which shows up
	// here as an empty range after the dash. C3 range slices include both
	// ends, so the text after the dash is [split + 1..len - 1].
	String to_text = split + 1 <= token.len - 1
		? token[split + 1..token.len - 1].trim()
		: "";
	int to = PORT_MAX;
	if (to_text.len > 0)
	{
		error = parse_port_number(to_text, &to);
		if (error != ParseError.NONE) return error;
	}

	if (from > to) return ParseError.INVALID;
	return add_range(buf, seen, from, to);
}

<*
 Handle a comma separated list of single ports and ranges.
*>
fn ParseError add_list(PortBuf* buf, SeenSet* seen, String spec)
{
	sz start = 0;
	while (true)
	{
		sz comma = start;
		while (comma < spec.len && spec[comma] != ',') comma++;

		// C3 range slices include both ends, so a token that runs to the
		// end of the spec ends at len - 1 rather than len.
		sz last = comma > 0 ? comma - 1 : 0;
		ParseError error = add_token(buf, seen, spec[start..last].trim());
		if (error != ParseError.NONE) return error;

		if (comma >= spec.len) return ParseError.NONE;
		start = comma + 1;
	}
}
