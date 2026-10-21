# Install the packages Trial Explorer needs into the notebook session's R library.
#   Rscript install.R            (or source("install.R") from RStudio / an R notebook)
#
# teal packages come from the insightsengineering r-universe (which also serves
# their CRAN dependencies); everything else from CRAN. Set TRIAL_EXPLORER_REPOS
# to a comma-separated list to use an internal mirror instead.

required <- c(
  # teal stack (versions the app was written and tested against)
  teal = "1.2.1", teal.modules.general = "0.9.0", teal.modules.clinical = "0.14.0",
  teal.picks = "0.3.1", teal.slice = "0.8.2", teal.data = "0.8.0",
  # app dependencies
  shiny = "1.8.0", ggplot2 = "3.5.0", DT = "0.31", yaml = "2.3.0", digest = "0.6.0",
  jsonlite = "1.8.0", rlang = "1.1.0", testthat = "3.0.0", rstudioapi = "0.15.0"
)
optional <- c("arrow", "haven")   # only for source: files with .parquet / .sas7bdat / .xpt

repos <- strsplit(Sys.getenv("TRIAL_EXPLORER_REPOS", ""), ",")[[1]]
if (!length(repos)) {
  cran <- getOption("repos")[["CRAN"]]
  if (is.null(cran) || cran == "@CRAN@") cran <- "https://cloud.r-project.org"
  repos <- c(insightsengineering = "https://insightsengineering.r-universe.dev", CRAN = cran)
}

outdated <- function(pkgs) {
  names(pkgs)[vapply(names(pkgs), function(p) {
    v <- tryCatch(utils::packageVersion(p), error = function(e) NULL)
    is.null(v) || v < package_version(pkgs[[p]])
  }, logical(1))]
}

# teal.reporter needs rtables.officer, whose current release requires R >= 4.4.
# On older R, install the last release that still supports it.
if (getRversion() < "4.4.0" && !requireNamespace("rtables.officer", quietly = TRUE)) {
  message("R ", getRversion(), " detected: installing rtables.officer 0.1.1 (newer releases need R >= 4.4)")
  utils::install.packages(c("formatters", "rtables", "rlistings", "officer", "flextable", "checkmate", "lifecycle",
                            "magrittr", "stringi"),
                          repos = repos)
  utils::install.packages("https://cran.r-project.org/src/contrib/Archive/rtables.officer/rtables.officer_0.1.1.tar.gz",
                          repos = NULL, type = "source")
}

todo <- outdated(required)
if (length(todo)) {
  message("Installing: ", paste(todo, collapse = ", "))
  utils::install.packages(todo, repos = repos, dependencies = c("Depends", "Imports", "LinkingTo"))
}
if (identical(Sys.getenv("TRIAL_EXPLORER_OPTIONAL"), "true")) {
  utils::install.packages(setdiff(optional, rownames(utils::installed.packages())), repos = repos)
}

still <- outdated(required)
if (length(still)) {
  stop("These packages are missing or older than required: ",
       paste(sprintf("%s (>= %s)", still, required[still]), collapse = ", "),
       "\nCheck that the session can reach: ", paste(repos, collapse = ", "))
}
message("All Trial Explorer packages are installed.")
