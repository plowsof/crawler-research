#!/usr/bin/env python3
"""Rebuild probe.jsonl from a capture: reassemble each probe flow's inbound bytes and decode the
handshake response. usage: pcap2probe.py <name>.pcap[.gz] probe.jsonl  (ports 41000-48999 = probe side)"""
import sys, os, gzip, json, struct, socket, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import levin

op = gzip.open if sys.argv[1].endswith(".gz") else open
f = op(sys.argv[1], "rb")
gh = f.read(24)
end = "<" if gh[:4] in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1") else ">"
link = struct.unpack(end + "I", gh[20:24])[0]
L2 = {1: 14, 113: 16, 276: 20}[link]
flows = collections.defaultdict(dict)          # (ip, rport, our port) -> {seq: payload}
first = {}
while True:
    h = f.read(16)
    if len(h) < 16: break
    ts = struct.unpack(end + "I", h[0:4])[0]
    pkt = f.read(struct.unpack(end + "I", h[8:12])[0])
    ipb = pkt[L2:]
    if len(ipb) < 20 or ipb[0] >> 4 != 4 or ipb[9] != 6: continue
    ihl = (ipb[0] & 15) * 4; tot = struct.unpack(">H", ipb[2:4])[0]
    tcp = ipb[ihl:tot]
    sport, dport, seq = struct.unpack(">HHI", tcp[:8])
    if not 41000 <= dport < 49000: continue
    pl = tcp[(tcp[12] >> 4) * 4:]
    k = (socket.inet_ntoa(ipb[12:16]), sport, dport)
    first.setdefault(k, ts)
    if pl: flows[k].setdefault(seq, pl)

out = open(sys.argv[2], "w"); n = 0
for (ip, port, _), segs in flows.items():
    data, nxt = b"", None
    for seq in sorted(segs):                     # contiguous bytes only; stop at the first gap
        if nxt is not None and seq != nxt:
            if seq < nxt and seq + len(segs[seq]) > nxt: data += segs[seq][nxt - seq:]; nxt = seq + len(segs[seq])
            if seq > nxt: break
            continue
        data += segs[seq]; nxt = seq + len(segs[seq])
    rec = {"ip": ip, "port": port, "t": first[(ip, port, _)]}
    try:
        off = 0
        while True:
            sig, cb, ret, c, rc, flags, ver = levin.HDR.unpack(data[off:off + 33])
            if sig != levin.SIG: raise ValueError("bad levin")
            body = data[off + 33:off + 33 + cb]
            if len(body) < cb: raise ValueError("truncated")
            off += 33 + cb
            if c == levin.CMD_HANDSHAKE and flags & 2: break
        d = levin.decode(body)
        peers = []
        for e in d.get("local_peerlist_new", []) or []:
            kind, h2, p = levin.fmt_addr(e.get("adr", {}))
            peers.append([kind, h2, p, e.get("last_seen")])
        rec.update(peer_id="%016x" % d.get("node_data", {}).get("peer_id", 0), np=len(peers), peers=peers)
        n += 1
    except Exception as e:
        rec["err"] = type(e).__name__
    out.write(json.dumps(rec) + "\n")
print(f"{n} handshakes decoded of {len(flows)} flows with data", file=sys.stderr)
