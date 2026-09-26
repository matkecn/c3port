<*
 Unit tests for address label rendering and sockaddr port patching.

 An address is rendered by hand rather than through `inet_ntop`, because that
 keeps the module free of any libc dependency. The trade is that the RFC 5952
 rules for IPv6 have to be implemented correctly here, so the shapes those
 rules care about are pinned down below.
*>
module c3port::target_test;

import std::core::test, std::io, c3port::target;

<*
 Render 8 already-decoded IPv6 groups through the same path `format_label`
 uses, and compare against `expected`.
*>
fn void check_ipv6(usz[8] groups, String expected)
{
	target::LabelWriter writer;
	char[target::LABEL_MAX] label;
	writer.buf = &label;
	writer.pos = 0;
	target::format_ipv6(&writer, groups[..]);
	usz len = writer.finish();
	label[len] = '\0';
	String actual = (String)label[:len];
	test::@check(actual == expected, "rendered \"%s\", expected \"%s\"", actual, expected);
}

<*
 Render 4 IPv4 octets the same way `format_label` does.
*>
fn void check_ipv4(usz[4] octets, String expected)
{
	target::LabelWriter writer;
	char[target::LABEL_MAX] label;
	writer.buf = &label;
	writer.pos = 0;
	for (usz i = 0; i < 4; i++)
	{
		if (i > 0) writer.put('.');
		writer.put_number(octets[i]);
	}
	usz len = writer.finish();
	label[len] = '\0';
	String actual = (String)label[:len];
	test::@check(actual == expected, "rendered \"%s\", expected \"%s\"", actual, expected);
}

fn void test_ipv4_labels() @test
{
	usz[4] loopback = { 127, 0, 0, 1 };
	usz[4] unspecified = { 0, 0, 0, 0 };
	usz[4] broadcast = { 255, 255, 255, 255 };
	usz[4] private = { 10, 0, 0, 7 };
	check_ipv4(loopback, "127.0.0.1");
	check_ipv4(unspecified, "0.0.0.0");
	check_ipv4(broadcast, "255.255.255.255");
	check_ipv4(private, "10.0.0.7");
}

fn void test_ipv6_loopback() @test
{
	// The most common IPv6 address, and the one that an un-compressed
	// formatter gets wrong.
	usz[8] groups = { 0, 0, 0, 0, 0, 0, 0, 1 };
	check_ipv6(groups, "::1");
}

fn void test_ipv6_all_zero() @test
{
	usz[8] groups = { 0, 0, 0, 0, 0, 0, 0, 0 };
	check_ipv6(groups, "::");
}

fn void test_ipv6_compresses_the_longest_zero_run() @test
{
	// RFC 5952 4.2.2: a run of two or more zero groups collapses to "::".
	usz[8] doc = { 0x2001, 0x0db8, 0, 0, 0, 0, 0, 1 };
	usz[8] link_local = { 0xfe80, 0, 0, 0, 0, 0, 0, 0 };
	check_ipv6(doc, "2001:db8::1");
	check_ipv6(link_local, "fe80::");
}

fn void test_ipv6_compresses_a_trailing_run() @test
{
	// A zero run at the end collapses, and must not leave a dangling colon.
	usz[8] tail = { 0x2001, 0x0db8, 0x85a3, 0, 0, 0, 0, 0 };
	check_ipv6(tail, "2001:db8:85a3::");
}

fn void test_ipv6_leaves_a_lone_zero_group_alone() @test
{
	// RFC 5952 4.2.2: a single zero group is not compressed.
	usz[8] groups = { 1, 0, 1, 0, 1, 0, 1, 1 };
	check_ipv6(groups, "1:0:1:0:1:0:1:1");
}

fn void test_ipv6_picks_the_longest_run() @test
{
	// With more than one eligible run the longest wins, and the first wins
	// only when the lengths are equal.
	usz[8] later_is_longer = { 0, 1, 0, 0, 1, 0, 0, 0 };
	usz[8] first_is_longer = { 0, 0, 1, 0, 0, 1, 0, 1 };
	check_ipv6(later_is_longer, "0:1:0:0:1::");
	check_ipv6(first_is_longer, "::1:0:0:1:0:1");
}

fn void test_ipv6_prints_groups_without_leading_zeros() @test
{
	// Lowercase hex, no zero padding, per RFC 5952 4.
	usz[8] full = { 0x1234, 0x5678, 0x9abc, 0xdef0, 0x1234, 0x5678, 0x9abc, 0xdef0 };
	usz[8] mixed = { 0x00ff, 0x0001, 0x0f0f, 0xffff, 1, 2, 3, 4 };
	check_ipv6(full, "1234:5678:9abc:def0:1234:5678:9abc:def0");
	check_ipv6(mixed, "ff:1:f0f:ffff:1:2:3:4");
}

fn void test_ipv6_writer_clamps_to_the_buffer() @test
{
	// The label buffer is fixed size, so an over long address must be
	// truncated rather than written past the end.
	char[4] tiny;
	target::LabelWriter writer;
	writer.buf = &tiny;
	writer.pos = 0;
	for (usz i = 0; i < 4; i++) writer.put_number(999999 + i);

	usz len = writer.finish();
	test::@check(len <= tiny.len - 1, "finish() left no room for the NUL");
	test::@check(len > 0, "the writer produced nothing at all");
}

fn void test_set_port_writes_network_byte_order() @test
{
	// The port lives at bytes 2..3 of a sockaddr in big endian order. Getting
	// the order backwards scans port 0x1600 instead of 22.
	char[16] addr;

	target::set_port_raw(&addr, 22);
	test::@check((usz)(addr[2] & 0xff) == 0, "high byte of 22 is %d, expected 0", addr[2] & 0xff);
	test::@check((usz)(addr[3] & 0xff) == 22, "low byte of 22 is %d, expected 22", addr[3] & 0xff);

	target::set_port_raw(&addr, 8080);
	test::@check((usz)(addr[2] & 0xff) == 0x1f, "high byte of 8080 is wrong");
	test::@check((usz)(addr[3] & 0xff) == 0x90, "low byte of 8080 is wrong");

	target::set_port_raw(&addr, 65535);
	test::@check((usz)(addr[2] & 0xff) == 0xff, "high byte of 65535 is wrong");
	test::@check((usz)(addr[3] & 0xff) == 0xff, "low byte of 65535 is wrong");

	target::set_port_raw(&addr, 0);
	test::@check((usz)(addr[2] & 0xff) == 0, "high byte of 0 is wrong");
	test::@check((usz)(addr[3] & 0xff) == 0, "low byte of 0 is wrong");
}

fn void test_sockaddr_port_offset_is_stable() @test
{
	// If this ever moves, `set_port_raw` and the address decoders have to
	// move with it, and the tests above would silently stop testing the
	// right bytes.
	test::@check(target::SOCKADDR_PORT_OFFSET == 2,
		"port offset moved to %d", target::SOCKADDR_PORT_OFFSET);
}
