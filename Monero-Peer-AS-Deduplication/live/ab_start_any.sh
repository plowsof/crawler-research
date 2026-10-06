#!/bin/bash
# Live A/B for the asmap paper: 6 monerod --no-sync instances, 3 with --asmap=embedded, 3 control.
cd "$(dirname "$0")"
for i in 0 1 2 3 4 5; do
  p2p=$((48180+i)); rpc=$((48190+i)); mkdir -p inst$i
  extra=""; [ $((i%2)) -eq 0 ] && extra="--asmap=embedded"
  ss -ltn | grep -q ":$p2p \|:$rpc " && { echo "port busy $p2p/$rpc"; continue; }
  setsid -f nice -n 10 ./monerod --non-interactive --no-sync --out-peers 12 --in-peers 0 --hide-my-port --no-igd --no-zmq \
    --data-dir "$PWD/inst$i" --p2p-bind-port $p2p --rpc-bind-ip 127.0.0.1 --rpc-bind-port $rpc \
    --log-level 0 --max-log-file-size 20000000 $extra > inst$i/stdout.log 2>&1 < /dev/null
  echo "inst$i p2p=$p2p rpc=$rpc ${extra:-control}"
done
