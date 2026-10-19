#!/usr/bin/env python3
"""Rebuild probe.jsonl from a capture: reassemble each probe flow's inbound bytes and decode the
handshake response. usage: pcap2probe.py <name>.pcap[ng][.gz] probe.jsonl  (ports 41000-48999 = probe side)"""
import sys, os, gzip, json, struct, socket, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import levin

def packets(fn):
    """(link type, unix seconds, frame) from a pcap or pcapng file, optionally gzipped."""
    f = (gzip.open if fn.endswith(".gz") else open)(fn, "rb")
    gh = f.read(4)
    if gh == b"\x0a\x0d\x0d\x0a":                 # pcapng: SHB, IDB, EPB blocks
        rest = f.read(8); end = "<" if rest[4:8] == b"\x4d\x3c\x2b\x1a" else ">"
        blen = struct.unpack(end + "I", rest[:4])[0]; f.read(blen - 12)
        links = []
        while True:
            h = f.read(8)
            if len(h) < 8: return
            bt, blen = struct.unpack(end + "II", h); body = f.read(blen - 8)
            if bt == 1: links.append(struct.unpack(end + "H", body[:2])[0])
            elif bt == 6:
                iface, hi, lo, cap = struct.unpack(end + "IIII", body[:16])
                yield links[iface], ((hi << 32) | lo) // 1000000, body[20:20 + cap]
    else:                                         # classic pcap
        gh += f.read(20)
        end = "<" if gh[:4] in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1") else ">"
        link = struct.unpack(end + "I", gh[20:24])[0]
        while True:
            h = f.read(16)
            if len(h) < 16: return
            yield link, struct.unpack(end + "I", h[0:4])[0], f.read(struct.unpack(end + "I", h[8:12])[0])

flows = collections.defaultdict(dict)          # (ip, rport, our port) -> {seq: payload}
first = {}
for link, ts, pkt in packets(sys.argv[1]):
    L2 = {1: 14, 113: 16, 276: 20}[link]
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
