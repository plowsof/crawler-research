#!/usr/bin/env python3
"""Share of honest reachable nodes that block the MRL ban list (or a DNS blocklist covering it), Section 5.3.
A node's white list only holds peers it has connected to, so a node that blocks ban-listed addresses has none in
its white list. For each honest node with at least 50 IPv4 entries in its sampled white list (data/peerlists),
count the entries in the MRL ban list. Writes results/ban_adoption.json."""
import json, glob, os, ipaddress, bisect, statistics
BAN_IDS = set(open("data/peerlists/banned_ids.txt").read().split()) if os.path.exists("data/peerlists/banned_ids.txt") else None
ban = []
if BAN_IDS is None:
    for l in open("data/ban_mrl_v2.txt"):
        l = l.strip()
        if l and not l.startswith("#") and ":" not in l:
            n = ipaddress.ip_network(l, strict=False); ban.append((int(n.network_address), int(n.broadcast_address)))
    ban.sort()
bs = [b[0] for b in ban]
def banned(ip):
    if BAN_IDS is not None: return ip in BAN_IDS
    v = int(ipaddress.ip_address(ip)); i = bisect.bisect_right(bs, v) - 1
    return i >= 0 and ban[i][1] >= v
lists = {}
for f in sorted(glob.glob("data/peerlists/pl_*.json")): lists.update(json.load(open(f)))
shares = []
for src, e in lists.items():
    v = [ip for kind, ip, port, ls in e if kind == "ipv4"]
    if len(v) >= 50: shares.append(sum(map(banned, v)) / len(v))
zero = sum(s == 0 for s in shares)
res = {"nodes": len(shares), "zero_banned": zero, "zero_banned_pct": round(100 * zero / len(shares), 1),
       "median_banned_share_pct_others": round(100 * statistics.median([s for s in shares if s > 0]), 1)}
json.dump(res, open("results/ban_adoption.json", "w"), indent=1); print(res)
