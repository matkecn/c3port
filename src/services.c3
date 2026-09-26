<*
 A small port -> service-name database.

 This is the single source of truth for "interesting" ports: the scan order
 used by `-p top<N>` and the names printed in the results table both come from
 the `KNOWN` table below.

 To extend the scanner with more ports, just append entries to `KNOWN`. The
 table MUST stay sorted by ascending port, because `name_of` binary searches
 it (a `@require`-style sanity check lives in the unit tests).

 Swap point: if you later want the full IANA list, replace the `name_of`
 lookup here with a parser for /etc/services and leave the rest of the
 program untouched.
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
	{    69, "tftp"          },
	{    79, "finger"        },
	{    80, "http"          },
	{    81, "http-alt"      },
	{    88, "kerberos"      },
	{   102, "iso-tsap"      },
	{   110, "pop3"          },
	{   111, "sunrpc"        },
	{   113, "auth"          },
	{   119, "nntp"          },
	{   135, "msrpc"         },
	{   139, "netbios-ssn"   },
	{   143, "imap"          },
	{   144, "imap"          },
	{   179, "bgp"           },
	{   199, "x11"           },
	{   389, "ldap"          },
	{   427, "svrloc"        },
	{   443, "https"         },
	{   444, "snpp"          },
	{   445, "microsoft-ds"  },
	{   465, "smtps"         },
	{   513, "login"         },
	{   514, "shell"         },
	{   515, "printer"       },
	{   543, "postgres"      },
	{   544, "kshell"        },
	{   548, "afp"           },
	{   554, "rtsp"          },
	{   587, "submission"    },
	{   631, "ipp"           },
	{   646, "ldaps"         },
	{   873, "rsync"         },
	{   990, "ftps-data"     },
	{   993, "imaps"         },
	{   995, "pop3s"         },
	{  1025, "rsh"           },
	{  1026, "rsh"           },
	{  1027, "rsh"           },
	{  1028, "rsh"           },
	{  1029, "rsh"           },
	{  1110, "cdp"           },
	{  1433, "mssql"         },
	{  1720, "h323"          },
	{  1723, "pptp"          },
	{  1755, "ms-streaming"  },
	{  1900, "upnp"          },
	{  2000, "cisco-sccp"    },
	{  2001, "dc"            },
	{  2049, "nfs"           },
	{  2121, "ftp-data"      },
	{  2717, "msft-mgmt"     },
	{  3000, "ppp"           },
	{  3128, "http-proxy"    },
	{  3306, "mysql"         },
	{  3389, "ms-wbt"        },
	{  3986, "altvnc"        },
	{  4899, "radmin"        },
	{  5000, "upnp"          },
	{  5009, "airport-admin" },
	{  5051, "acta"          },
	{  5060, "sip"           },
	{  5061, "sips"          },
	{  5101, "cisco-pta"     },
	{  5190, "cisco-tacacs"  },
	{  5357, "wsman"         },
	{  5432, "postgresql"    },
	{  5631, "pcanywhere"    },
	{  5666, "nrpc"          },
	{  5800, "vnc-http"      },
	{  5900, "vnc"           },
	{  6000, "x11"           },
	{  6001, "x11"           },
	{  6646, "sentinel"      },
	{  7070, "websm"         },
	{  8000, "http-alt"      },
	{  8008, "http-alt"      },
	{  8009, "ajp13"         },
	{  8080, "http-proxy"    },
	{  8081, "http-alt"      },
	{  8443, "https-alt"     },
	{  8888, "http-alt"      },
	{  9100, "jetdirect"     },
	{  9999, "cisco-tacacs"  },
	{ 10000, "webmin"        },
	{ 32768, "filenet"       },
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

 This is a two value return rather than a `String?` on purpose. `String` is a
 struct, and a zero initialised `String?` is indistinguishable from a present
 empty string, so an optional return cannot express "no such port" reliably.
 The caller passes in the text it wants for an unknown port instead, which
 also keeps the placeholder in one place.

 @param port : "the TCP port number"
 @param out : "receives the service name when the port is in the table"
 @return "true when the port was found"
*>
fn bool name_of(int port, String* out)
{
	usz low = 0;
	usz high = KNOWN.len;
	while (low < high)
	{
		usz mid = low + (high - low) / 2;
		int candidate = KNOWN[mid].port;
		if (candidate == port)
		{
			*out = KNOWN[mid].name;
			return true;
		}
		if (candidate < port)
		{
			low = mid + 1;
		}
		else
		{
			high = mid;
		}
	}
	return false;
}
