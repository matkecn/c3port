<*
 Unit tests for the `-p` / `--ports` argument parser.

 The parser is the piece most worth pinning down: it is the only place where
 untrusted text turns into a list of integers, and every downstream stage
 assumes it produced exactly what the user asked for.

 Assertions use `test::@check` rather than `test::eq` because the latter needs
 an `.equals` method, which the integer and enum types here do not have.
*>
module c3port::ports_test;

import std::core::mem::alloc, std::core::test, std::io, c3port::ports, c3port::services;

<*
 Parse `spec`, assert it succeeded, and return the ports.
*>
fn usz[] parsed(String spec)
{
	ports::PortSet result = ports::parse(tmem, spec);
	test::@check(result.error == ports::ParseError.NONE,
		"parse(\"%s\") failed: %s", spec, ports::describe(result.error));
	return result.ports;
}

<*
 Assert a spec is rejected, and for the right reason.
*>
fn void rejects(String spec, ports::ParseError expected)
{
	ports::PortSet result = ports::parse(tmem, spec);
	test::@check(result.error == expected,
		"parse(\"%s\") gave %s, expected %s", spec, result.error, expected);
	test::@check(result.ports.len == 0, "a rejected spec must not yield ports");
}

<*
 Assert a spec produces exactly these ports, in this order.
*>
fn void expect_ports(String spec, usz[] expected)
{
	usz[] actual = parsed(spec);
	if (actual.len != expected.len)
	{
		test::@check(false, "parse(\"%s\") gave %d ports, expected %d",
			spec, actual.len, expected.len);
		return;
	}
	for (usz i = 0; i < expected.len; i++)
	{
		test::@check(actual[i] == expected[i],
			"parse(\"%s\")[%d] = %d, expected %d", spec, i, actual[i], expected[i]);
	}
}

fn usz[] range(int from, int to)
{
	usz[] result = alloc::alloc_array(tmem, usz, (sz)(to - from + 1));
	for (int port = from; port <= to; port++)
	{
		result[port - from] = (usz)port;
	}
	return result;
}

fn void test_single_port() @test
{
	expect_ports("22", { 22 });
	expect_ports("1", { 1 });
	expect_ports("65535", { 65535 });
}

fn void test_range() @test
{
	expect_ports("1-3", { 1, 2, 3 });
	expect_ports("8080-8082", { 8080, 8081, 8082 });
	expect_ports("100-100", { 100 });
}

fn void test_open_ended_range() @test
{
	// "65534-" covers the last two ports and nothing else, and "65535-" is
	// the degenerate one port case.
	expect_ports("65534-", { 65534, 65535 });
	expect_ports("65535-", { 65535 });
}

fn void test_comma_list() @test
{
	expect_ports("80,443,8080", { 80, 443, 8080 });
	expect_ports("22,1-3,443", { 22, 1, 2, 3, 443 });
}

fn void test_whitespace_is_ignored() @test
{
	expect_ports("  80 , 443  ", { 80, 443 });
	expect_ports(" 1 - 3 ", { 1, 2, 3 });
	expect_ports("\t22\t", { 22 });
}

fn void test_duplicates_collapse_and_order_is_kept() @test
{
	// The order the user wrote is the order that gets scanned, and each port
	// appears exactly once.
	expect_ports("443,80,443", { 443, 80 });
	expect_ports("1-3,2-4", { 1, 2, 3, 4 });
	expect_ports("22,22,22", { 22 });
}

fn void test_all_expands_to_every_port() @test
{
	ports::PortSet result = ports::parse(tmem, "all");
	test::@check(result.error == ports::ParseError.NONE, "parse(\"all\") failed");
	test::@check(result.ports.len == 65535,
		"parse(\"all\") gave %d ports, expected 65535", result.ports.len);
	test::@check(result.ports[0] == 1, "first port of \"all\" is %d, expected 1", result.ports[0]);
	test::@check(result.ports[result.ports.len - 1] == 65535, "last port of \"all\" is wrong");
}

fn void test_top_uses_the_default_count() @test
{
	usz[] ports = parsed("top");
	test::@check(ports.len == (usz)services::DEFAULT_TOP_COUNT,
		"parse(\"top\") gave %d ports, expected %d", ports.len, services::DEFAULT_TOP_COUNT);
	// "top" means "the beginning of the service table", so the first entry
	// has to be the table's first port.
	test::@check(ports[0] == (usz)services::KNOWN[0].port,
		"first port of \"top\" is %d, expected %d", ports[0], services::KNOWN[0].port);
}

fn void test_top_n_takes_a_count() @test
{
	expect_ports("top5", { 7, 9, 13, 20, 21 });
}

fn void test_top_n_beyond_the_table_clamps() @test
{
	// Asking for more ports than are known is not an error, it just scans
	// the whole table.
	usz[] exact = parsed(string::format(tmem, "top%d", services::KNOWN.len));
	test::@check(exact.len == (usz)services::KNOWN.len, "top<len> did not clamp");

	usz[] many = parsed("top100000");
	test::@check(many.len == (usz)services::KNOWN.len, "top100000 did not clamp");
}

fn void test_rejects_empty_and_blank() @test
{
	rejects("", ports::ParseError.EMPTY);
	rejects("   ", ports::ParseError.EMPTY);
	rejects("\t\n", ports::ParseError.EMPTY);
}

fn void test_rejects_out_of_range() @test
{
	rejects("0", ports::ParseError.OUT_OF_RANGE);
	rejects("65536", ports::ParseError.OUT_OF_RANGE);
	rejects("99999", ports::ParseError.OUT_OF_RANGE);
	rejects("1-70000", ports::ParseError.OUT_OF_RANGE);
	rejects("0-10", ports::ParseError.OUT_OF_RANGE);
}

fn void test_rejects_malformed() @test
{
	rejects("abc", ports::ParseError.INVALID);
	rejects("22x", ports::ParseError.INVALID);
	rejects("-1", ports::ParseError.INVALID);
	rejects("22,,443", ports::ParseError.INVALID);
	rejects(",22", ports::ParseError.INVALID);
	rejects("80-22", ports::ParseError.INVALID);
	rejects("topology", ports::ParseError.INVALID);
	rejects("80-abc", ports::ParseError.INVALID);
}

fn void test_max_ports_is_enforced() @test
{
	ports::PortSet result = ports::parse(tmem, "1-1000", 10);
	test::@check(result.error == ports::ParseError.TOO_MANY, "cap was not enforced");

	// Exactly hitting the cap is fine.
	ports::PortSet exact = ports::parse(tmem, "1-10", 10);
	test::@check(exact.error == ports::ParseError.NONE, "hitting the cap exactly should pass");
	test::@check(exact.ports.len == 10, "got %d ports, expected 10", exact.ports.len);
}

fn void test_growth_past_the_initial_capacity() @test
{
	// The buffer starts small and doubles, so check a span that crosses
	// several growth steps and is not a round number.
	expect_ports("1000-1200", range(1000, 1200));
	expect_ports("1-5000", range(1, 5000));
}

fn void test_describe_covers_every_error() @test
{
	// A missing message would print an empty string to the user, which is
	// the one thing an error path must never do. This list has to be kept in
	// step with the enum: adding a member without a message fails the build
	// only if the switch is exhaustive, so the check below is the backstop.
	ports::ParseError[6] all = {
		ports::ParseError.NONE,
		ports::ParseError.EMPTY,
		ports::ParseError.INVALID,
		ports::ParseError.OUT_OF_RANGE,
		ports::ParseError.TOO_MANY,
		ports::ParseError.NO_MEMORY,
	};
	foreach (ports::ParseError error : all)
	{
		String message = ports::describe(error);
		test::@check(message.len > 0, "ParseError %s has no description", error);
	}
}
