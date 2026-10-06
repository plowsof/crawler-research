#!/bin/bash
# Per-AS Dandelion++ stem test: 4 monerod --no-sync instances (same build), 6 and 8 with MONERO_DANDELIONPP_STEM_ASN=1,
# 7 and 9 control; all log their stems (category net.dandelionpp.stems) at every epoch and stem change.
cd "$(dirname "$0")"
for i in 6 7 8 9; do
  p2p=$((48180+i)); rpc=$((48190+i)); mkdir -p inst$i
  env=""; [ $((i%2)) -eq 0 ] && env="MONERO_DANDELIONPP_STEM_ASN=1"
  ss -ltn | grep -q ":$p2p \|:$rpc " && { echo "port busy $p2p/$rpc"; continue; }
  env $env setsid -f nice -n 10 ./monerod-stem --non-interactive --no-sync --out-peers 12 --in-peers 0 --hide-my-port --no-igd --no-zmq \
    --data-dir "$PWD/inst$i" --p2p-bind-port $p2p --rpc-bind-ip 127.0.0.1 --rpc-bind-port $rpc \
    --log-level 0,net.dandelionpp.stems:INFO --max-log-file-size 20000000 > inst$i/stdout.log 2>&1 < /dev/null
  echo "inst$i p2p=$p2p rpc=$rpc ${env:-control}"
done
