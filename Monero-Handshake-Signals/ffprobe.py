#!/usr/bin/env python3
"""Friend-or-Foe active signals: one handshake per target, keep the full peer list.
Client sockets bind to source ports 41000-48999 so a parallel tcpdump can isolate
the replies (first-segment check). usage: ffprobe.py targets.txt out.jsonl [workers]"""
import sys, json, time, socket, random, threading, queue
import levin

PORTS = queue.Queue()
for p in range(41000, 49000): PORTS.put(p)

class PSock(socket.socket):
    sp = None
    def close(self):
        super().close()
        if self.sp is not None:
            PORTS.put(self.sp); self.sp = None

def bound_connect(host, port, timeout):
    for _ in range(5):
        sp = PORTS.get()
        s = PSock(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            s.bind(("", sp))
        except OSError:
            s.close(); PORTS.put(sp); continue
        s.sp = sp
        s.settimeout(timeout)
        try:
            s.connect((host, port))
        except Exception:
            s.close(); raise
        return s
    raise OSError("no source port")

levin.connect = bound_connect

def run(targets, out, workers):
    q = queue.Queue()
    for t in targets: q.put(t)
    lock = threading.Lock()
    f = open(out, "a")
    def w():
        while True:
            try: ip, port, grp = q.get_nowait()
            except queue.Empty: return
            rec = {"ip": ip, "port": port, "grp": grp, "t": time.time()}
            try:
                r = levin.handshake(ip, port, timeout=12)
                rec.update(peer_id=r["peer_id"], np=len(r["peers"]),
                           peers=[[k, h, p, ls] for k, h, p, ls, *_ in r["peers"]])
            except Exception as e:
                rec["err"] = type(e).__name__
            with lock:
                f.write(json.dumps(rec) + "\n"); f.flush()
    ts = [threading.Thread(target=w) for _ in range(workers)]
    for t in ts: t.start()
    for t in ts: t.join()

if __name__ == "__main__":
    tg = []
    for l in open(sys.argv[1]):
        a = l.split()
        if len(a) >= 2: tg.append((a[0], int(a[1]), a[2] if len(a) > 2 else ""))
    random.shuffle(tg)
    run(tg, sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 64)
