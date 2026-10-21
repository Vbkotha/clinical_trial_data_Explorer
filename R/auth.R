# Identity and role.
#
# The app runs inside an already-authenticated Lifebit workspace (notebook
# session), so it does no authentication of its own. The user is the workspace
# user (APP_USER, else the OS user) and the role is chosen at launch:
#
#   APP_ROLE   = unblinded | blinded | viewer   (explicit role), or
#   APP_GROUPS = comma-separated groups mapped to a role via config/roles.yml
#
# With neither set, the most restrictive role for the study is used
# (blinded for an ongoing study, viewer for a completed one).
#
# Note: whoever launches the app picks the role. Blinding here controls what the
# app displays; it is only an access control if the workspace user cannot read
# the underlying unblinded files directly.

#' @return list(user = chr, groups = chr, role = chr or NULL)
get_identity <- function(session = NULL) {
  user <- Sys.getenv("APP_USER", Sys.getenv("USER", "workspace-user"))
  role <- Sys.getenv("APP_ROLE", "")
  list(
    user   = if (nzchar(user)) user else "workspace-user",
    groups = parse_groups(Sys.getenv("APP_GROUPS", "")),
    role   = if (nzchar(role)) role else NULL
  )
}

parse_groups <- function(x) {
  if (is.null(x) || !nzchar(x)) return(character(0))
  g <- trimws(unlist(strsplit(x, "[,;]")))
  g[nzchar(g)]
}

#' Writable location for runtime state (audit log, saved graphs).
#' Defaults to ~/.trial-explorer so the app also runs from a read-only checkout.
state_dir <- function(...) {
  root <- Sys.getenv("APP_STATE_DIR", file.path(path.expand("~"), ".trial-explorer"))
  p <- file.path(root, ...)
  dir.create(if (length(list(...))) dirname(p) else p, recursive = TRUE, showWarnings = FALSE)
  p
}
