#!/usr/bin/env python3
"""Outbound peer selection from real peer lists (Section 8 of the asmap paper).

Each honest reachable node's candidate pool is the white-list sample it returned in 4 handshakes from the
four vantage points (data/peerlists/pl_*.json), not the whole reachable network. Selection follows
make_new_connection_from_peerlist() in src/p2p/net_node.inl: shuffle, keep one candidate per group not already
connected (/24 or ASN), sort by last_seen (most recent first), keep the first 20 untried candidates, pick index
get_random_index_with_fixed_probability(n-1) = x^3 / (16 (n-1))^3 / ... (cubic bias to recent), retry on failure.
A candidate succeeds if its address is known to be reachable (honest or suspected spy in the October 2026
snapshot, or a reachable ban-listed node); other entries fail (assumed unreachable). 12 slots are filled, then
12 churns, as in Rucknium (2025). Only the white list is modelled (monerod draws about 70 percent of outbound
connections from it); the gray list was not observed.

Usage: pl_sim.py <scenario> <rule> <stems-unused> ; scenario in observed|spread, rule in s24|asn,
options via env: BAN=1 (node uses the MRL ban list), CAP=<fraction> (per-AS cap on list entries), SEED.
Writes results/pl_<scenario>_<rule>_ban<BAN>_cap<CAP>.json"""
import json, glob, csv, os, sys, random, bisect, ipaddress, collections
scenario, rule = sys.argv[1], sys.argv[2]
BAN = int(os.environ.get("BAN", "0")); CAP = float(os.environ.get("CAP", "0")); SEED = int(os.environ.get("SEED", "314"))
asn_of = json.load(open("data/peerlists/asn_of.json"))           # ip -> asn, precomputed with the embedded asmap
label = {r["ip"]: r["label"] for r in csv.DictReader(open("data/nodes.csv"))}
for r in csv.DictReader(open("data/ban_reachable.csv")): label[r["ip"]] = "banned"
ban = []
for l in (open("data/ban_mrl_v2.txt") if os.path.exists("data/ban_mrl_v2.txt") else []):
    l = l.strip()
    if l and not l.startswith("#") and ":" not in l:
        n = ipaddress.ip_network(l, strict=False); ban.append((int(n.network_address), int(n.broadcast_address)))
ban.sort(); bs = [b[0] for b in ban]
# replication package: addresses are pseudonyms, ban-list membership is precomputed
BAN_IDS = set(open("data/peerlists/banned_ids.txt").read().split()) if os.path.exists("data/peerlists/banned_ids.txt") else None
def banned(ip):
    if BAN_IDS is not None: return ip in BAN_IDS
    v = int(ipaddress.ip_address(ip)); i = bisect.bisect_right(bs, v) - 1
    return i >= 0 and ban[i][1] >= v
def ip_int(ip): return int(ip[1:], 16) if BAN_IDS is not None else int(ipaddress.ip_address(ip))
lists = {}
for f in sorted(glob.glob("data/peerlists/pl_*.json")): lists.update(json.load(open(f)))
rng = random.Random(SEED)

S24_OF = json.load(open("data/peerlists/s24_of.json")) if BAN_IDS is not None else None
def group(ip, a):
    return ("asn", a) if rule == "asn" and a else ("s24", S24_OF[ip] if S24_OF is not None else ip.rsplit(".", 1)[0])

def fixed_prob_index(max_index):
    if not max_index: return 0
    x = rng.randrange(16 * max_index + 1)
    return (x * x * x) // (max_index * max_index * 16 * 16 * 16)

out = {"nodes": 0, "spy_out": 0.0, "stem_cur": 0.0, "stem_div": 0.0, "list_spy_share": 0.0, "list_unknown_share": 0.0, "slots_filled": 0.0}
for src, entries in lists.items():
    cand = []
    for kind, ip, port, ls in entries:
        if kind != "ipv4" or ip == src: continue
        lab = label.get(ip)
        if BAN and banned(ip): continue
        spy = lab in ("flagged", "banned")
        a = asn_of.get(ip, 0)
        if scenario == "spread" and spy: a = 4200000000 + ip_int(ip) % 1000000007   # one AS per spy node
        cand.append((ip, ls, a, spy, lab is not None))
    if not cand: continue
    if CAP:     # per-AS cap on list entries, keeping the most recently seen
        per = collections.defaultdict(list)
        for c in sorted(cand, key=lambda c: -c[1]): per[c[2]].append(c)
        lim = max(1, int(CAP * len(cand)))
        cand = [c for v in per.values() for c in v[:lim]]
    out["nodes"] += 1
    out["list_spy_share"] += sum(c[3] for c in cand) / len(cand)
    out["list_unknown_share"] += sum(not c[4] for c in cand) / len(cand)

    def choose(conns):
        connected = {group(c[0], c[2]) for c in conns}
        used = {c[0] for c in conns}
        tried = set()
        for _ in range(3):                                   # outer try loop, as in monerod
            order = cand[:]; rng.shuffle(order); seen = set(connected); dedup = []
            for c in order:
                g = group(c[0], c[2])
                if g in seen: continue
                seen.add(g); dedup.append(c)
            dedup.sort(key=lambda c: -c[1])
            filt = [c for c in dedup if c[0] not in tried and c[0] not in used][:20]
            if not filt: return None
            c = filt[fixed_prob_index(len(filt) - 1)]
            tried.add(c[0])
            if c[4]: return c                                # reachable -> connected
        return None
    conns = []
    for _ in range(12):
        c = choose(conns)
        if c: conns.append(c)
    for _ in range(12):
        if not conns: break
        conns.pop(rng.randrange(len(conns)))
        c = choose(conns)
        if c: conns.append(c)
    if not conns: continue
    n = len(conns); s = sum(c[3] for c in conns)
    out["spy_out"] += s * 12 / n                            # normalised to 12 slots
    out["slots_filled"] += n
    out["stem_cur"] += s / n
    share = collections.defaultdict(list)
    for c in conns: share[c[2]].append(c[3])
    out["stem_div"] += sum(sum(v) / len(v) for v in share.values()) / len(share)
N = out["nodes"]
res = {k: (v / N if k != "nodes" else v) for k, v in out.items()}
res.update({"scenario": scenario, "rule": rule, "ban": BAN, "cap": CAP, "seed": SEED})
os.makedirs("results", exist_ok=True)
json.dump(res, open(f"results/pl_{scenario}_{rule}_ban{BAN}_cap{CAP}_seed{SEED}.json", "w"))
print(json.dumps(res))
