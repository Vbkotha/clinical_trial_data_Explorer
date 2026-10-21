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
        stop("Unsupported file type: ", f[1])
      )
    })
  }
  ds[intersect(unlist(study_cfg$datasets), names(ds))]
}

build_join_keys <- function(datanames) {
  cdisc <- intersect(datanames, names(teal.data::default_cdisc_join_keys))
  jk <- teal.data::default_cdisc_join_keys[cdisc]
  if ("ADDIARY" %in% datanames) {
    jk <- c(jk, teal.data::join_keys(
      teal.data::join_key("ADDIARY", "ADDIARY", c("STUDYID", "USUBJID", "DIARYSEQ")),
      teal.data::join_key("ADSL", "ADDIARY", c("STUDYID", "USUBJID"))
    ))
  }
  jk
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
          ds <- apply_policy(ds, policy)
          assert_policy(ds, policy)            # fail closed

          td <- do.call(teal.data::teal_data, ds)
          teal.data::join_keys(td) <- build_join_keys(names(ds))
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
