# Break-even number of ASes across simulation seeds and price ratios (fleet runs, Section 5.2)
library(data.table)
f <- list.files("results", pattern = "^supply_2026_breakeven_seed.*csv$", full.names = TRUE)
d <- rbindlist(lapply(f, fread), fill = TRUE)
be <- function(x) {   # interpolate K where AS dedup reaches the /24 dedup value at the same seed/ratio
  a <- x[grouping == "asn"][order(K)]; base <- mean(x[grouping == "s24", mean])
  i <- which(a$mean >= base)[1]
  if (is.na(i) || i == 1) return(NA_real_)
  a$K[i - 1] + (base - a$mean[i - 1]) / (a$mean[i] - a$mean[i - 1]) * (a$K[i] - a$K[i - 1])
}
seeds <- d[ratio == 1, .(breakeven = be(.SD), s24 = mean(mean[grouping == "s24"])), by = seed]
print(seeds)
cat("break-even mean", mean(seeds$breakeven), "sd", sd(seeds$breakeven), "range", range(seeds$breakeven), "\n")
# AS dedup outcome by K across price ratios, against the /24 baseline of the full fleet (ratio 1)
asn <- dcast(d[grouping == "asn"], K ~ ratio, value.var = "mean", fun.aggregate = mean)
print(asn)
base1 <- d[ratio == 1 & grouping == "s24", mean(mean)]
rbe <- d[, .(breakeven.vs.full.bulk = { a <- .SD[grouping == "asn"][, .(m = mean(mean)), by = K][order(K)]; i <- which(a$m >= base1)[1]
  a$K[i - 1] + (base1 - a$m[i - 1]) / (a$m[i] - a$m[i - 1]) * (a$K[i] - a$K[i - 1]) }), by = ratio]
print(rbe)
res <- list(seed_be_mean = mean(seeds$breakeven), seed_be_sd = sd(seeds$breakeven), seed_be_min = min(seeds$breakeven),
  seed_be_max = max(seeds$breakeven), n_seeds = nrow(seeds), s24_base = base1, ratio_be = setNames(rbe$breakeven.vs.full.bulk, rbe$ratio))
jsonlite::write_json(res, "results/breakeven.json", auto_unbox = TRUE, digits = 6)
fwrite(dcast(d, K + ratio ~ grouping, value.var = "mean", fun.aggregate = mean), "results/breakeven-grid.csv")
