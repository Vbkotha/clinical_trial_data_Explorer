# Standard TLG library from teal.modules.clinical (needs R >= 4.4; skipped otherwise).
# Argument style follows teal.modules.clinical 0.14.0 (teal.picks variables()/
# values()/picks()). Older versions use choices_selected() - pin versions in renv.

standard_library <- function(datanames, lab_params = c("PLAT", "HGB", "WBC", "NEUT")) {
  v <- teal.picks::variables
  mods <- list(
    teal.modules.clinical::tm_t_summary(
      label = "Demographics",
      dataname = "ADSL",
      arm_var = v(choices = c("ARM", "ARMCD"), selected = "ARM"),
      summarize_vars = v(choices = c("AGE", "SEX", "SITEID"), selected = c("AGE", "SEX"))
    )
  )
  if ("ADLB" %in% datanames) {
    mods[[length(mods) + 1]] <- teal.modules.clinical::tm_g_lineplot(
      label = "Haematology over time",
      dataname = "ADLB",
      group_var = v(choices = c("ARM", "ARMCD"), selected = "ARM", multiple = FALSE),
      y = v(choices = c("AVAL", "CHG", "PCHG"), selected = "AVAL", multiple = FALSE),
      paramcd = teal.picks::picks(
        v("PARAMCD", fixed = TRUE),
        teal.picks::values(selected = lab_params[1], multiple = FALSE),
        check_dataset = FALSE
      )
    )
  }
  if ("ADAE" %in% datanames) {
    mods[[length(mods) + 1]] <- teal.modules.clinical::tm_t_events(
      label = "Adverse events by SOC / PT",
      dataname = "ADAE",
      arm_var = v(choices = c("ARM", "ARMCD"), selected = "ARM"),
      hlt = v(choices = "AEBODSYS", selected = "AEBODSYS"),
      llt = v(choices = "AEDECOD", selected = "AEDECOD"),
      event_type = "adverse event"
    )
  }
  do.call(teal::modules, c(mods, label = "Standard outputs"))
}
