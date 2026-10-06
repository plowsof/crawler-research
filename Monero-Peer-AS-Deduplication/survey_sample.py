#!/usr/bin/env python3
"""Sampling frame and random sample for the rentable-AS survey (Section 6.3).
Frame: ASes with at least one public server among IPv4 Tor relays (Onionoo), reachable Bitcoin nodes
(Bitnodes) and honest reachable Monero nodes (October 2026), mapped with the embedded asmap."""
import json, re, csv, ipaddress, random, gzip, os
from asmap import ASMap, net_to_prefix
m = ASMap.from_binary(open(os.environ.get("ASMAP", "data/ip_asn.dat"), "rb").read())
look = lambda ip: (m.lookup(net_to_prefix(ipaddress.ip_network(ip + "/32"))) or 0)
src = {}
def add(a, s):
    if a: src.setdefault(a, set()).add(s)
for addr in json.load(open("data/bitnodes_latest.json"))["nodes"]:
    mm = re.match(r"(\d+\.\d+\.\d+\.\d+):", addr)
    if mm: add(look(mm.group(1)), "bitcoin")
for r in json.load(open("data/onionoo_relays.json"))["relays"]:
    for x in r.get("or_addresses", []):
        mm = re.match(r"(\d+\.\d+\.\d+\.\d+):", x)
        if mm: add(look(mm.group(1)), "tor")
for r in csv.DictReader(open("data/nodes.csv")):
    if r["label"] == "honest": add(int(r["asn"]), "monero")
frame = sorted(src)
print("frame size", len(frame))
random.seed(20261005)
sample = random.sample(frame, 100)
pdb = {n["asn"]: n for n in json.load(open("data/survey/peeringdb_net.json"))["data"]}
names = {}
for l in gzip.open("data/ip2asn-combined.tsv.gz", "rt"):
    s, e, a, cc, nm = l.rstrip("\n").split("\t"); names.setdefault(int(a), (nm, cc))
dc = set()
for l in open("data/x4b_datacenter_ASN.txt"):
    mm = re.match(r"\s*AS(\d+)", l)
    if mm: dc.add(int(mm.group(1)))
with open("data/survey/frame.txt", "w") as fh: fh.write("\n".join(map(str, frame)) + "\n")
rows = []
for a in sample:
    p = pdb.get(a, {})
    rows.append({"asn": a, "sources": "+".join(sorted(src[a])), "x4b_dc": int(a in dc),
                 "as_name": names.get(a, ("", ""))[0], "country": names.get(a, ("", ""))[1],
                 "pdb_name": p.get("name", ""), "pdb_type": ";".join(p.get("info_types") or ([p["info_type"]] if p.get("info_type") else [])),
                 "website": p.get("website", "")})
with open("data/survey/sample.csv", "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
import collections
print("in PeeringDB:", sum(1 for r in rows if r["pdb_name"]), "with website:", sum(1 for r in rows if r["website"]), "x4b dc:", sum(r["x4b_dc"] for r in rows))
print(collections.Counter(r["pdb_type"] for r in rows))
