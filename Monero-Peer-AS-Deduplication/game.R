# Game between the peer selection protocol (/24 deduplication vs ASN deduplication) and an adversary
# (bulk nodes in few ASNs vs one node per distinct ASN). Follows the structure of Rucknium's
# subnet-deduplication-game-theory.R.
library(data.table)
library(ggplot2)

load.nodes <- function(f) fread(f, colClasses = list(character = c("s16", "s24")))

game.inputs <- function(nodes) {
  h <- nodes[label == "honest"]
  a <- nodes[label != "honest"]
  list(
    h_s  = nrow(h),
    H24  = uniqueN(h$s24),
    HA   = uniqueN(h$asn),
    a_n  = nrow(a),
    a_24 = uniqueN(a$s24),
    m    = uniqueN(a$asn),
    # exact single-draw probability of selecting an adversary node for the observed nodes,
    # i.e. mean over groups of the adversary share inside the group
    p_obs_24  = nodes[, .(s = mean(label != "honest")), by = s24][, mean(s)],
    p_obs_asn = nodes[, .(s = mean(label != "honest")), by = asn][, mean(s)])
}

# Payoffs (probability that one draw selects an adversary node), adversary spends budget b.
#   w24: price of one node in a /24 not shared with honest nodes, in few ASNs ("bulk")
#   wA : price of one node in an ASN not shared with honest nodes ("ASN-distinct")
#   m  : number of ASNs the bulk strategy occupies
payoffs <- function(H24, HA, m, b, w24, wA) {
  c(p_ss = b / (w24 * H24 + b),          # /24 dedup  vs bulk
    p_sa = b / (wA * H24 + b),           # /24 dedup  vs ASN-distinct (each node is also /24-distinct)
    p_as = m / (HA + m),                 # ASN dedup  vs bulk (upper bound: m adversary-only groups)
    p_aa = b / (wA * HA + b))            # ASN dedup  vs ASN-distinct
}

# Protocol commits first, adversary best-responds (Stackelberg)
stackelberg <- function(p) {
  c(subnet24 = max(p[["p_ss"]], p[["p_sa"]]), asmap = max(p[["p_as"]], p[["p_aa"]]))
}

# Simultaneous 2x2 zero-sum game, mixed-strategy Nash equilibrium (Theorem 1.2 of Sun (2022),
# the same formulas as Rucknium's paper). Rows: protocol (subnet24, asmap). Columns: adversary (bulk, ASN-distinct).
nash <- function(p) {
  a11 <- p[["p_ss"]]; a12 <- p[["p_sa"]]; a21 <- p[["p_as"]]; a22 <- p[["p_aa"]]
  unique.mixed <- (a11 - a12) * (a22 - a21) > 0 && (a11 - a21) * (a22 - a12) > 0
  if (!unique.mixed) return(c(P_protocol_subnet24 = NA, P_adversary_bulk = NA, u_adversary = NA))
  d <- a11 - a12 - a21 + a22
  c(P_protocol_subnet24 = (a22 - a21) / d,
    P_adversary_bulk = (a22 - a12) / d,
    u_adversary = (a11 * a22 - a12 * a21) / d)
}

threshold <- function(H24, HA) H24 / HA
