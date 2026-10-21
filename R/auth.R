# Identity: who is the user and which IdP groups are they in?
#
# The app trusts identity headers injected by the platform's authenticating
# reverse proxy. That is only safe if the Shiny process is NOT reachable except
# through that proxy (network policy / container ingress). Header names below
# are placeholders -- confirm the real ones with the Lifebit platform team and
# check they actually reach session$request in your Shiny Server setup.

AUTH_USER_HEADER   <- Sys.getenv("AUTH_USER_HEADER",   "HTTP_X_AUTH_REQUEST_EMAIL")
AUTH_GROUPS_HEADER <- Sys.getenv("AUTH_GROUPS_HEADER", "HTTP_X_AUTH_REQUEST_GROUPS")

#' Resolve the current user's identity from the Shiny session.
#' @return list(user = chr, groups = chr) or NULL if unauthenticated.
get_identity <- function(session) {
  req <- session$request
  user   <- req[[AUTH_USER_HEADER]]
  groups <- req[[AUTH_GROUPS_HEADER]]

  # Local development only: never set APP_DEV_MODE in a deployed environment.
  if (is.null(user) && identical(Sys.getenv("APP_DEV_MODE"), "true")) {
    user   <- Sys.getenv("DEV_USER", "dev@example.com")
    groups <- Sys.getenv("DEV_GROUPS", "")
  }
  if (is.null(user) || !nzchar(user)) return(NULL)

  list(
    user   = user,
    groups = parse_groups(groups)
  )
}

parse_groups <- function(x) {
  if (is.null(x) || !nzchar(x)) return(character(0))
  g <- trimws(unlist(strsplit(x, "[,;]")))
  g[nzchar(g)]
}
