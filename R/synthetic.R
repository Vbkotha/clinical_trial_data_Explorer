# Synthetic CDISC-like ADaM data for development and demos (base R only).
# Replace with read_study_files() for real studies.

make_synthetic_study <- function(study_id = "STUDY-001", n = 60, seed = 42) {
  set.seed(seed)
  arms <- c("Drug X 10 mg", "Drug X 20 mg", "Placebo")
  armcd <- c("ARM A", "ARM B", "ARM C")
  dose_mg <- c(10, 20, 0)

  a <- sample(1:3, n, replace = TRUE)
  usubjid <- sprintf("%s-%03d", study_id, seq_len(n))
  trtsdt <- as.Date("2026-01-05") + sample(0:120, n, replace = TRUE)

  ADSL <- data.frame(
    STUDYID = study_id, USUBJID = usubjid, SUBJID = sprintf("%03d", seq_len(n)),
    SITEID = sample(c("S01", "S02", "S03", "S04"), n, replace = TRUE),
    AGE = round(rnorm(n, 62, 9)), SEX = factor(sample(c("F", "M"), n, replace = TRUE)),
    ARM = factor(arms[a], levels = arms), ARMCD = factor(armcd[a], levels = armcd),
    ACTARM = factor(arms[a], levels = arms), ACTARMCD = factor(armcd[a], levels = armcd),
    TRT01P = factor(arms[a], levels = arms), TRT01A = factor(arms[a], levels = arms),
    TRT01AN = a, TRTSDT = trtsdt, SAFFL = "Y", ITTFL = "Y",
    stringsAsFactors = FALSE
  )

  # --- Labs (weekly, 12 weeks) with a dose-dependent platelet dip -------------
  days <- seq(0, 84, by = 7)
  params <- list(
    PLAT = list(name = "Platelets (10^9/L)",  unit = "10^9/L", base = 220, sd = 40, lo = 150, hi = 400, eff = -6.0),
    HGB  = list(name = "Hemoglobin (g/dL)",   unit = "g/dL",   base = 12.5, sd = 1.2, lo = 12, hi = 17, eff = -0.06),
    WBC  = list(name = "Leukocytes (10^9/L)", unit = "10^9/L", base = 6.5, sd = 1.5, lo = 4, hi = 11, eff = -0.12),
    NEUT = list(name = "Neutrophils (10^9/L)", unit = "10^9/L", base = 4.0, sd = 1.0, lo = 1.8, hi = 7.5, eff = -0.09)
  )
  lb <- list()
  for (i in seq_len(n)) {
    d <- dose_mg[a[i]]
    for (pc in names(params)) {
      p <- params[[pc]]
      base <- max(rnorm(1, p$base, p$sd), p$base * 0.5)
      # nadir around day 21-28 of each 28-day cycle, deeper with dose
      shape <- -cos(2 * pi * days / 28) * 0.5 + 0.5
      val <- base + p$eff * d * shape * runif(1, 0.6, 1.4) + rnorm(length(days), 0, p$sd * 0.15)
      val <- pmax(round(val, 1), 0.1)
      lb[[length(lb) + 1]] <- data.frame(
        STUDYID = study_id, USUBJID = usubjid[i], PARAMCD = pc, PARAM = p$name,
        AVISIT = factor(ifelse(days == 0, "BASELINE", paste("WEEK", days / 7)),
                        levels = c("BASELINE", paste("WEEK", 1:12))),
        AVISITN = days / 7, ADY = days + 1, ADT = trtsdt[i] + days,
        AVAL = val, AVALU = p$unit, BASE = val[1], CHG = val - val[1],
        PCHG = 100 * (val - val[1]) / val[1], ANRLO = p$lo, ANRHI = p$hi,
        stringsAsFactors = FALSE
      )
    }
  }
  ADLB <- do.call(rbind, lb)
  ADLB$ANRIND <- ifelse(ADLB$AVAL < ADLB$ANRLO, "LOW", ifelse(ADLB$AVAL > ADLB$ANRHI, "HIGH", "NORMAL"))

  # --- Exposure: weekly doses, held when platelets < 75 ------------------------
  ex <- list()
  for (i in seq_len(n)) {
    plat <- ADLB[ADLB$USUBJID == usubjid[i] & ADLB$PARAMCD == "PLAT", ]
    for (k in seq_along(days)[-length(days)]) {
      held <- plat$AVAL[k] < 75
      reduced <- !held && plat$AVAL[k] < 100 && dose_mg[a[i]] > 0
      amt <- if (held) 0 else if (reduced) dose_mg[a[i]] / 2 else dose_mg[a[i]]
      ex[[length(ex) + 1]] <- data.frame(
        STUDYID = study_id, USUBJID = usubjid[i], PARAMCD = "DOSE", PARAM = "Dose administered (mg)",
        AVAL = amt, AVALU = "mg", ASTDY = days[k] + 1, AENDY = days[k] + 7,
        ASTDT = trtsdt[i] + days[k], AENDT = trtsdt[i] + days[k] + 6,
        EXADJ = if (held) "DOSE HELD" else if (reduced) "DOSE REDUCED" else "",
        stringsAsFactors = FALSE
      )
    }
  }
  ADEX <- do.call(rbind, ex)

  # --- Response: assessments every 4 weeks, better on higher dose -------------
  rs <- list()
  lv <- c("CR", "PR", "SD", "PD")
  for (i in seq_len(n)) {
    pr <- switch(a[i], c(.15, .30, .35, .20), c(.25, .35, .25, .15), c(.03, .10, .47, .40))
    for (dy in c(29, 57, 85)) {
      rs[[length(rs) + 1]] <- data.frame(
        STUDYID = study_id, USUBJID = usubjid[i], PARAMCD = "OVRLRESP",
        PARAM = "Overall Response by Investigator", AVALC = sample(lv, 1, prob = pr),
        ADY = dy, ADT = trtsdt[i] + dy - 1, stringsAsFactors = FALSE
      )
    }
  }
  ADRS <- do.call(rbind, rs)
  ADRS$AVALC <- factor(ADRS$AVALC, levels = lv)

  # --- Adverse events ---------------------------------------------------------
  ae_terms <- data.frame(
    AEDECOD = c("Thrombocytopenia", "Anaemia", "Neutropenia", "Fatigue", "Nausea", "Epistaxis", "Headache"),
    AEBODSYS = c("Blood and lymphatic system disorders", "Blood and lymphatic system disorders",
                 "Blood and lymphatic system disorders", "General disorders", "Gastrointestinal disorders",
                 "Respiratory disorders", "Nervous system disorders"),
    stringsAsFactors = FALSE
  )
  ae <- list()
  for (i in seq_len(n)) {
    k <- rpois(1, 1 + dose_mg[a[i]] / 10)
    if (k == 0) next
    t <- ae_terms[sample(nrow(ae_terms), k, replace = TRUE), ]
    ae[[length(ae) + 1]] <- data.frame(
      STUDYID = study_id, USUBJID = usubjid[i], AESEQ = seq_len(k), t,
      AETOXGR = sample(as.character(1:4), k, replace = TRUE, prob = c(.45, .3, .2, .05)),
      ASTDY = sort(sample(1:84, k, replace = TRUE)), stringsAsFactors = FALSE
    )
  }
  ADAE <- do.call(rbind, ae)

  # --- Patient diary (ePRO free text with timestamps) -------------------------
  phrases <- c(
    "Felt tired most of the afternoon, napped for two hours.",
    "Noticed some bruising on my left arm, not sure from what.",
    "Small nosebleed in the morning, stopped after 10 minutes.",
    "Good day, walked to the shops and back.",
    "Mild headache after the injection, took paracetamol.",
    "Gums bled a little when brushing teeth.",
    "Appetite back to normal today.",
    "Slept badly, felt breathless climbing the stairs.",
    "Nausea after breakfast, better by lunch.",
    "No complaints today."
  )
  cats <- c("Fatigue", "Bleeding/bruising", "Bleeding/bruising", "General", "Pain",
            "Bleeding/bruising", "General", "Fatigue", "GI", "General")
  dy <- list()
  for (i in seq_len(n)) {
    k <- sample(4:14, 1)
    idx <- sample(seq_along(phrases), k, replace = TRUE,
                  prob = c(2, 1 + dose_mg[a[i]] / 5, 1 + dose_mg[a[i]] / 7, 3, 1, 1 + dose_mg[a[i]] / 8, 2, 1, 1, 3))
    ady <- sort(sample(1:84, k))
    tm <- as.POSIXct(trtsdt[i] + ady - 1) + sample(7:22, k, replace = TRUE) * 3600 + sample(0:59, k, replace = TRUE) * 60
    dy[[i]] <- data.frame(
      STUDYID = study_id, USUBJID = usubjid[i], DIARYSEQ = seq_len(k),
      ADTM = tm, ADY = ady, DIARYCAT = cats[idx], DIARYTXT = phrases[idx],
      stringsAsFactors = FALSE
    )
  }
  ADDIARY <- do.call(rbind, dy)

  list(ADSL = ADSL, ADEX = ADEX, ADLB = ADLB, ADRS = ADRS, ADAE = ADAE, ADDIARY = ADDIARY)
}

#' Write demo "final" TFL PDFs plus a checksum manifest for a completed study.
make_demo_tfls <- function(datasets, dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  out <- list(
    list(id = "T-14.1.1", title = "Demographics, Safety Population", type = "Table"),
    list(id = "F-14.3.1", title = "Mean platelet count over time by arm", type = "Figure"),
    list(id = "L-16.2.7", title = "Listing of grade >=3 adverse events", type = "Listing")
  )
  for (o in out) {
    f <- file.path(dir, paste0(o$id, ".pdf"))
    grDevices::pdf(f, width = 8.27, height = 11.69)
    graphics::plot.new()
    graphics::title(main = paste(o$id, o$title), sub = "FINAL - database locked - demo output")
    if (o$type == "Figure") {
      lb <- merge(datasets$ADLB[datasets$ADLB$PARAMCD == "PLAT", ], datasets$ADSL[, c("USUBJID", "ARM")])
      m <- aggregate(AVAL ~ ADY + ARM, lb, mean)
      graphics::par(new = TRUE)
      graphics::plot(m$ADY, m$AVAL, col = as.integer(m$ARM), pch = 19, xlab = "Study day", ylab = "Platelets")
    }
    grDevices::dev.off()
  }
  files <- file.path(dir, paste0(vapply(out, `[[`, "", "id"), ".pdf"))
  manifest <- data.frame(
    output_id = vapply(out, `[[`, "", "id"),
    title = vapply(out, `[[`, "", "title"),
    type = vapply(out, `[[`, "", "type"),
    file = basename(files),
    sha256 = vapply(files, function(f) digest::digest(file = f, algo = "sha256"), ""),
    stringsAsFactors = FALSE
  )
  utils::write.csv(manifest, file.path(dir, "manifest.csv"), row.names = FALSE)
  invisible(manifest)
}
