# Access policy: role resolution + server-side blinding.
#
# Principle: blinding is applied to the data BEFORE it is handed to teal.
# Nothing downstream (filter panel, data table, "Show R code", reporter,
# bespoke graph builder) can reveal what is not in memory for that session.
# Hiding UI elements is NOT a blinding control.

ROLE_PRECEDENCE <- c("unblinded", "blinded", "viewer")

#' Map a user's groups to a single role for a study. Deny by default (NULL).
#' If a user is in several groups, the most privileged role wins, so keep the
#' unblinded groups small and audited.
resolve_role <- function(groups, study_id, roles_cfg) {
  study_roles <- roles_cfg[[study_id]]
  if (is.null(study_roles) || length(groups) == 0) return(NULL)
  for (role in ROLE_PRECEDENCE) {
    if (any(groups %in% study_roles[[role]])) return(role)
  }
  NULL
}

#' Build the data policy for a (study, role) pair.
access_policy <- function(study_cfg, role) {
  stopifnot(!is.null(role))
  completed <- identical(study_cfg$status, "completed")
  b <- study_cfg$blinding

  if (completed && role == "blinded") {
    stop("Role 'blinded' is not valid for a completed study - map the group to 'unblinded' or 'viewer'.")
  }
  if (!completed && role == "viewer") {
    stop("Role 'viewer' is only valid for completed studies.")
  }

  blinded <- !completed && role == "blinded"
  if (blinded && is.null(b)) stop("Ongoing study has no blinding config - refusing to serve blinded role.")

  list(
    role          = role,
    blinded       = blinded,
    completed     = completed,
    mask_value    = if (blinded) b$mask_value %||% "BLINDED" else NULL,
    mask_vars     = if (blinded) unlist(b$mask_vars) else character(0),
    drop_datasets = if (blinded) unlist(b$drop_datasets) else character(0),
    hide_diary_text = (blinded && isTRUE(b$restrict_free_text)) || role == "viewer"
  )
}

#' Apply blinding to a named list of data.frames.
apply_policy <- function(datasets, policy) {
  datasets <- datasets[setdiff(names(datasets), policy$drop_datasets)]

  if (policy$blinded) {
    datasets <- lapply(datasets, function(df) {
      hit <- intersect(names(df), policy$mask_vars)
      for (v in hit) {
        # numeric codes (TRT01PN) become NA; character/factor become the mask label
        df[[v]] <- if (is.numeric(df[[v]])) NA_real_ else factor(policy$mask_value)
      }
      df
    })
  }

  if (policy$hide_diary_text && "ADDIARY" %in% names(datasets)) {
    datasets$ADDIARY$DIARYTXT <- "[text restricted for your role]"
  }
  datasets
}

#' Fail-closed check run after apply_policy(). If anything treatment-revealing
#' survived, stop the session rather than serve it.
assert_policy <- function(datasets, policy) {
  leaks <- intersect(names(datasets), policy$drop_datasets)
  if (length(leaks)) stop("Blinding check failed: dataset(s) present: ", paste(leaks, collapse = ", "))

  if (policy$blinded) {
    for (nm in names(datasets)) {
      df <- datasets[[nm]]
      for (v in intersect(names(df), policy$mask_vars)) {
        vals <- unique(as.character(df[[v]]))
        vals <- vals[!is.na(vals)]
        if (length(setdiff(vals, policy$mask_value))) {
          stop(sprintf("Blinding check failed: %s$%s contains unmasked values", nm, v))
        }
      }
    }
  }
  invisible(TRUE)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# Session-scoped access context shared between the data module and analysis
# modules. app.R creates the reactiveVal before teal's server starts.
set_access <- function(session, value) {
  rv <- session$userData$access
  if (is.function(rv)) rv(value) else session$userData$access <- shiny::reactiveVal(value)
}
get_access <- function(session) {
  rv <- session$userData$access
  if (is.function(rv)) rv() else NULL
}
