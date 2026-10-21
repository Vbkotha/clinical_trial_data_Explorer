# Data loading: identity -> role -> policy -> blinded teal_data.
# Runs once per Shiny session, server-side.

read_study_datasets <- function(study_id, study_cfg) {
  if (identical(study_cfg$source, "synthetic")) {
    ds <- make_synthetic_study(study_id, seed = if (study_id == "STUDY-001") 1 else 2)
  } else {
    ds <- lapply(stats::setNames(nm = unlist(study_cfg$datasets)), function(nm) {
      f <- list.files(study_cfg$data_dir, pattern = paste0("^", tolower(nm), "\\."), full.names = TRUE,
                      ignore.case = TRUE)
      if (!length(f)) stop("Missing dataset ", nm, " in ", study_cfg$data_dir)
      switch(tolower(tools::file_ext(f[1])),
        rds      = readRDS(f[1]),
        parquet  = as.data.frame(arrow::read_parquet(f[1])),
        sas7bdat = as.data.frame(haven::read_sas(f[1])),
        xpt      = as.data.frame(haven::read_xpt(f[1])),
        csv      = parse_csv_dates(utils::read.csv(f[1], stringsAsFactors = FALSE, na.strings = c("", "NA"))),
        stop("Unsupported file type: ", f[1])
      )
    })
  }
  standardise_datasets(ds[intersect(unlist(study_cfg$datasets), names(ds))])
}

#' CSV has no column types: parse ADaM date (--DT) and datetime (--DTM) columns.
parse_csv_dates <- function(df) {
  for (v in grep("DTM$", names(df), value = TRUE)) if (is.character(df[[v]])) df[[v]] <- as.POSIXct(df[[v]], tz = "UTC")
  for (v in grep("DT$", names(df), value = TRUE)) if (is.character(df[[v]])) df[[v]] <- as.Date(df[[v]])
  df
}

# Common CDISC variable labels; anything else is labelled with its own name.
CDISC_LABELS <- c(
  STUDYID = "Study Identifier", USUBJID = "Unique Subject Identifier", SUBJID = "Subject Identifier",
  SITEID = "Study Site Identifier", AGE = "Age", SEX = "Sex", RACE = "Race",
  ARM = "Description of Planned Arm", ARMCD = "Planned Arm Code", ACTARM = "Description of Actual Arm",
  ACTARMCD = "Actual Arm Code", TRT01P = "Planned Treatment for Period 01",
  TRT01A = "Actual Treatment for Period 01", TRT01AN = "Actual Treatment for Period 01 (N)",
  TRTSDT = "Date of First Exposure to Treatment", SAFFL = "Safety Population Flag", ITTFL = "Intent-To-Treat Population Flag",
  PARAMCD = "Parameter Code", PARAM = "Parameter", AVAL = "Analysis Value", AVALC = "Analysis Value (C)",
  AVALU = "Analysis Value Unit", BASE = "Baseline Value", CHG = "Change from Baseline", PCHG = "Percent Change from Baseline",
  AVISIT = "Analysis Visit", AVISITN = "Analysis Visit (N)", ADY = "Analysis Relative Day", ADT = "Analysis Date",
  ANRLO = "Analysis Normal Range Lower Limit", ANRHI = "Analysis Normal Range Upper Limit", ANRIND = "Analysis Reference Range Indicator",
  AEDECOD = "Dictionary-Derived Term", AEBODSYS = "Body System or Organ Class", AETOXGR = "Analysis Toxicity Grade",
  AESEQ = "Sequence Number", ASTDY = "Analysis Start Relative Day", AENDY = "Analysis End Relative Day",
  ASTDT = "Analysis Start Date", AENDT = "Analysis End Date", EXADJ = "Reason for Dose Adjustment",
  DIARYSEQ = "Diary Sequence Number", ADTM = "Analysis Datetime", DIARYCAT = "Diary Category", DIARYTXT = "Diary Entry Text"
)

#' Give every column a "label" attribute (teal.modules.clinical tables need them).
#' Existing labels, e.g. from SAS/XPT files, are kept.
ensure_labels <- function(df) {
  for (v in names(df)) {
    if (is.null(attr(df[[v]], "label"))) attr(df[[v]], "label") <- if (v %in% names(CDISC_LABELS)) CDISC_LABELS[[v]] else v
  }
  df
}

#' Join keys from the columns each dataset actually has: the CDISC default primary
#' keys (or STUDYID/USUBJID) limited to existing columns, and every dataset with
#' USUBJID linked to ADSL so global ADSL filters apply. teal's defaults name
#' columns (e.g. ADAE ASTDTM/AETERM) that many datasets lack, which breaks merges.
build_join_keys <- function(ds) {
  def <- teal.data::default_cdisc_join_keys
  extra_pk <- list(ADDIARY = c("STUDYID", "USUBJID", "DIARYSEQ"))
  keys <- list()
  for (nm in names(ds)) {
    cols <- names(ds[[nm]])
    pk <- if (nm %in% names(def)) def[nm, nm] else extra_pk[[nm]] %||% c("STUDYID", "USUBJID")
    pk <- intersect(pk, cols)
    if (length(pk)) keys[[length(keys) + 1]] <- teal.data::join_key(nm, nm, pk)
    link <- intersect(c("STUDYID", "USUBJID"), cols)
    if (nm != "ADSL" && "ADSL" %in% names(ds) && "USUBJID" %in% link) {
      keys[[length(keys) + 1]] <- teal.data::join_key("ADSL", nm, link)
    }
  }
  do.call(teal.data::join_keys, keys)
}

#' teal_data_module that enforces access per session.
study_data_module <- function(study_id, study_cfg, roles_cfg, audit = audit_log) {
  teal::teal_data_module(
    label = "Study access",
    once = TRUE,
    ui = function(id) {
      ns <- shiny::NS(id)
      shiny::uiOutput(ns("status"))
    },
    server = function(id) {
      shiny::moduleServer(id, function(input, output, session) {
        ident  <- get_identity(session)
        err    <- NULL
        role   <- tryCatch(session_role(ident, study_id, study_cfg, roles_cfg),
                           error = function(e) { err <<- conditionMessage(e); NULL })
        policy <- if (!is.null(role)) tryCatch(access_policy(study_cfg, role),
                                               error = function(e) { err <<- conditionMessage(e); NULL })

        audit(ident$user %||% "<anonymous>", study_id, if (is.null(policy)) "DENIED" else role)

        # shared with analysis modules (role banner, module-level degradations)
        set_access(session, list(user = ident$user, role = if (!is.null(policy)) role, policy = policy,
                                 study_id = study_id, study = study_cfg))

        output$status <- shiny::renderUI({
          if (is.null(policy)) {
            shiny::div(class = "alert alert-danger",
                       err %||% paste0("No role for ", study_id, " (APP_GROUPS matched nothing in config/roles.yml). ",
                                       "Relaunch with APP_ROLE set."))
          }
        })

        shiny::reactive({
          shiny::validate(shiny::need(!is.null(policy), "Access denied."))
          ds <- read_study_datasets(study_id, study_cfg)
          issues <- check_study_data(ds, study_cfg)
          errs <- issues[issues$level == "error", ]
          shiny::validate(shiny::need(nrow(errs) == 0, paste(
            c("The study data does not match what the app needs:", paste0(errs$dataset, ": ", errs$message)),
            collapse = "\n")))
          ds <- apply_policy(ds, policy)
          assert_policy(ds, policy)            # fail closed
          ds <- lapply(ds, ensure_labels)      # after masking, which replaces columns

          td <- do.call(teal.data::teal_data, ds)
          teal.data::join_keys(td) <- build_join_keys(ds)
          td
        })
      })
    }
  )
}

#' Minimal audit trail: who opened which study under which role.
#' Point AUDIT_LOG at durable storage (or replace with the platform's audit API).
audit_log <- function(user, study_id, role) {
  line <- sprintf("%s\t%s\t%s\t%s\n", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), user, study_id, role)
  cat(line, file = Sys.getenv("AUDIT_LOG", state_dir("audit.log")), append = TRUE)
}
