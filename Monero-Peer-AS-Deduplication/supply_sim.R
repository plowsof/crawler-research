# Supply-constrained adversary response (October 2026 data). The adversary keeps the size of the observed
# suspected spy fleet and spreads it evenly over the K ASNs where it can rent servers, each node in its own /24:
#   K9   : the 9 ASNs whose cheapest public-IPv4 VPS price was verified (data/prices/supply.csv)
#   K99  : the datacenter ASNs (X4BNet list) that host at least one honest reachable node
#   K933 : all ASNs in the X4BNet datacenter list
#   Kn (with arguments) : K99 plus a random sample of the other listed ASNs, for the break-even search
# Prices are assumed equal across ASNs (verified range for K9: USD 3.00-6.72 per month).
library(data.table)
source("sim.R")
setDTthreads(1)

nodes <- fread("data/nodes.csv", colClasses = list(character = c("s16", "s24")))
honest <- nodes[label == "honest"]
# SEED: simulation seed (default 314); RATIO: price of a node in another ASN relative to a bulk node,
# so the adversary affords fleet/RATIO nodes (default 1); GROUPINGS: rules to simulate
SEED <- as.integer(Sys.getenv("SEED", "314")); RATIO <- as.numeric(Sys.getenv("RATIO", "1"))
GROUPINGS <- strsplit(Sys.getenv("GROUPINGS", "s24,asn,hybrid"), ",")[[1]]
fleet <- floor(nodes[label != "honest", .N] / RATIO)
supply <- fread("data/prices/supply.csv")
dc <- as.numeric(sub("^AS", "", regmatches(readLines("data/x4b_datacenter_ASN.txt"),
  regexpr("^AS[0-9]+", readLines("data/x4b_datacenter_ASN.txt")))))
dc <- unique(dc)

args <- commandArgs(trailingOnly = TRUE)
sets <- list(
  K9 = unique(supply$asn),
  K99 = intersect(dc, unique(honest$asn)),
  K933 = dc)
if (length(args)) {
  # break-even search: the 99 datacenter ASNs with honest nodes plus a random sample of the other listed ones
  set.seed(1)
  others <- sample(setdiff(dc, sets$K99))
  sets <- setNames(lapply(as.integer(args), function(k) c(sets$K99, others)[seq_len(k)]), paste0("K", args))
}

res <- list()
for (k in names(sets)) {
  asns <- sets[[k]]
  asn.of.node <- rep_len(asns, fleet)
  synth <- data.table(ip = paste0("synthetic-", seq_len(fleet)), s16 = paste0("syn16-", seq_len(fleet)),
    s24 = paste0("syn24-", seq_len(fleet)), asn = asn.of.node, label = "spy", own = 0)
  d <- rbind(honest, synth, fill = TRUE)
  for (grouping in GROUPINGS) {
    set.seed(SEED)
    net <- gen.network.grouped(d, grouping, n.unreachable = 0, compute.network.stats = FALSE)
    x <- net$nodes[malicious == FALSE]
    res[[length(res) + 1]] <- data.table(scenario = k, K = length(asns), grouping = grouping, seed = SEED, ratio = RATIO,
      n.adversary = fleet, mean = mean(x$n.malicious.outbound), max = max(x$n.malicious.outbound))
    message(k, " K=", length(asns), " ", grouping, " mean ", round(mean(x$n.malicious.outbound), 3))
  }
}
suffix <- if (SEED != 314 || RATIO != 1) sprintf("_seed%d_r%s", SEED, RATIO) else ""
fwrite(rbindlist(res), paste0(if (length(args)) "results/supply_2026_breakeven" else "results/supply_2026", suffix, ".csv"))
