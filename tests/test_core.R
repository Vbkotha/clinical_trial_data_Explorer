# Unit tests for the pure (non-teal) logic: access, blinding, diary, plots.
#   Rscript -e 'testthat::test_file("tests/test_core.R")'
library(testthat)
root <- if (file.exists("app.R")) "." else ".."
for (f in c("access.R", "auth.R", "synthetic.R", "tm_exposure_hem.R", "tm_diary.R", "tm_graph_builder.R"))
  source(file.path(root, "R", f))
studies <- yaml::read_yaml(file.path(root, "config/studies.yml"))
roles   <- yaml::read_yaml(file.path(root, "config/roles.yml"))
ds <- make_synthetic_study("STUDY-001", n = 30, seed = 1)

test_that("roles: deny by default, most privileged wins", {
  expect_null(resolve_role(character(0), "STUDY-001", roles))
  expect_null(resolve_role("random-group", "STUDY-001", roles))
  expect_null(resolve_role("study001-dmc", "UNKNOWN", roles))
  expect_equal(resolve_role("study001-study-team", "STUDY-001", roles), "blinded")
  expect_equal(resolve_role(c("study001-study-team", "study001-dmc"), "STUDY-001", roles), "unblinded")
})

test_that("blinded policy masks arm variables everywhere and drops ADEX", {
  pol <- access_policy(studies[["STUDY-001"]], "blinded")
  out <- apply_policy(ds, pol)
  expect_false("ADEX" %in% names(out))
  expect_equal(unique(as.character(out$ADSL$ARM)), "BLINDED")
  expect_true(all(is.na(out$ADSL$TRT01AN)))
  expect_true(all(out$ADDIARY$DIARYTXT == "[text restricted for your role]"))
  expect_silent(assert_policy(out, pol))
})

test_that("assert_policy fails closed on a leak", {
  pol <- access_policy(studies[["STUDY-001"]], "blinded")
  out <- apply_policy(ds, pol)
  out$ADLB$ARM <- "Placebo"                 # e.g. ARM merged onto ADLB after masking
  expect_error(assert_policy(out, pol), "unmasked")
  expect_error(assert_policy(c(out, list(ADEX = ds$ADEX)), pol), "ADEX")
})

test_that("unblinded and completed-study policies keep data", {
  pol <- access_policy(studies[["STUDY-001"]], "unblinded")
  out <- apply_policy(ds, pol)
  expect_true("ADEX" %in% names(out))
  expect_true(length(unique(out$ADSL$ARM)) > 1)
  expect_error(access_policy(studies[["STUDY-002"]], "blinded"), "not valid")
  v <- access_policy(studies[["STUDY-002"]], "viewer")
  expect_true(v$hide_diary_text)
})

test_that("diary highlighting escapes HTML before marking", {
  x <- highlight_terms("<script>alert(1)</script> bruising & bleeding", "bruis, bleed")
  expect_false(grepl("<script>", x, fixed = TRUE))
  expect_true(grepl("<mark>bruis</mark>ing", x, fixed = TRUE))
  expect_true(grepl("<mark>bleed</mark>ing", x, fixed = TRUE))
  expect_true(grepl("&amp;", x, fixed = TRUE))
  f <- filter_diary(ds$ADDIARY, "nosebleed, gums")
  expect_true(nrow(f) > 0 && all(grepl("nosebleed|gums", tolower(f$DIARYTXT))))
})

test_that("cross-dimension summaries compute per subject", {
  s <- cohort_window_summary(ds$ADSL, ds$ADEX, ds$ADLB, ds$ADRS, "PLAT", c(1, 42), "cumulative_dose", "nadir")
  expect_equal(nrow(s), 30)
  expect_true(all(c("exposure", "lab", "best_response", "ARM") %in% names(s)))
  pp <- patient_profile_data(ds$ADEX, ds$ADLB, ds$ADRS, ds$ADSL$USUBJID[1], c("PLAT", "HGB"), c(1, 85))
  expect_setequal(levels(pp$panel), c("Dose (mg)", unique(ds$ADLB$PARAM[ds$ADLB$PARAMCD %in% c("PLAT","HGB")]), "Response"))
  # blinded: no ADEX still works
  pp2 <- patient_profile_data(NULL, ds$ADLB, ds$ADRS, ds$ADSL$USUBJID[1], "PLAT", c(1, 85))
  expect_false("Dose (mg)" %in% levels(pp2$panel))
})

test_that("every preset renders", {
  presets <- yaml::read_yaml(file.path(root, "config/graph_presets.yml"))
  for (nm in names(presets)) {
    p <- build_graph(with_adsl(ds, presets[[nm]]$dataset), presets[[nm]])
    expect_s3_class(p, "ggplot")
    expect_silent(ggplot2::ggplot_build(p))
  }
})
