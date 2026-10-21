# Launch Trial Explorer from a Lifebit notebook session (RStudio or Jupyter).
#
#   source("launch.R")
#   run_trial_explorer(study = "STUDY-001", role = "blinded")                    # opens a browser tab; Stop to quit
#   run_trial_explorer(study = "STUDY-001", role = "blinded", open = "viewer")   # RStudio Viewer pane instead
#   run_trial_explorer(study = "STUDY-001", role = "unblinded", background = TRUE) # returns; app keeps running
#   stop_trial_explorer()
#
# From a terminal:  Rscript launch.R STUDY-001 blinded 3838

app_dir_default <- function() {
  f <- tryCatch(normalizePath(sys.frame(1)$ofile), error = function(e) NULL)          # source("launch.R")
  if (is.null(f)) f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]) # Rscript launch.R
  d <- if (!is.na(f) && length(f)) dirname(normalizePath(f)) else getwd()
  if (!file.exists(file.path(d, "app.R"))) stop("Can't find app.R; pass app_dir = '<path to clinical_trial_data_Explorer>'")
  d
}
.trial_explorer_dir <- app_dir_default()

#' Start the app.
#' @param study   study id from config/studies.yml
#' @param role    "blinded", "unblinded" or "viewer". NULL = most restrictive role for the study.
#' @param port    local port to serve on
#' @param background run in a separate R process so the notebook stays usable
#' @param open    "window" (new browser tab), "viewer" (RStudio Viewer pane) or "none"
run_trial_explorer <- function(study = "STUDY-001", role = NULL, port = 3838,
                               host = "0.0.0.0", background = FALSE, open = c("window", "viewer", "none"),
                               app_dir = .trial_explorer_dir, user = NULL) {
  # install teal & co. here (first run only) so progress shows in the notebook
  source(file.path(app_dir, "install.R"), local = TRUE)
  ensure_packages()

  open <- match.arg(open)
  env <- c(APP_STUDY = study, APP_ROLE = .or_default(role, ""), APP_USER = .or_default(user, Sys.getenv("APP_USER")))
  do.call(Sys.setenv, as.list(env))

  if (!background) {
    message("Starting Trial Explorer on port ", port, " ...")
    print_urls(port)
    return(shiny::runApp(app_dir, port = port, host = host, launch.browser = opener(open)))
  }

  # replace a previous Trial Explorer on this port; refuse if something else holds it
  if (length(.app_pids(port))) stop_trial_explorer(port)
  if (is_up(port)) {
    stop("Port ", port, " is already in use by another program. Use run_trial_explorer(port = <other>).", call. = FALSE)
  }

  log <- file.path(state_dir_launch(), sprintf("app-%d.log", port))
  # the --trial-explorer-port marker lets stop_trial_explorer() find the process;
  # R_LIBS hands the child this session's libraries so it loads the same packages
  expr <- sprintf("shiny::runApp('%s', port = %d, host = '%s', launch.browser = FALSE)", app_dir, port, host)
  old_libs <- Sys.getenv("R_LIBS")
  Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  on.exit(Sys.setenv(R_LIBS = old_libs), add = TRUE)
  system2(file.path(R.home("bin"), "Rscript"), c("-e", shQuote(expr), paste0("--trial-explorer-port=", port)),
          stdout = log, stderr = log, wait = FALSE)

  message("Starting Trial Explorer in the background (log: ", log, ") ...")
  up <- FALSE
  for (i in 1:300) {                       # first start may install packages
    Sys.sleep(1)
    if (!length(.app_pids(port))) break     # process exited: startup failed
    if (up <- is_up(port)) break
  }
  if (!up) {
    message("Trial Explorer did not start. Last log lines:\n",
            paste(utils::tail(readLines(log, warn = FALSE), 25), collapse = "\n"))
    stop_trial_explorer(port, quiet = TRUE)
    return(invisible(FALSE))
  }
  print_urls(port)
  o <- opener(open)
  if (is.function(o)) o(sprintf("http://localhost:%d", port))
  invisible(TRUE)
}

stop_trial_explorer <- function(port = 3838, quiet = FALSE) {
  pids <- .app_pids(port)
  if (length(pids)) tools::pskill(pids)
  Sys.sleep(1)
  if (!quiet) message(if (length(pids)) "Stopped." else "No background Trial Explorer found on that port.")
  invisible(length(pids) > 0)
}

# PIDs of background apps started by run_trial_explorer() on this port
.app_pids <- function(port) {
  ps <- suppressWarnings(system("ps -eo pid=,args=", intern = TRUE))
  hit <- grepl(sprintf("--trial-explorer-port=%d( |$)", port), ps) & grepl("runApp", ps, fixed = TRUE)
  as.integer(sub("^\\s*([0-9]+).*", "\\1", ps[hit]))
}

#' Load a study's data as configured in config/studies.yml and report problems
#' (missing datasets/columns, lab_params not in ADLB, blinding vars not present).
check_trial_data <- function(study = "STUDY-001", app_dir = .trial_explorer_dir) {
  e <- new.env()
  for (f in list.files(file.path(app_dir, "R"), full.names = TRUE, pattern = "\\.R$")) sys.source(f, envir = e)
  cfg <- yaml::read_yaml(file.path(app_dir, "config", "studies.yml"))[[study]]
  if (is.null(cfg)) stop("No study '", study, "' in config/studies.yml")
  if (identical(cfg$source, "files") && !grepl("^(/|~)", .or_default(cfg$data_dir, ""))) cfg$data_dir <- file.path(app_dir, cfg$data_dir)
  ds <- e$read_study_datasets(study, cfg)
  for (nm in names(ds)) message(sprintf("  %-8s %6d rows  %3d columns", nm, nrow(ds[[nm]]), ncol(ds[[nm]])))
  rep <- e$check_study_data(ds, cfg)
  if (!nrow(rep)) message("No problems found.") else print(rep, right = FALSE, row.names = FALSE)
  invisible(rep)
}

# ---- helpers ------------------------------------------------------------------

.or_default <- function(a, b) if (is.null(a) || !nzchar(a[1])) b else a

is_up <- function(port) {
  con <- url(sprintf("http://127.0.0.1:%d", port))
  on.exit(try(close(con), silent = TRUE))
  tryCatch({ suppressWarnings(readLines(con, 1, warn = FALSE)); TRUE }, error = function(e) FALSE)
}

state_dir_launch <- function() {
  d <- Sys.getenv("APP_STATE_DIR", file.path(path.expand("~"), ".trial-explorer"))
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

in_rstudio <- function() identical(Sys.getenv("RSTUDIO"), "1") && requireNamespace("rstudioapi", quietly = TRUE) &&
  rstudioapi::isAvailable()

# RStudio proxies local ports itself; open the app in the Viewer pane.
# In RStudio (incl. RStudio Server) browseURL() on a localhost URL opens a new
# browser tab through RStudio's port proxy; viewer() keeps it in the Viewer pane.
opener <- function(open) {
  if (open == "none" || !interactive()) return(FALSE)
  if (open == "viewer" && in_rstudio()) return(function(url) rstudioapi::viewer(url))
  function(url) {
    # RStudio routes browseURL("http://localhost:...") to the Viewer. Its own
    # "Run App > Run External" uses .rs.invokeShinyWindowExternal(), so use that.
    external <- get0(".rs.invokeShinyWindowExternal", mode = "function")
    if (in_rstudio()) {
      proxied <- tryCatch(rstudioapi::translateLocalUrl(url, absolute = TRUE), error = function(e) url)
      message("Trial Explorer is at: ", proxied,
              "\n  (if no new tab opens, allow pop-ups for this site or paste the link into the address bar)")
    }
    if (!is.null(external)) external(url) else utils::browseURL(url)
  }
}

print_urls <- function(port) {
  lines <- sprintf("  Local:   http://127.0.0.1:%d", port)
  if (in_rstudio()) {
    lines <- c(lines, paste0("  RStudio: ", tryCatch(rstudioapi::translateLocalUrl(sprintf("http://localhost:%d", port), absolute = TRUE),
                                                    error = function(e) sprintf("open http://localhost:%d from the Viewer pane", port))))
  }
  prefix <- Sys.getenv("JUPYTERHUB_SERVICE_PREFIX")
  if (nzchar(Sys.getenv("JPY_SESSION_NAME")) || nzchar(prefix) || nzchar(Sys.getenv("JUPYTER_SERVER_ROOT"))) {
    lines <- c(lines, sprintf("  Jupyter: <your session URL>%sproxy/%d/   (needs jupyter-server-proxy)",
                              if (nzchar(prefix)) prefix else "/", port))
  }
  message("Trial Explorer:\n", paste(lines, collapse = "\n"))
}

# ---- command line: Rscript launch.R [STUDY] [ROLE] [PORT] ---------------------
if (!interactive() && sys.nframe() == 0L) {
  a <- commandArgs(TRUE)
  run_trial_explorer(study = if (length(a) >= 1) a[1] else "STUDY-001",
                     role  = if (length(a) >= 2) a[2] else NULL,
                     port  = if (length(a) >= 3) as.integer(a[3]) else 3838)
}
