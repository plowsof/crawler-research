# Runs the network simulations for the paper and writes LaTeX tables and figures.
# Follows Rucknium's subnet-deduplication-plots-and-simulations.R.
library(data.table)
source("sim.R")
setDTthreads(1)
dir.create("pdf/tables", recursive = TRUE, showWarnings = FALSE)
dir.create("pdf/images", recursive = TRUE, showWarnings = FALSE)

datasets <- list(
  "2026" = fread("data/nodes.csv", colClasses = list(character = c("s16", "s24"))),
  "2025" = fread("data/nodes_2025.csv", colClasses = list(character = c("s16", "s24"))))

scenarios <- rbind(
  CJ(dataset = c("2026", "2025"), grouping = c("s24", "asn"), share.reachable = c(0.20, 0.10), sorted = FALSE),
  CJ(dataset = c("2026", "2025"), grouping = "hybrid", share.reachable = c(0.20, 0.10), sorted = FALSE))
scenarios[, name := paste0(dataset, "_", c(s24 = "subnet24", asn = "asmap", hybrid = "hybrid")[grouping], "_",
  100 * (1 - share.reachable), "_percent_unreachable")]

args <- commandArgs(trailingOnly = TRUE)
todo <- if (length(args)) as.integer(args) else seq_len(nrow(scenarios))

for (i in todo) {
  s <- scenarios[i]
  nodes <- datasets[[s$dataset]]
  n.unreachable <- floor(nrow(nodes) * ((1 - s$share.reachable) / s$share.reachable))
  set.seed(314)
  t0 <- Sys.time()
  net <- gen.network.grouped(nodes, s$grouping, n.unreachable = n.unreachable)
  message(s$name, " done in ", format(Sys.time() - t0))
  net$edgelist <- NULL
  saveRDS(net, paste0("results/", s$name, ".rds"))
}
