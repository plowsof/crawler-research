#!/usr/bin/env python3
"""Live check of inbound concentration (Section 4.1, Figure inbound-share): the honest outbound peers of the live A/B
instances (data/ab), classified by the number of honest reachable nodes in their AS in the October 2026 snapshot.
Each distinct (instance, peer) pair counts once. Writes results/live_peer_classes.json."""
import json, glob, csv, os, collections, ipaddress
PEER_ASN = json.load(open("data/peer_asn.json")) if os.path.exists("data/peer_asn.json") else None
if PEER_ASN is None:
    from asmap import ASMap, net_to_prefix
    m = ASMap.from_binary(open(os.environ.get("ASMAP", "data/ip_asn.dat"), "rb").read())
def asn(ip):
    if PEER_ASN is not None: return PEER_ASN.get(ip, 0)
    return m.lookup(net_to_prefix(ipaddress.ip_network(ip + "/32"))) or 0
rows = list(csv.DictReader(open("data/nodes.csv")))
lab = {r["ip"]: r["label"] for r in rows}
k = collections.Counter(int(r["asn"]) for r in rows if r["label"] == "honest")
def cls(n): return "Alone in its AS" if n == 1 else "AS with 2-9 honest nodes" if n <= 9 else "AS with 10+ honest nodes"
peers = {0: set(), 1: set()}
for f in sorted(glob.glob("data/ab/*.jsonl")):
    box = f.split("/")[-1][:-6]
    for l in open(f):
        r = json.loads(l)
        for c in r.get("c", []):
            if c[2] == 0 and c[0] and ":" not in c[0] and lab.get(c[0]) == "honest":
                peers[r["asmap"]].add((box, r["inst"], c[0]))
res = {}
for arm, name in ((0, "default"), (1, "asmap")):
    c = collections.Counter(cls(k[asn(ip)]) for _, _, ip in peers[arm] if k[asn(ip)])
    n = sum(c.values())
    res[name] = {"honest_peers": n, "instances": len({(b, i) for b, i, _ in peers[arm]}),
                 "share_pct": {g: round(100 * v / n, 1) for g, v in c.items()}}
json.dump(res, open("results/live_peer_classes.json", "w"), indent=1); print(json.dumps(res, indent=1))
