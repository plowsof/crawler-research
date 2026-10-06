#!/usr/bin/env python3
"""Coverage of the IPv4 part of an asmap: total mapped addresses and distinct ASNs.
Usage: asmap_coverage.py ip_asn.dat"""
import sys, random, ipaddress
from asmap import ASMap, net_to_prefix
m = ASMap.from_binary(open(sys.argv[1], "rb").read())
v4 = 0; v4asn = set()
for prefix, asn in m.to_entries(overlapping=False):
    # IPv4-mapped IPv6 prefix ::ffff:0:0/96
    if len(prefix) >= 96 and not any(prefix[:80]) and all(prefix[80:96]):
        v4 += 2 ** (128 - len(prefix)); v4asn.add(asn)
print(f"IPv4 addresses mapped: {v4} of {2**32} ({100*v4/2**32:.1f}%)")
print(f"distinct ASNs in IPv4 part: {len(v4asn)}")
random.seed(1); N = 100000
z = sum((m.lookup(net_to_prefix(ipaddress.ip_network(f"{ipaddress.IPv4Address(random.getrandbits(32))}/32"))) or 0) == 0 for _ in range(N))
print(f"random IPv4 sample unmapped: {z} of {N}")
