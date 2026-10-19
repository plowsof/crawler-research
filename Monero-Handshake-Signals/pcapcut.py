#!/usr/bin/env python3
"""Keep only the probe's own TCP flows. usage: pcapcut.py raw.pcap conns.tsv out.pcap
Flow key = (our source port, remote ip, remote port) from conns.tsv. Ethernet / SLL / SLL2 pcap."""
import sys, struct, socket

keys = set()
for l in open(sys.argv[2]):
    sp, ip, port = l.split()
    keys.add((int(sp), ip, int(port)))

f, o = open(sys.argv[1], "rb"), open(sys.argv[3], "wb")
gh = f.read(24); o.write(gh)
end = "<" if gh[:4] in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1") else ">"
link = struct.unpack(end + "I", gh[20:24])[0]
L2 = {1: 14, 113: 16, 276: 20}[link]
kept = total = 0
while True:
    h = f.read(16)
    if len(h) < 16: break
    incl = struct.unpack(end + "I", h[8:12])[0]
    pkt = f.read(incl); total += 1
    if link == 1:
        et = struct.unpack(">H", pkt[12:14])[0]
    elif link == 113:
        et = struct.unpack(">H", pkt[14:16])[0]
    else:
        et = struct.unpack(">H", pkt[0:2])[0]
    if et != 0x0800: continue
    ipb = pkt[L2:]
    if len(ipb) < 20 or ipb[9] != 6: continue
    ihl = (ipb[0] & 15) * 4
    src, dst = socket.inet_ntoa(ipb[12:16]), socket.inet_ntoa(ipb[16:20])
    sport, dport = struct.unpack(">HH", ipb[ihl:ihl + 4])
    if (sport, dst, dport) in keys or (dport, src, sport) in keys:
        o.write(h); o.write(pkt); kept += 1
print(f"kept {kept} of {total} packets")
