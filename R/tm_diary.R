# Diary module: patient-reported free text with timestamps.
#   * keyword search (literal terms) with highlighting (HTML-escaped first: patient text is untrusted input)
#   * category + date filtering on top of the global teal filter panel
#   * timeline of entries, optionally aligned with one lab parameter for the same subject(s)

# ---- pure functions ----------------------------------------------------------

html_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x <- gsub("\"", "&quot;", x, fixed = TRUE)
  gsub("'", "&#39;", x, fixed = TRUE)
}

#' Escape, then wrap matches of comma-separated terms in <mark>.
highlight_terms <- function(text, terms) {
  out <- html_escape(text)
  terms <- trimws(unlist(strsplit(terms %||% "", ",")))
  terms <- terms[nzchar(terms)]
  for (t in terms) {
    pat <- paste0("(", gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", html_escape(t)), ")")
    out <- gsub(pat, "<mark>\\1</mark>", out, ignore.case = TRUE, perl = TRUE)
  }
  out
}

filter_diary <- function(df, terms = "", categories = NULL, ady_range = NULL, subjects = NULL) {
  keep <- rep(TRUE, nrow(df))
  terms <- trimws(unlist(strsplit(terms %||% "", ",")))
  terms <- terms[nzchar(terms)]
  if (length(terms)) {
    hit <- Reduce(`|`, lapply(terms, function(t) grepl(tolower(t), tolower(df$DIARYTXT), fixed = TRUE)))
    keep <- keep & hit
  }
  if (length(categories)) keep <- keep & df$DIARYCAT %in% categories
  if (length(ady_range))  keep <- keep & df$ADY >= ady_range[1] & df$ADY <= ady_range[2]
  if (length(subjects))   keep <- keep & df$USUBJID %in% subjects
  df[keep, , drop = FALSE]
}

plot_diary_timeline <- function(diary, adlb = NULL, param = NULL) {
  library(ggplot2)
  p <- ggplot(diary, aes(x = ADY, y = USUBJID)) +
    geom_point(aes(colour = DIARYCAT), size = 3, alpha = 0.85) +
    labs(x = "Study day", y = NULL, colour = "Diary category") +
    theme_minimal(base_size = 12)
  if (!is.null(adlb) && !is.null(param) && length(unique(diary$USUBJID)) <= 6) {
    # one panel per subject: lab trajectory, diary entries as marks along the bottom
    lb <- adlb[adlb$PARAMCD == param & adlb$USUBJID %in% diary$USUBJID, ]
    p <- ggplot() +
      geom_rect(data = lb[!duplicated(lb$USUBJID), ], aes(xmin = -Inf, xmax = Inf, ymin = ANRLO, ymax = ANRHI),
                fill = "grey88", alpha = 0.6) +
      geom_line(data = lb, aes(x = ADY, y = AVAL), colour = "grey30") +
      geom_point(data = lb, aes(x = ADY, y = AVAL), colour = "grey30", size = 1.5) +
      geom_rug(data = diary, aes(x = ADY, colour = DIARYCAT), sides = "b", linewidth = 1.2, length = grid::unit(0.08, "npc")) +
      facet_wrap(~USUBJID, ncol = 2) +
      labs(x = "Study day", y = lb$PARAM[1], colour = "Diary entry",
           caption = "Coloured ticks on the x-axis = diary entries; grey band = normal range") +
      theme_minimal(base_size = 12)
  }
  p
}

# ---- teal module -----------------------------------------------------------

tm_diary <- function(label = "Patient diary", overlay_params = c("PLAT", "HGB"), transformators = list()) {
  teal::module(
    label = label,
    datanames = c("ADSL", "ADDIARY", "ADLB"),
    transformators = transformators,
    ui = function(id) {
      ns <- shiny::NS(id)
      shiny::sidebarLayout(
        shiny::sidebarPanel(width = 3,
          shiny::textInput(ns("terms"), "Search text (comma-separated terms)", placeholder = "bruis, bleed, nosebleed"),
          shiny::selectizeInput(ns("subjects"), "Subjects (empty = all filtered)", choices = NULL, multiple = TRUE),
          shiny::checkboxGroupInput(ns("cats"), "Categories", choices = NULL),
          shiny::sliderInput(ns("ady"), "Study day", 1, 85, c(1, 85)),
          shiny::selectInput(ns("overlay"), "Overlay lab (<= 6 subjects)", c("None" = "", overlay_params))
        ),
        shiny::mainPanel(width = 9,
          shiny::plotOutput(ns("timeline"), height = "380px"),
          DT::DTOutput(ns("table"))
        )
      )
    },
    server = function(id, data) {
      shiny::moduleServer(id, function(input, output, session) {
        diary <- shiny::reactive({
          d <- data()[["ADDIARY"]]
          shiny::validate(shiny::need(is.data.frame(d), "No diary data (ADDIARY) is available for this study or your role."))
          d
        })

        shiny::observeEvent(diary(), once = TRUE, {
          days <- diary()$ADY[is.finite(diary()$ADY)]
          if (length(days)) {
            rng <- c(floor(min(days)), ceiling(max(days)))
            shiny::updateSliderInput(session, "ady", min = rng[1], max = rng[2], value = rng)
          }
        })

        shiny::observe({
          d <- diary()
          shiny::updateSelectizeInput(session, "subjects", choices = sort(unique(d$USUBJID)), server = TRUE)
          cats <- sort(unique(d$DIARYCAT))
          shiny::updateCheckboxGroupInput(session, "cats", choices = cats, selected = cats)
        })

        filtered <- shiny::reactive({
          filter_diary(diary(), input$terms, input$cats, input$ady, input$subjects)
        })

        output$timeline <- shiny::renderPlot({
          f <- filtered()
          shiny::validate(shiny::need(nrow(f) > 0, "No diary entries match."))
          plot_diary_timeline(f, data()[["ADLB"]], if (nzchar(input$overlay)) input$overlay)
        })

        output$table <- DT::renderDT({
          f <- filtered()
          f <- f[order(f$USUBJID, f$ADTM), ]
          show <- data.frame(
            Subject = f$USUBJID, `Date/time` = format(f$ADTM, "%Y-%m-%d %H:%M"), `Study day` = f$ADY,
            Category = f$DIARYCAT, Entry = highlight_terms(f$DIARYTXT, input$terms), check.names = FALSE
          )
          # escape = FALSE is safe ONLY because highlight_terms() escapes the text first
          DT::datatable(show, escape = FALSE, rownames = FALSE, filter = "top",
                        options = list(pageLength = 15, scrollX = TRUE))
        })
      })
    }
  )
}
