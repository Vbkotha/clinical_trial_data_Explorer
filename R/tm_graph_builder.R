# Bespoke graphs + preset library, on ONE engine.
#
# A graph is a small declarative spec (dataset, geom, x, y, colour, facet, param
# filter). Presets are specs stored in config/graph_presets.yml (curated, version
# controlled). Users build bespoke graphs in the same UI and can save their spec
# to a personal library. Because specs reference variable names only, a saved
# graph re-renders against whatever data the current user's role allows.

GEOMS <- c("point", "line", "boxplot", "bar", "histogram", "violin")

#' Add ADSL variables (ARM, SEX, ...) to a child dataset so they can be used
#' for colour / facet. Inner join, so ADSL-level filters carry through.
with_adsl <- function(td_or_list, dataname) {
  df <- td_or_list[[dataname]]
  if (dataname == "ADSL" || !"USUBJID" %in% names(df)) return(df)
  adsl <- td_or_list[["ADSL"]]
  extra <- c("USUBJID", setdiff(names(adsl), names(df)))
  merge(df, adsl[, extra, drop = FALSE], by = "USUBJID")
}

#' Build a ggplot from a spec. Pure function: testable, reusable in batch.
build_graph <- function(df, spec) {
  library(ggplot2)
  if (!is.null(spec$paramcd) && "PARAMCD" %in% names(df)) df <- df[df$PARAMCD %in% spec$paramcd, ]
  stopifnot(spec$geom %in% GEOMS, spec$x %in% names(df))
  has <- function(v) !is.null(v) && length(v) == 1 && nzchar(v)
  vars <- list(x = spec$x)
  if (has(spec$y))      vars$y <- spec$y
  if (has(spec$colour)) vars$colour <- spec$colour
  if (has(spec$colour) && spec$geom %in% c("bar", "histogram", "boxplot", "violin")) vars$fill <- spec$colour
  if (has(spec$group) && spec$geom == "line") vars$group <- spec$group
  m <- aes(!!!lapply(vars, function(v) rlang::expr(.data[[!!v]])))
  if (spec$geom %in% c("point", "line", "boxplot", "violin") && !has(spec$y)) stop("Choose a Y variable for a ", spec$geom, " plot")

  layer <- switch(spec$geom,
    point = geom_point(alpha = 0.7, size = 2),
    line = geom_line(alpha = 0.6),
    boxplot = geom_boxplot(alpha = 0.6, outlier.alpha = 0.4),
    violin = geom_violin(alpha = 0.6),
    bar = geom_bar(position = "dodge"),
    histogram = geom_histogram(bins = 30, alpha = 0.7, position = "identity")
  )
  p <- ggplot(df, m) + layer + theme_minimal(base_size = 13) + labs(title = spec$title)
  if (!is.null(spec$summary) && isTRUE(spec$summary) && spec$geom == "line") {
    m_sum <- aes(!!!lapply(vars[setdiff(names(vars), "group")], function(v) rlang::expr(.data[[!!v]])))
    p <- ggplot(df, m_sum) +
      stat_summary(fun = mean, geom = "line", linewidth = 1) +
      stat_summary(fun.data = mean_se, geom = "errorbar", width = 2) +
      theme_minimal(base_size = 13) + labs(title = spec$title, y = paste("Mean", spec$y))
  }
  if (has(spec$facet)) p <- p + facet_wrap(stats::as.formula(paste("~", spec$facet)), scales = "free_y")
  p
}

load_presets <- function(path = "config/graph_presets.yml") yaml::read_yaml(path)

user_library_path <- function(user) {
  root <- Sys.getenv("GRAPH_LIBRARY_DIR", state_dir("user_graphs"))
  file.path(root, paste0(gsub("[^A-Za-z0-9._-]", "_", user), ".json"))
}

tm_graph_builder <- function(label = "Graph builder", presets = load_presets(),
                             datanames = "all") {
  teal::module(
    label = label,
    datanames = datanames,
    ui = function(id) {
      ns <- shiny::NS(id)
      shiny::sidebarLayout(
        shiny::sidebarPanel(width = 3,
          shiny::selectInput(ns("source"), "Start from",
            c("Blank" = "", stats::setNames(paste0("preset:", names(presets)),
                                            paste("Preset:", vapply(presets, `[[`, "", "title"))))),
          shiny::selectInput(ns("my"), "My saved graphs", choices = c("(none)" = "")),
          shiny::hr(),
          shiny::selectInput(ns("dataset"), "Dataset", choices = NULL),
          shiny::selectInput(ns("geom"), "Geometry", GEOMS),
          shiny::selectizeInput(ns("paramcd"), "PARAMCD (if present)", choices = NULL, multiple = TRUE),
          shiny::selectInput(ns("x"), "X", choices = NULL),
          shiny::selectInput(ns("y"), "Y", choices = NULL),
          shiny::selectInput(ns("colour"), "Colour", choices = NULL),
          shiny::selectInput(ns("group"), "Group (line)", choices = NULL),
          shiny::selectInput(ns("facet"), "Facet", choices = NULL),
          shiny::checkboxInput(ns("summary"), "Line: plot mean +/- SE", FALSE),
          shiny::textInput(ns("title"), "Title"),
          shiny::actionButton(ns("save"), "Save to my library", icon = shiny::icon("bookmark"))
        ),
        shiny::mainPanel(width = 9, shiny::plotOutput(ns("plot"), height = "650px"))
      )
    },
    server = function(id, data) {
      shiny::moduleServer(id, function(input, output, session) {
        lib_file <- shiny::reactive(user_library_path(get_access(session)$user %||% "anonymous"))
        my_lib <- shiny::reactiveVal(list())
        shiny::observe({
          f <- lib_file()
          my_lib(if (file.exists(f)) jsonlite::read_json(f) else list())
        })
        pending <- shiny::reactiveVal(NULL)   # spec waiting to be applied after dataset switch

        shiny::observe({
          dn <- Filter(function(n) is.data.frame(data()[[n]]), names(data()))
          cur <- shiny::isolate(input$dataset)
          shiny::updateSelectInput(session, "dataset", choices = dn, selected = if (isTRUE(cur %in% dn)) cur else dn[1])
        })
        shiny::observe({
          shiny::updateSelectInput(session, "my", choices = c("(none)" = "", names(my_lib())))
        })

        apply_spec <- function(spec) {
          pending(spec)
          shiny::updateSelectInput(session, "dataset", selected = spec$dataset)
          shiny::updateSelectInput(session, "geom", selected = spec$geom)
          shiny::updateCheckboxInput(session, "summary", value = isTRUE(spec$summary))
          shiny::updateTextInput(session, "title", value = spec$title %||% "")
        }
        shiny::observeEvent(input$source, if (startsWith(input$source, "preset:"))
          apply_spec(presets[[sub("^preset:", "", input$source)]]))
        shiny::observeEvent(input$my, if (nzchar(input$my)) apply_spec(my_lib()[[input$my]]))

        # refresh variable pickers when dataset changes; apply pending spec values
        shiny::observeEvent(list(input$dataset, data()), {
          shiny::req(input$dataset)
          df <- with_adsl(data(), input$dataset)
          v <- names(df); opt <- c("None" = "", v)
          s <- pending() %||% list()
          shiny::updateSelectInput(session, "x", choices = v, selected = s$x %||% v[1])
          shiny::updateSelectInput(session, "y", choices = opt, selected = s$y %||% "")
          shiny::updateSelectInput(session, "colour", choices = opt, selected = s$colour %||% "")
          shiny::updateSelectInput(session, "group", choices = opt, selected = s$group %||% "")
          shiny::updateSelectInput(session, "facet", choices = opt, selected = s$facet %||% "")
          pc <- if ("PARAMCD" %in% v) sort(unique(df$PARAMCD)) else character(0)
          shiny::updateSelectizeInput(session, "paramcd", choices = pc, selected = unlist(s$paramcd) %||% pc[1])
          pending(NULL)
        })

        spec <- shiny::reactive({
          list(dataset = input$dataset, geom = input$geom, x = input$x, y = input$y,
               colour = input$colour, group = input$group, facet = input$facet,
               paramcd = input$paramcd, summary = input$summary, title = input$title)
        })

        output$plot <- shiny::renderPlot({
          s <- spec()
          df <- with_adsl(data(), shiny::req(s$dataset))
          shiny::req(s$x, s$x %in% names(df))
          tryCatch(build_graph(df, s),
                   error = function(e) shiny::validate(shiny::need(FALSE, conditionMessage(e))))
        })

        shiny::observeEvent(input$save, {
          nm <- if (nzchar(input$title)) input$title else paste(input$dataset, input$geom, format(Sys.time(), "%H%M%S"))
          lib <- my_lib(); lib[[nm]] <- spec(); my_lib(lib)
          f <- lib_file()
          dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
          jsonlite::write_json(lib, f, auto_unbox = TRUE, pretty = TRUE)
          shiny::showNotification(paste("Saved:", nm), type = "message")
        })
      })
    }
  )
}
