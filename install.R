# Package bootstrap for Trial Explorer.
#
# You normally don't run this yourself: app.R and run_trial_explorer() call
# ensure_packages() on start. The first start installs anything missing (a few
# minutes); later starts only check versions.
#
# Manual use:  Rscript install.R
#
# Sources: teal packages from the insightsengineering r-universe; everything else
# from CRAN, using Posit Package Manager's precompiled Linux binaries when the
# OS is recognised (much faster than compiling). Set TRIAL_EXPLORER_REPOS to a
# comma-separated list of repos to use an internal mirror instead.

# Required: the core app (role-based blinding, analysis modules, TFL viewer, listings).
trial_explorer_packages <- c(
  teal = "1.2.1", teal.slice = "0.8.2", teal.data = "0.8.0",
  shiny = "1.8.0", ggplot2 = "3.5.0", DT = "0.33", yaml = "2.3.0", digest = "0.6.0",
  jsonlite = "1.8.0", rlang = "1.1.0", testthat = "3.0.0", rstudioapi = "0.15.0"
)
# Optional: the "Standard outputs" group (demographics, AE table, lab line plot).
# teal.modules.clinical and tern need R >= 4.4; on older R the group is left out.
trial_explorer_clinical <- c(teal.modules.clinical = "0.14.0", teal.picks = "0.3.1")

ensure_packages <- function(pkgs = trial_explorer_packages, optional = FALSE,
                            clinical = getRversion() >= "4.4.0") {
  if (optional) pkgs <- c(pkgs, arrow = "0.0.0", haven = "0.0.0")   # for source: files
  todo <- .outdated(pkgs)
  todo_clinical <- if (clinical) .outdated(trial_explorer_clinical) else character(0)
  stale <- .stale_dependencies(c(names(pkgs), names(trial_explorer_clinical)))
  if (!length(todo) && !length(todo_clinical) && !length(stale)) return(invisible(TRUE))

  lib <- .writable_lib()
  repos <- .install_repos()
  message("Trial Explorer: installing ", length(c(todo, todo_clinical, stale)), " package(s) into ", lib,
          " (first start only, this can take a few minutes): ", paste(c(todo, todo_clinical, stale), collapse = ", "))
  old <- options(repos = repos, HTTPUserAgent = .binary_user_agent(), Ncpus = max(1L, parallel::detectCores() - 1L))
  on.exit(options(old), add = TRUE)

  # teal.reporter needs rtables.officer, whose current release requires R >= 4.4.
  # On older R, install the last release that still supports it.
  if (getRversion() < "4.4.0" && !requireNamespace("rtables.officer", quietly = TRUE)) {
    utils::install.packages(c("formatters", "rtables", "rlistings", "officer", "flextable", "checkmate",
                              "lifecycle", "magrittr", "stringi"), lib = lib)
    utils::install.packages(
      "https://cran.r-project.org/src/contrib/Archive/rtables.officer/rtables.officer_0.1.1.tar.gz",
      lib = lib, repos = NULL, type = "source")
  }

  todo <- c(todo, stale)
  if (length(todo)) utils::install.packages(todo, lib = lib, dependencies = c("Depends", "Imports", "LinkingTo"))
  if (length(todo_clinical)) {
    suppressWarnings(tryCatch(
      utils::install.packages(todo_clinical, lib = lib, dependencies = c("Depends", "Imports", "LinkingTo")),
      error = function(e) NULL))
    if (length(.outdated(trial_explorer_clinical))) {
      message("Trial Explorer: teal.modules.clinical could not be installed; ",
              "starting without the 'Standard outputs' group.")
    }
  }

  # install.packages() skips dependencies that are installed but too old; upgrade those
  for (i in 1:3) {
    stale <- .stale_dependencies(c(names(pkgs), names(trial_explorer_clinical)))
    if (!length(stale)) break
    utils::install.packages(stale, lib = lib, dependencies = c("Depends", "Imports", "LinkingTo"))
  }

  still <- c(.outdated(pkgs), .stale_dependencies(names(pkgs)))
  if (length(still)) {
    stop("Trial Explorer: these packages are missing or older than required: ",
         paste(still, collapse = ", "),
         "\nCheck that this session can reach: ", paste(repos, collapse = ", "),
         "\n(or set TRIAL_EXPLORER_REPOS to a mirror it can reach)", call. = FALSE)
  }
  message("Trial Explorer: all packages installed.")
  invisible(TRUE)
}

.outdated <- function(pkgs) {
  names(pkgs)[vapply(names(pkgs), function(p) {
    v <- tryCatch(utils::packageVersion(p), error = function(e) NULL)
    is.null(v) || v < package_version(pkgs[[p]])
  }, logical(1))]
}

# Installed packages (recursively from `roots`) whose installed version is below
# what another installed package in the tree requires.
.stale_dependencies <- function(roots) {
  base <- rownames(utils::installed.packages(priority = "base"))
  seen <- character(0); need <- list(); queue <- roots
  while (length(queue)) {
    p <- queue[1]; queue <- queue[-1]
    if (p %in% seen || p %in% base) next
    seen <- c(seen, p)
    d <- suppressWarnings(utils::packageDescription(p, fields = c("Depends", "Imports", "LinkingTo")))
    if (!is.list(d)) next                                     # not installed
    x <- trimws(unlist(strsplit(gsub("\\s+", " ", paste(unlist(d), collapse = ",")), ",")))
    x <- x[nzchar(x) & x != "NA"]
    nm <- trimws(sub("\\(.*", "", x))
    for (i in grep(">=", x)) {
      v <- trimws(sub(".*>=\\s*([0-9.-]+).*", "\\1", x[i]))
      if (is.null(need[[nm[i]]]) || package_version(v) > package_version(need[[nm[i]]])) need[[nm[i]]] <- v
    }
    queue <- c(queue, setdiff(nm, c("R", seen)))
  }
  need <- need[setdiff(names(need), c("R", base))]
  names(need)[vapply(names(need), function(p) {
    v <- tryCatch(utils::packageVersion(p), error = function(e) NULL)
    !is.null(v) && v < package_version(need[[p]])
  }, logical(1))]
}

# First writable library on the path; otherwise create the user library.
.writable_lib <- function() {
  for (l in .libPaths()) if (file.access(l, 2) == 0) return(l)
  l <- Sys.getenv("R_LIBS_USER")
  if (!nzchar(l)) l <- file.path(path.expand("~"), "R", "library")
  l <- path.expand(strsplit(l, .Platform$path.sep)[[1]][1])
  dir.create(l, recursive = TRUE, showWarnings = FALSE)
  .libPaths(c(l, .libPaths()))
  l
}

.install_repos <- function() {
  custom <- trimws(strsplit(Sys.getenv("TRIAL_EXPLORER_REPOS", ""), ",")[[1]])
  if (length(custom)) return(custom[nzchar(custom)])
  cran <- getOption("repos")[["CRAN"]]
  if (is.null(cran) || cran == "@CRAN@") cran <- "https://cloud.r-project.org"
  codename <- .linux_codename()
  if (!is.null(codename)) cran <- sprintf("https://packagemanager.posit.co/cran/__linux__/%s/latest", codename)
  c(insightsengineering = "https://insightsengineering.r-universe.dev", CRAN = cran)
}

# Posit Package Manager serves Linux binaries for these distributions.
.linux_codename <- function() {
  if (!file.exists("/etc/os-release")) return(NULL)
  os <- readLines("/etc/os-release", warn = FALSE)
  get <- function(k) sub(paste0("^", k, "=\"?([^\"]*)\"?$"), "\\1", grep(paste0("^", k, "="), os, value = TRUE)[1])
  id <- get("ID"); cn <- get("VERSION_CODENAME"); ver <- get("VERSION_ID")
  if (identical(id, "ubuntu") && cn %in% c("focal", "jammy", "noble")) return(cn)
  if (identical(id, "debian") && cn %in% c("bullseye", "bookworm")) return(cn)
  if (id %in% c("rhel", "rocky", "almalinux", "centos") && !is.na(ver)) return(paste0("rhel", sub("\\..*", "", ver)))
  NULL
}

# Package Manager only serves binaries when the user agent names the R version and platform.
.binary_user_agent <- function() {
  sprintf("R/%s R (%s)", getRversion(),
          paste(getRversion(), R.version$platform, R.version$arch, R.version$os))
}

if (!interactive() && sys.nframe() == 0L) {
  ensure_packages(optional = identical(Sys.getenv("TRIAL_EXPLORER_OPTIONAL"), "true"))
}
