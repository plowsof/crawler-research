#!/usr/bin/env python3
"""ffprobe.py run that also logs each connection attempt's (source port, ip, port) so the capture
can be cut down to the probe's own flows. usage: ruckcap.py targets.txt probe.jsonl conns.tsv [workers]"""
import sys, os, random, socket, threading
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ffprobe

LOG = open(sys.argv[3], "w"); LK = threading.Lock()

def bound_connect(host, port, timeout):
    for _ in range(5):
        sp = ffprobe.PORTS.get()
        s = ffprobe.PSock(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            s.bind(("", sp))
        except OSError:
            s.close(); ffprobe.PORTS.put(sp); continue
        s.sp = sp
        with LK: LOG.write(f"{sp}\t{host}\t{port}\n"); LOG.flush()
        s.settimeout(timeout)
        try:
            s.connect((host, port))
        except Exception:
            s.close(); raise
        return s
    raise OSError("no source port")

ffprobe.levin.connect = bound_connect
tg = []
for l in open(sys.argv[1]):
    a = l.split()
    if len(a) >= 2: tg.append((a[0], int(a[1]), a[2] if len(a) > 2 else ""))
random.shuffle(tg)
ffprobe.run(tg, sys.argv[2], int(sys.argv[4]) if len(sys.argv) > 4 else 48)
