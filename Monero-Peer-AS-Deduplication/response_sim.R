# Adversary response simulation: replace the observed suspected spy nodes by a synthetic fleet with the
# same budget that puts one node in each of n new ASNs (each node also in its own /24), where
# n = (observed fleet size) / (price premium wA / w24). Simulates only the reachable honest nodes as
# originators: the per-node outbound selection does not depend on unreachable nodes, which only
# add more originators with the same distribution.
library(data.table)
source("sim.R")
setDTthreads(1)

args <- commandArgs(trailingOnly = TRUE)
dataset <- args[1]
file <- c("2026" = "data/nodes.csv", "2025" = "data/nodes_2025.csv")[[dataset]]
nodes <- fread(file, colClasses = list(character = c("s16", "s24")))
ratios <- c(1, 2, 3.46, 5, 10)

res <- list()
honest <- nodes[label == "honest"]
fleet <- nodes[label != "honest", .N]
for (strategy in c("observed", paste0("asn_distinct_r", ratios))) {
  if (strategy == "observed") {
    d <- nodes
  } else {
    r <- as.numeric(sub("asn_distinct_r", "", strategy))
    n <- floor(fleet / r)
    synth <- data.table(ip = paste0("synthetic-", seq_len(n)), s16 = paste0("syn16-", seq_len(n)),
      s24 = paste0("syn24-", seq_len(n)), asn = 4200000000 + seq_len(n), label = "spy", own = 0)
    d <- rbind(honest, synth, fill = TRUE)
  }
  for (grouping in c("s24", "asn", "hybrid")) {
    set.seed(314)
    net <- gen.network.grouped(d, grouping, n.unreachable = 0, compute.network.stats = FALSE)
    x <- net$nodes[malicious == FALSE]
    res[[length(res) + 1]] <- data.table(dataset = dataset, strategy = strategy, grouping = grouping,
      n.adversary = d[label != "honest", .N],
      mean = mean(x$n.malicious.outbound), median = median(x$n.malicious.outbound),
      q3 = quantile(x$n.malicious.outbound, 0.75), max = max(x$n.malicious.outbound))
    message(dataset, " ", strategy, " ", grouping, " mean ", round(mean(x$n.malicious.outbound), 3))
  }
}
fwrite(rbindlist(res), paste0("results/response_", dataset, ".csv"))
