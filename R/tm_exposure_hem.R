# Cross-dimension module: exposure vs haematology vs response over a shared
# study-day window. Two views:
#   * Patient profile - stacked, time-aligned panels for one subject
#   * Cohort scatter  - per-subject exposure metric vs lab metric in the window

# ---- pure functions (unit-testable, no Shiny) --------------------------------

patient_profile_data <- function(adex, adlb, adrs, usubjid, params, window) {
  in_win <- function(d) d >= window[1] & d <= window[2]
  out <- list()
  if (!is.null(adex)) {
    ex <- adex[adex$USUBJID == usubjid & in_win(adex$ASTDY), ]
    if (nrow(ex)) out$ex <- data.frame(panel = "Dose (mg)", x = ex$ASTDY, xend = ex$AENDY,
                                       y = ex$AVAL, label = ex$EXADJ, kind = "exposure")
  }
  lb <- adlb[adlb$USUBJID == usubjid & adlb$PARAMCD %in% params & in_win(adlb$ADY), ]
  if (nrow(lb)) out$lb <- data.frame(panel = lb$PARAM, x = lb$ADY, xend = NA, y = lb$AVAL,
                                     lo = lb$ANRLO, hi = lb$ANRHI, label = lb$ANRIND, kind = "lab")
  if (!is.null(adrs)) {
    rs <- adrs[adrs$USUBJID == usubjid & in_win(adrs$ADY), ]
    if (nrow(rs)) out$rs <- data.frame(panel = "Response", x = rs$ADY, xend = NA, y = 1,
                                       label = as.character(rs$AVALC), kind = "response")
  }
  if (!length(out)) return(NULL)
  cols <- unique(unlist(lapply(out, names)))
  out <- lapply(out, function(d) { for (c in setdiff(cols, names(d))) d[[c]] <- NA; d[cols] })
  df <- do.call(rbind, out)
  lvl <- c(if (!is.null(out$ex)) "Dose (mg)", unique(as.character(out$lb$panel)), if (!is.null(out$rs)) "Response")
  df$panel <- factor(df$panel, levels = lvl)
  df
}

plot_patient_profile <- function(df, usubjid, window) {
  library(ggplot2)
  p <- ggplot(df, aes(x = x, y = y)) +
    facet_grid(panel ~ ., scales = "free_y", switch = "y") +
    coord_cartesian(xlim = window) +
    labs(x = "Study day", y = NULL, title = usubjid) +
    theme_minimal(base_size = 13) +
    theme(strip.placement = "outside", strip.text.y.left = element_text(angle = 0, hjust = 1),
          panel.grid.minor = element_blank())
  ex <- df[df$kind == "exposure", ]
  lb <- df[df$kind == "lab", ]
  rs <- df[df$kind == "response", ]
  if (nrow(ex)) p <- p + geom_segment(data = ex, aes(xend = xend, yend = y), linewidth = 3, colour = "#3b6ea8") +
    geom_text(data = ex[nzchar(ex$label), ], aes(label = label), vjust = -1, size = 3, colour = "#a83b3b")
  if (nrow(lb)) p <- p +
    geom_rect(data = lb[!duplicated(lb$panel), ], aes(xmin = -Inf, xmax = Inf, ymin = lo, ymax = hi),
              inherit.aes = FALSE, fill = "grey85", alpha = 0.5) +
    geom_line(data = lb, colour = "grey30") +
    geom_point(data = lb, aes(colour = label), size = 2) +
    scale_colour_manual(values = c(LOW = "#c0392b", NORMAL = "grey30", HIGH = "#d68910"), name = "Range")
  if (nrow(rs)) p <- p + geom_label(data = rs, aes(label = label), size = 3.5)
  p
}

#' One row per subject: exposure metric and lab metric inside the window.
cohort_window_summary <- function(adsl, adex, adlb, adrs, param, window,
                                  exposure_metric = c("cumulative_dose", "dose_intensity", "days_on_drug"),
                                  lab_metric = c("nadir", "pct_change_nadir", "max", "last")) {
  exposure_metric <- match.arg(exposure_metric)
  lab_metric <- match.arg(lab_metric)
  in_win <- function(d) d >= window[1] & d <= window[2]

  lb <- adlb[adlb$PARAMCD == param & in_win(adlb$ADY), ]
  labv <- vapply(split(lb, lb$USUBJID), function(d) switch(lab_metric,
    nadir = min(d$AVAL),
    pct_change_nadir = 100 * (min(d$AVAL) - d$BASE[1]) / d$BASE[1],
    max = max(d$AVAL),
    last = d$AVAL[which.max(d$ADY)]
  ), numeric(1))
  out <- data.frame(USUBJID = names(labv), lab = unname(labv), stringsAsFactors = FALSE)

  if (!is.null(adex)) {
    ex <- adex[in_win(adex$ASTDY), ]
    expv <- vapply(split(ex, ex$USUBJID), function(d) switch(exposure_metric,
      cumulative_dose = sum(d$AVAL),
      dose_intensity  = sum(d$AVAL) / max(1, diff(range(c(d$ASTDY, d$AENDY))) + 1) * 7,
      days_on_drug    = sum(d$AVAL > 0) * 7
    ), numeric(1))
    out$exposure <- unname(expv[out$USUBJID])
  }
  if (!is.null(adrs)) {
    rs <- adrs[in_win(adrs$ADY), ]
    best <- vapply(split(rs, rs$USUBJID), function(d) as.character(sort(d$AVALC)[1]), "")
    out$best_response <- factor(unname(best[out$USUBJID]), levels = levels(adrs$AVALC))
  }
  merge(out, adsl[, intersect(c("USUBJID", "ARM", "SEX", "AGE", "SITEID"), names(adsl))], by = "USUBJID")
}

plot_cohort_scatter <- function(df, colour_by, x_lab, y_lab) {
  library(ggplot2)
  ggplot(df, aes(x = exposure, y = lab, colour = .data[[colour_by]])) +
    geom_point(size = 3, alpha = 0.8) +
    geom_smooth(aes(group = 1), method = "loess", formula = y ~ x, se = TRUE, colour = "grey40", linewidth = 0.6) +
    labs(x = x_lab, y = y_lab, colour = colour_by) +
    theme_minimal(base_size = 13)
}

# ---- teal module -----------------------------------------------------------

tm_exposure_hem <- function(label = "Exposure vs haematology",
                            lab_params = c("PLAT", "HGB", "WBC", "NEUT"),
                            max_day = 85, transformators = list()) {
  teal::module(
    label = label,
    datanames = "all",   # ADEX is withheld for blinded roles, so do not hard-depend on it
    transformators = transformators,
    ui = function(id) {
      ns <- shiny::NS(id)
      shiny::sidebarLayout(
        shiny::sidebarPanel(width = 3,
          shiny::radioButtons(ns("view"), "View", c("Patient profile" = "patient", "Cohort scatter" = "cohort")),
          shiny::sliderInput(ns("window"), "Study-day window", min = 1, max = max_day, value = c(1, max_day)),
          shiny::conditionalPanel(sprintf("input['%s'] == 'patient'", ns("view")),
            shiny::selectizeInput(ns("subject"), "Subject", choices = NULL),
            shiny::checkboxGroupInput(ns("params"), "Haematology parameters", lab_params, selected = lab_params[1:2])
          ),
          shiny::conditionalPanel(sprintf("input['%s'] == 'cohort'", ns("view")),
            shiny::selectInput(ns("param"), "Lab parameter", lab_params),
            shiny::selectInput(ns("lab_metric"), "Lab metric in window",
              c("Nadir" = "nadir", "% change at nadir" = "pct_change_nadir", "Max" = "max", "Last" = "last")),
            shiny::selectInput(ns("exp_metric"), "Exposure metric in window",
              c("Cumulative dose (mg)" = "cumulative_dose", "Dose intensity (mg/week)" = "dose_intensity",
                "Days on drug" = "days_on_drug")),
            shiny::selectInput(ns("colour_by"), "Colour by", c("best_response", "ARM", "SEX", "SITEID"))
          )
        ),
        shiny::mainPanel(width = 9,
          shiny::uiOutput(ns("notice")),
          shiny::plotOutput(ns("plot"), height = "650px")
        )
      )
    },
    server = function(id, data) {
      shiny::moduleServer(id, function(input, output, session) {
        has_exposure <- shiny::reactive("ADEX" %in% names(data()))

        shiny::observe({
          ids <- unique(data()[["ADLB"]]$USUBJID)
          shiny::updateSelectizeInput(session, "subject", choices = ids, selected = ids[1], server = TRUE)
        })

        output$notice <- shiny::renderUI({
          if (!has_exposure()) shiny::div(class = "alert alert-warning",
            "Exposure data is withheld for your role while the study is blinded. ",
            "Haematology and response panels are shown without dose.")
        })

        output$plot <- shiny::renderPlot({
          d <- data()
          adex <- if (has_exposure()) d[["ADEX"]]
          if (input$view == "patient") {
            shiny::req(input$subject, length(input$params) > 0)
            df <- patient_profile_data(adex, d[["ADLB"]], d[["ADRS"]], input$subject, input$params, input$window)
            shiny::validate(shiny::need(!is.null(df), "No records for this subject in the window / current filters."))
            plot_patient_profile(df, input$subject, input$window)
          } else {
            shiny::validate(shiny::need(has_exposure(), "Cohort exposure view requires exposure data."))
            df <- cohort_window_summary(d[["ADSL"]], adex, d[["ADLB"]], d[["ADRS"]], input$param, input$window,
                                        input$exp_metric, input$lab_metric)
            shiny::validate(shiny::need(nrow(df) > 0, "No subjects in the window / current filters."))
            x_labs <- c(cumulative_dose = "Cumulative dose (mg)", dose_intensity = "Dose intensity (mg/week)",
                        days_on_drug = "Days on drug")
            plot_cohort_scatter(df, input$colour_by,
                                x_lab = paste0(x_labs[[input$exp_metric]], ", days ", input$window[1], "-", input$window[2]),
                                y_lab = paste(input$param, gsub("_", " ", input$lab_metric)))
          }
        })
      })
    }
  )
}
