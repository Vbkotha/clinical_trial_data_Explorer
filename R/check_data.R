# What the app expects from each dataset, and a checker for bring-your-own data.
#   required    - the modules using this dataset fail without it
#   recommended - some views or options are empty without it

DATA_SPEC <- list(
  ADSL    = list(required = c("STUDYID", "USUBJID", "ARM"),
                 recommended = c("ARMCD", "SAFFL", "AGE", "SEX", "SITEID")),
  ADLB    = list(required = c("STUDYID", "USUBJID", "PARAMCD", "PARAM", "AVAL", "ADY"),
                 recommended = c("AVISIT", "BASE", "CHG", "PCHG", "ANRLO", "ANRHI", "ANRIND")),
  ADEX    = list(required = c("STUDYID", "USUBJID", "AVAL", "ASTDY", "AENDY"),
                 recommended = "EXADJ"),
  ADRS    = list(required = c("STUDYID", "USUBJID", "AVALC", "ADY"), recommended = character(0)),
  ADAE    = list(required = c("STUDYID", "USUBJID"), recommended = c("AEBODSYS", "AEDECOD")),
  ADDIARY = list(required = c("STUDYID", "USUBJID", "DIARYSEQ", "ADTM", "ADY", "DIARYCAT", "DIARYTXT"),
                 recommended = character(0))
)

#' @return data.frame(dataset, level = "error" | "warning", message); zero rows if all good.
check_study_data <- function(ds, study_cfg) {
  out <- list()
  add <- function(dataset, level, ...) out[[length(out) + 1]] <<- data.frame(dataset = dataset, level = level,
                                                                             message = paste0(...))
  if (!"ADSL" %in% names(ds)) add("ADSL", "error", "ADSL is required (every other dataset joins to it)")
  for (nm in names(ds)) {
    df <- ds[[nm]]
    spec <- DATA_SPEC[[nm]]
    if (is.null(spec)) {
      if (!"USUBJID" %in% names(df)) add(nm, "warning", "no USUBJID: global ADSL filters will not apply to it")
      next
    }
    miss <- setdiff(spec$required, names(df))
    if (length(miss)) add(nm, "error", "missing required column(s): ", paste(miss, collapse = ", "))
    miss <- setdiff(spec$recommended, names(df))
    if (length(miss)) add(nm, "warning", "missing recommended column(s): ", paste(miss, collapse = ", "))
  }
  if ("ADSL" %in% names(ds) && anyDuplicated(ds$ADSL$USUBJID)) add("ADSL", "error", "USUBJID is not unique")

  lab <- unlist(study_cfg$lab_params) %||% c("PLAT", "HGB", "WBC", "NEUT")
  if ("ADLB" %in% names(ds) && "PARAMCD" %in% names(ds$ADLB)) {
    miss <- setdiff(lab, ds$ADLB$PARAMCD)
    if (length(miss)) add("ADLB", "warning", "lab_params not found in PARAMCD: ", paste(miss, collapse = ", "),
                          " (set lab_params in config/studies.yml)")
  }

  b <- study_cfg$blinding
  if (!identical(study_cfg$status, "completed") && !is.null(b)) {
    present <- intersect(unlist(b$mask_vars), unique(unlist(lapply(ds, names))))
    if (!length(present)) add("(blinding)", "error", "none of blinding mask_vars exist in the data, ",
                              "so the blinded view would hide nothing; fix mask_vars in config/studies.yml")
  }
  if (length(out)) do.call(rbind, out) else data.frame(dataset = character(0), level = character(0), message = character(0))
}

#' Put loaded data into the shape the modules expect.
standardise_datasets <- function(ds) {
  # best response = first factor level, so order response codes best -> worst
  if ("ADRS" %in% names(ds) && "AVALC" %in% names(ds$ADRS) && !is.factor(ds$ADRS$AVALC)) {
    std <- c("CR", "PR", "SD", "NON-CR/NON-PD", "PD", "NE")
    v <- as.character(ds$ADRS$AVALC)
    ds$ADRS$AVALC <- factor(v, levels = c(intersect(std, v), sort(setdiff(unique(v[!is.na(v)]), std))))
  }
  ds
}
