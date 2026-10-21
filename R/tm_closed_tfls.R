# Closed TFLs for completed studies.
# Final outputs are produced by the validated production pipeline, not by this
# app. The app only SERVES them read-only and verifies each file against the
# SHA-256 in the locked manifest, so users can see the output is the one signed off.

read_tfl_manifest <- function(tfl_dir) {
  m <- utils::read.csv(file.path(tfl_dir, "manifest.csv"), stringsAsFactors = FALSE)
  m$path <- file.path(tfl_dir, m$file)
  m$actual <- vapply(m$path, function(f) {
    if (file.exists(f)) digest::digest(file = f, algo = "sha256") else NA_character_
  }, "")
  m$status <- ifelse(is.na(m$actual), "MISSING", ifelse(m$actual == m$sha256, "Verified", "CHECKSUM MISMATCH"))
  m
}

tm_closed_tfls <- function(study_id, tfl_dir, locked_on = NULL, label = "Final TFLs (locked)") {
  res_prefix <- paste0("tfl_", gsub("[^A-Za-z0-9]", "_", study_id))
  shiny::addResourcePath(res_prefix, normalizePath(tfl_dir))

  teal::module(
    label = label,
    datanames = NULL,                       # no filter panel: outputs are fixed
    ui = function(id) {
      ns <- shiny::NS(id)
      shiny::tagList(
        shiny::div(class = "alert alert-info",
          shiny::strong("Database locked", if (!is.null(locked_on)) paste("on", locked_on), ". "),
          "These are the final, signed-off outputs. Interactive modules in this app are exploratory and do not replace them."),
        DT::DTOutput(ns("list")),
        shiny::uiOutput(ns("preview"))
      )
    },
    server = function(id) {
      shiny::moduleServer(id, function(input, output, session) {
        m <- read_tfl_manifest(tfl_dir)

        output$list <- DT::renderDT({
          DT::datatable(m[, c("output_id", "title", "type", "status")], selection = "single",
                        rownames = FALSE, options = list(dom = "t", pageLength = 100)) |>
            DT::formatStyle("status", color = DT::styleEqual(c("Verified", "CHECKSUM MISMATCH", "MISSING"),
                                                            c("#1e8449", "#c0392b", "#c0392b")))
        })

        output$preview <- shiny::renderUI({
          i <- input$list_rows_selected
          shiny::req(i)
          if (m$status[i] != "Verified") {
            return(shiny::div(class = "alert alert-danger",
                              "This output failed integrity verification and is not displayed. Contact the study statistician."))
          }
          shiny::tags$iframe(src = paste0(res_prefix, "/", utils::URLencode(m$file[i])),
                             style = "width:100%; height:800px; border:1px solid #ddd; margin-top:12px;")
        })
      })
    }
  )
}
