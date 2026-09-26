<*
 The port to service name database.

 Port numbers are assigned by IANA, so the name for a port is a fact rather
 than a guess, and a scan is much easier to read when it can print one. The
 table below is the source of truth for that mapping and for the "top" port
 preset.

 To extend the scanner with more ports, just append entries to `KNOWN`. The
 table must stay sorted by port because `name_of` binary searches it; the
 ordering is verified in test/services_test.c3 rather than trusted.
*>
module c3port::services;

<*
 One entry in the service database. `KNOWN` below is a list of these.
*>
struct Service
{
	int port;
	String name;
}

<*
 The service table, sorted ascending by port.

 Sorted order is load bearing: `name_of` is a binary search, and the search
 also assumes no duplicate ports, so that a hit is unambiguous.
*>
const Service[] KNOWN =
{
	{     7, "echo"          },
	{     9, "discard"       },
	{    13, "daytime"       },
	{    20, "ftp-data"      },
	{    21, "ftp"           },
	{    22, "ssh"           },
	{    23, "telnet"        },
	{    25, "smtp"          },
	{    26, "smtp"          },
	{    37, "time"          },
	{    53, "domain"        },
	{    67, "bootps"        },
	{    69, "tftp"          },
	{    70, "tftp"          },
	{    79, "finger"        },
	{    80, "http"          },
	{   102, "iso-tsap"      },
	{   110, "pop3"          },
	{   111, "sunrpc"        },
	{   119, "nntp"          },
	{   123, "ntp"           },
	{   135, "msrpc"         },
	{   137, "netbios-ns"    },
	{   138, "netbios-dgm"   },
	{   139, "netbios-ssn"   },
	{   143, "imap"          },
	{   161, "snmp"          },
	{   179, "bgp"           },
	{   389, "ldap"          },
	{   443, "https"         },
	{   445, "microsoft-ds"  },
	{   465, "smtps"         },
	{   513, "rlogin"        },
	{   514, "syslog"        },
	{   515, "printer"       },
	{   543, "kpasswd"       },
	{   544, "kshell"        },
	{   587, "submission"    },
	{   631, "ipp"           },
	{   636, "ldaps"         },
	{   646, "ldp"           },
	{   873, "rsync"         },
	{   990, "ftps-data"     },
	{   993, "ftps"          },
	{   995, "pop3s"         },
	{  1080, "socks"         },
	{  1194, "openvpn"       },
	{  1433, "ms-sql-s"      },
	{  1521, "oracle"        },
	{  1723, "pptp"          },
	{  2049, "nfs"           },
	{  2181, "zookeeper"     },
	{  2375, "docker"        },
	{  2376, "docker-alt"    },
	{  3000, "dev"           },
	{  3128, "squid"         },
	{  3306, "mysql"         },
	{  3389, "ms-wts"        },
	{  4443, "ssl-nodejs"    },
	{  5000, "upnp"          },
	{  5432, "postgresql"    },
	{  5672, "amqp"          },
	{  5900, "vnc"           },
	{  5985, "winrm"         },
	{  6000, "x11"           },
	{  6379, "redis"         },
	{  6443, "kubernetes"    },
	{  6667, "irc"           },
	{  6668, "ircs"          },
	{  6697, "irc-tls"       },
	{  7001, "weblogic"      },
	{  7002, "weblogic-alt"  },
	{  7070, "websphere"     },
	{  7071, "zookeeper-alt" },
	{  8000, "http-alt"      },
	{  8008, "http-alt"      },
	{  8080, "http-proxy"    },
	{  8081, "http-alt"      },
	{  8088, "http-alt"      },
	{  8181, "http-alt"      },
	{  8443, "https-alt"     },
	{  8500, "consul"        },
	{  8888, "http-alt"      },
	{  9000, "cslistener"    },
	{  9042, "cassandra"     },
	{  9090, "prometheus"    },
	{  9092, "kafka"         },
	{  9200, "elasticsearch" },
	{  9300, "elasticsearch" },
	{  9418, "git-daemon"    },
	{  9999, "abyss"         },
	{ 10000, "webmin"        },
	{ 11211, "memcached"     },
	{ 15672, "rabbitmq"      },
	{ 27017, "mongodb"       },
	{ 27018, "mongodb"       },
	{ 28017, "mongodb"       },
	{ 49152, "msrpc"         },
	{ 49153, "msrpc"         },
	{ 49154, "msrpc"         },
	{ 49155, "msrpc"         },
	{ 49156, "msrpc"         },
	{ 49157, "msrpc"         },
};

<*
 Number of ports scanned when `-p` is not given.
*>
const usz DEFAULT_TOP_COUNT = 100;

<*
 Look up a service name for a port.

 @param port : "the TCP port number"
 @return "the service name, or null if the port is not in the table"
*>
fn String? name_of(int port)
{
	usz low = 0;
	usz high = KNOWN.len;
	while (low < high)
	{
		usz mid = low + (high - low) / 2;
		int candidate = KNOWN[mid].port;
		if (candidate == port) return KNOWN[mid].name;
		if (candidate < port)
		{
			low = mid + 1;
		}
		else
		{
			high = mid;
		}
	}
	String? missing;
	return missing;
}
