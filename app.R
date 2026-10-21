# Trial Explorer - teal app, one study per running instance.
#   From a notebook:  source("launch.R"); run_trial_explorer("STUDY-001", role = "blinded")
#   From a terminal:  APP_STUDY=STUDY-001 APP_ROLE=blinded Rscript -e 'shiny::runApp(".", port = 3838, host = "0.0.0.0")'
# See R/auth.R for how the user and role are determined.

# installs teal and the other packages on first start, then only checks versions
source("install.R", local = TRUE)
ensure_packages()

library(teal)

# teal.modules.clinical needs R >= 4.4; without it the "Standard outputs" group is skipped
has_clinical <- requireNamespace("teal.modules.clinical", quietly = TRUE) &&
  requireNamespace("teal.picks", quietly = TRUE)

for (f in list.files("R", full.names = TRUE, pattern = "\\.R$")) source(f)

study_id  <- Sys.getenv("APP_STUDY", "STUDY-001")
studies   <- yaml::read_yaml("config/studies.yml")
roles_cfg <- yaml::read_yaml("config/roles.yml")
study     <- studies[[study_id]]
if (is.null(study)) stop("Unknown APP_STUDY: ", study_id)

completed <- identical(study$status, "completed")

# Demo only: generate locked TFLs for the synthetic completed study
if (completed && identical(study$source, "synthetic") && !file.exists(file.path(study$tfl_dir, "manifest.csv"))) {
  make_demo_tfls(make_synthetic_study(study_id, seed = 2), study$tfl_dir)
}

# ---- modules (static per deployment; access is enforced in the data) ----------
analysis <- modules(
  label = "Analysis",
  tm_exposure_hem(),
  tm_diary(),
  tm_graph_builder(label = "Graph builder & presets")
)

app_modules <- list(
  tm_about(
    label = "About",
    info = c(
      "Study"  = study$title,
      "Status" = if (completed) paste("Completed - database locked", study$locked_on) else "Ongoing - blinded views apply by role"
    ),
    footnotes = c("Access" = "Your role is set when the app is launched in this workspace; blinding is applied server-side before any data reaches the app.")
  ),
  if (completed) tm_closed_tfls(study_id, study$tfl_dir, study$locked_on),
  if (has_clinical) standard_library(unlist(study$datasets)),
  analysis,
  tm_listings(label = "Data listings")
)
app_modules <- do.call(modules, Filter(Negate(is.null), app_modules))

# ---- filters: locked population flag (anchored + fixed => user cannot remove or change) ----
filters <- teal_slices(
  teal_slice(dataname = "ADSL", varname = "SAFFL", selected = "Y", fixed = TRUE, anchored = TRUE),
  teal_slice(dataname = "ADLB", varname = "PARAMCD", selected = c("PLAT", "HGB", "WBC", "NEUT")),
  count_type = "all"
)

app <- init(
  data    = study_data_module(study_id, study, roles_cfg),
  modules = app_modules,
  filter  = filters
) |>
  modify_title(title = paste("Trial Explorer -", study_id)) |>
  modify_header(element = shiny::uiOutput("role_banner"))

# Role banner, so users always know which view they are on
server <- function(input, output, session) {
  session$userData$access <- shiny::reactiveVal(NULL)   # filled by study_data_module
  output$role_banner <- shiny::renderUI({
    a <- get_access(session)
    if (is.null(a) || is.null(a$role)) return(NULL)
    cls <- if (isTRUE(a$policy$blinded)) "warning" else "success"
    shiny::div(class = paste0("alert alert-", cls), style = "margin:0; padding:6px 12px;",
               sprintf("%s | %s | role: %s%s", study_id, a$user, a$role,
                       if (isTRUE(a$policy$blinded)) " (BLINDED VIEW)" else ""))
  })
  app$server(input, output, session)
}

shiny::shinyApp(app$ui, server)
