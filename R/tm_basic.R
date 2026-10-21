# Small built-in modules so the core app needs only teal (no teal.modules.general,
# whose tern dependency requires R >= 4.4).

#' Static "About" page: a key/value table plus footnotes.
tm_about <- function(label = "About", info = character(0), footnotes = character(0)) {
  teal::module(
    label = label,
    datanames = NULL,
    ui = function(id) {
      rows <- lapply(names(info), function(k) shiny::tags$tr(shiny::tags$th(k, style = "padding-right:16px"),
                                                              shiny::tags$td(info[[k]])))
      notes <- lapply(names(footnotes), function(k) shiny::tags$p(shiny::tags$strong(paste0(k, ": ")), footnotes[[k]]))
      shiny::div(style = "padding:12px; max-width:900px",
                 shiny::tags$table(class = "table", rows),
                 notes)
    },
    server = function(id) shiny::moduleServer(id, function(input, output, session) NULL)
  )
}

#' Browse any dataset in the (filtered, role-masked) data.
tm_listings <- function(label = "Data listings") {
  teal::module(
    label = label,
    datanames = "all",
    ui = function(id) {
      ns <- shiny::NS(id)
      shiny::tagList(
        shiny::selectInput(ns("dataset"), "Dataset", choices = NULL),
        DT::DTOutput(ns("table"))
      )
    },
    server = function(id, data) {
      shiny::moduleServer(id, function(input, output, session) {
        shiny::observe({
          dn <- Filter(function(n) is.data.frame(data()[[n]]), names(data()))
          cur <- shiny::isolate(input$dataset)
          shiny::updateSelectInput(session, "dataset", choices = dn, selected = if (isTRUE(cur %in% dn)) cur else dn[1])
        })
        output$table <- DT::renderDT({
          df <- data()[[shiny::req(input$dataset)]]
          shiny::req(is.data.frame(df))
          DT::datatable(df, rownames = FALSE, filter = "top",
                        options = list(pageLength = 25, scrollX = TRUE))
        })
      })
    }
  )
}
