<*
 Unit tests for the service name database.

 The table is hand maintained and `name_of` binary searches it, so the two
 things that can silently break are a mis-sorted table (the search then
 returns the wrong name or nothing) and a duplicate port (the search finds one
 of the two at random). Both are checked here rather than trusted.
*>
module c3port::services_test;

import std::core::test, std::io, c3port::services;

<*
 Look up `port` and assert the name is exactly `expected`.

 @param expect_found : "false means the port is deliberately absent"
*>
fn void check_name(int port, String expected, bool expect_found = true)
{
	String found;
	bool ok = services::name_of(port, &found);
	if (ok != expect_found)
	{
		test::@check(false, "name_of(%d) found=%s, expected found=%s", port, ok, expect_found);
		return;
	}
	if (ok) test::@check(found == expected, "name_of(%d) = \"%s\", expected \"%s\"", port, found, expected);
}

fn void test_table_is_sorted() @test
{
	// `name_of` is a binary search, which is only correct on a sorted table.
	for (usz i = 1; i < services::KNOWN.len; i++)
	{
		test::@check(services::KNOWN[i - 1].port < services::KNOWN[i].port,
			"table is out of order at index %d: %d then %d",
			i, services::KNOWN[i - 1].port, services::KNOWN[i].port);
	}
}

fn void test_table_has_no_duplicates() @test
{
	// A duplicate port makes the search result depend on where it lands.
	for (usz i = 1; i < services::KNOWN.len; i++)
	{
		test::@check(services::KNOWN[i - 1].port != services::KNOWN[i].port,
			"port %d appears twice in the table", services::KNOWN[i].port);
	}
}

fn void test_ports_are_in_range() @test
{
	foreach (services::Service service : services::KNOWN)
	{
		test::@check(service.port >= 1 && service.port <= 65535,
			"port %d is outside 1..65535", service.port);
		test::@check(service.name.len > 0, "port %d has no name", service.port);
	}
}

fn void test_known_names() @test
{
	check_name(22, "ssh");
	check_name(80, "http");
	check_name(443, "https");
	check_name(53, "domain");
	check_name(7, "echo");
}

fn void test_unknown_ports() @test
{
	// Ports that are not in the table, including the two ends of the range.
	check_name(0, "", false);
	check_name(1, "", false);
	check_name(65535, "", false);
	check_name(44444, "", false);
}

fn void test_every_table_entry_round_trips() @test
{
	// Walk the whole table and confirm the search finds each entry. This
	// catches a table that is sorted but whose search bounds are wrong.
	foreach (services::Service service : services::KNOWN)
	{
		String found;
		if (!services::name_of(service.port, &found))
		{
			test::@check(false, "name_of(%d) failed for a table entry", service.port);
			continue;
		}
		test::@check(found == service.name,
			"name_of(%d) = \"%s\", table says \"%s\"", service.port, found, service.name);
	}
}

fn void test_default_top_count_is_sane() @test
{
	// "top" has to select something, and not the entire table by accident.
	test::@check(services::DEFAULT_TOP_COUNT > 0, "top would select no ports");
	test::@check(services::DEFAULT_TOP_COUNT <= services::KNOWN.len,
		"top wants %d ports but the table only has %d",
		services::DEFAULT_TOP_COUNT, services::KNOWN.len);
}
