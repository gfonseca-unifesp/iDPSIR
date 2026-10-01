# =====================================================
# Sri Lanka example - is "aid -> fleet capacity" supported by the data?
# =====================================================
#
# Revisao 3, E3.2, done fairly. Dropping the two aid -> fleet links removes
# the only two fitted parameters, so the variant fits worse by construction.
# Three comparisons that do not favour the model with more parameters:
#   (a) AIC / BIC from the residual sum of squares, 2006-2021;
#   (b) out of sample: every model fitted on 2006-2014, tested on 2015-2021;
#   (c) a rival with the same number of free parameters: no aid -> fleet, but
#       the rise in effort explained by the fleet's own growth (growth_rate of
#       D3) and by demand -> effort (beta D2 -> P1), both fitted.
# Everything runs through the app's engine via simulate_effort() (calibrate.R).
#
#   Rscript analysis/validation_srilanka/variant_test.R   (from the repository root)

if (!exists("simulate_effort")) {
  old <- setwd("tests/testthat"); suppressMessages(source("helper-setup.R")); setwd(old)
  source("analysis/validation_srilanka/calibrate.R")
}

VT_FIT <- 2006:2014
VT_TEST <- 2015:2021
VT_ALL <- 2006:2021

# Effort for a model: `aid` = the two aid betas; `rival` = c(growth of D3,
# beta D2 -> P1) or NULL to keep the published values.
vt_effort <- function(d, aid, rival = NULL, last_year = 2021) {
  if (!is.null(rival)) {
    g <- d$g
    igraph::V(g)$growth_rate[igraph::V(g)$name == "D3"] <- rival[1]
    e <- igraph::ends(g, igraph::E(g), names = TRUE)
    igraph::E(g)$weight[e[, 1] == "D2" & e[, 2] == "P1"] <- rival[2]
    d$g <- g
  }
  simulate_effort(d, aid, last_year)
}

vt_sse <- function(d, years, aid, rival = NULL) {
  yrs <- as.character(years)
  sum((d$obs[yrs] - vt_effort(d, aid, rival, max(years))[yrs])^2)
}

# Least squares over the free parameters of one model.
vt_fit <- function(d, model, years) {
  switch(model,
    aid = {
      f <- function(b) if (any(b < 0)) 1e30 else vt_sse(d, years, b)
      o <- stats::optim(c(0.3, 0.1), f, control = list(reltol = 1e-12, maxit = 2000))
      list(aid = o$par, rival = NULL, k = 2)
    },
    no_aid = list(aid = c(0, 0), rival = NULL, k = 0),
    rival = {
      f <- function(r) if (r[1] < 0 || r[1] > 0.5 || r[2] < 0 || r[2] > 1.5) 1e30 else vt_sse(d, years, c(0, 0), r)
      starts <- list(c(0.01, 0.45), c(0.05, 0.45), c(0.1, 0.8), c(0.03, 1))
      best <- NULL
      for (s in starts) {
        o <- stats::optim(s, f, control = list(reltol = 1e-12, maxit = 2000))
        if (is.null(best) || o$value < best$value) best <- o
      }
      list(aid = c(0, 0), rival = best$par, k = 2)
    })
}

vt_ic <- function(sse, n, k) {
  c(aic = n * log(sse / n) + 2 * k, bic = n * log(sse / n) + k * log(n))
}

run_variant_test <- function(root = ".", out_dir = "analysis/validation_srilanka/out") {
  d <- load_srilanka(root)
  models <- c(aid = "Aid -> fleet (published, 2 aid betas fitted)",
              no_aid = "No aid -> fleet (nothing fitted)",
              rival = "No aid -> fleet; fleet growth and demand -> effort fitted")
  rows <- lapply(names(models), function(m) {
    full <- vt_fit(d, m, VT_ALL)
    sse_all <- vt_sse(d, VT_ALL, full$aid, full$rival)
    ic <- vt_ic(sse_all, length(VT_ALL), full$k)
    part <- vt_fit(d, m, VT_FIT)
    yrs <- as.character(VT_TEST)
    st <- fit_stats(d$obs[yrs], vt_effort(d, part$aid, part$rival)[yrs])
    data.frame(model = m, description = models[[m]], k = full$k,
               rmse_2006_2021 = sqrt(sse_all / length(VT_ALL)), aic = ic[["aic"]], bic = ic[["bic"]],
               rmse_test_2015_2021 = st[["rmse"]], nse_test = st[["nse"]], bias_test = st[["bias"]],
               params_2006_2021 = if (full$k == 0) "-" else paste(signif(if (m == "aid") full$aid else full$rival, 3), collapse = "; "),
               stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  out$delta_aic <- out$aic - min(out$aic)
  out$delta_bic <- out$bic - min(out$bic)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  utils::write.csv(out, file.path(out_dir, "variant_test.csv"), row.names = FALSE)
  out
}

if (sys.nframe() == 0) print(run_variant_test(), digits = 4)
