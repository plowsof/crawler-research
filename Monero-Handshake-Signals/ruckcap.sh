#!/bin/bash
# One full-payload probe pass from this box. usage: ruckcap.sh <name> <workers>
cd "$(dirname "$0")" || exit 1
N=$1; W=${2:-48}
S=; [ "$(id -u)" = 0 ] || S="sudo -n"
IF=$(ip route get 1.1.1.1 | sed -n 's/.* dev \([^ ]*\).*/\1/p')
ulimit -n 8192
# hard 3 h cap so a missed stop can never leave tcpdump writing (a leftover filled a 438 G disk)
$S timeout -s INT 3h tcpdump -Z root -i "$IF" -nn -s 0 -U -w raw.pcap 'tcp portrange 41000-48999' > tcpdump.log 2>&1 &
sleep 3
date -u +%FT%TZ > start.txt
nice python3 ruckcap.py targets.txt probe.jsonl conns.tsv "$W" > probe.log 2>&1
date -u +%FT%TZ > end.txt
sleep 15; $S pkill -INT -f -- "tcpdump .*-w raw.pcap"
for _ in $(seq 30); do pgrep -f -- "tcpdump .*-w raw.pcap" >/dev/null || break; sleep 1; done
if pgrep -f -- "tcpdump .*-w raw.pcap" >/dev/null; then echo "tcpdump still running, not cutting" >&2; exit 1; fi
$S chown "$(id -u)" raw.pcap
python3 pcapcut.py raw.pcap conns.tsv "$N.pcap" > cut.log && rm -f raw.pcap
gzip -f "$N.pcap" probe.jsonl
echo done
