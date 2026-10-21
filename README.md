# Trial Explorer

An R/Shiny ([teal](https://insightsengineering.github.io/teal/)) app for exploring clinical trial ADaM data. It provides:

- blinded and unblinded views, with masking applied to the data before the app sees it;
- exposure against haematology over a shared study-day window (a patient profile and a cohort scatter);
- searching and plotting patient diary free text;
- a graph builder with a reviewed preset library;
- read-only final TFLs, checksum-verified, for completed studies.

See [DESIGN.md](DESIGN.md) for the design and the blinding rules.

![Patient profile](docs/profile_unblinded.png)

## Run it in a Lifebit notebook session

The app runs inside your already-logged-in workspace. It does no authentication of its own (see [Roles](#roles)).

### 1. Get the code into the session

In a terminal in the session:

```bash
git clone https://github.com/Vbkotha/clinical_trial_data_Explorer.git
cd clinical_trial_data_Explorer
```

You can also upload a zip of the repository and unzip it.

### 2. Start the app

There is no separate install step. On first start the app installs teal and its other packages into your R library, which takes a few minutes. Later starts only check versions.
- teal packages come from the insightsengineering r-universe.
- Everything else comes from CRAN, as precompiled Linux binaries from Posit Package Manager when the OS is recognised.
- If the session can only reach an internal mirror, set `TRIAL_EXPLORER_REPOS=https://your-mirror/...` before starting.
- To install ahead of time, run `Rscript install.R`.

**RStudio session.** Open the project folder and run:

```r
source("launch.R")
run_trial_explorer(study = "STUDY-001", role = "blinded")
```

The app opens in a new browser tab, through RStudio's port proxy. If your browser blocks the pop-up, allow pop-ups for the Lifebit site, or open the RStudio URL printed in the console. Press Stop (or Esc) in the console to quit. To keep it in the Viewer pane instead, pass `open = "viewer"`.

**Jupyter session (R kernel).** Open `notebooks/launch_trial_explorer.ipynb` and run the cells. It starts the app in a background R process:

```r
source("launch.R")
run_trial_explorer(study = "STUDY-001", role = "blinded", background = TRUE)
# ... later
stop_trial_explorer()
```

Then open `<your session URL>/proxy/3838/`. This needs jupyter-server-proxy in the Jupyter session. If that path returns 404, ask the platform team how the session exposes ports.

**Terminal.**

```bash
Rscript launch.R STUDY-001 blinded 3838        # foreground, Ctrl+C to stop
nohup Rscript launch.R STUDY-001 unblinded 3838 > ~/trial-explorer.log 2>&1 &   # background
```

The app listens on `0.0.0.0:<port>`, so the session's port proxy can reach it.

## Roles

| Role | Valid for | Sees |
|---|---|---|
| `unblinded` | any study | all data |
| `blinded` | ongoing studies | arm variables masked, `ADEX` dropped, diary text hidden |
| `viewer` | completed studies | final TFLs and locked data, no diary free text |

The role is chosen when you launch, through `role =` (or the `APP_ROLE` variable). The alternative is `APP_GROUPS`, a comma-separated list of groups mapped through `config/roles.yml`. If you set neither, the app uses the most restrictive role for the study.

Because whoever launches the app chooses the role, the blinded view only controls what the app displays. It is an access control only if the workspace user cannot read the unblinded source files directly. Per-user authentication can be added later in `get_identity()` (`R/auth.R`). See DESIGN.md §2.

## Configuration

| Setting | Where | Default |
|---|---|---|
| Study, data source, blinding spec, TFL folder | `config/studies.yml` | two synthetic demo studies |
| Group to role mapping | `config/roles.yml` | |
| Preset graphs | `config/graph_presets.yml` | |
| `APP_STUDY`, `APP_ROLE`, `APP_GROUPS`, `APP_USER` | environment (set by `run_trial_explorer()`) | `STUDY-001`, most restrictive, none, OS user |
| `APP_STATE_DIR` | environment: audit log and saved graphs | `~/.trial-explorer` |
| `AUDIT_LOG`, `GRAPH_LIBRARY_DIR` | environment: override the individual paths | under `APP_STATE_DIR` |

## Bring your own data

The full guide, covering the variables per dataset, types, CSV rules, blinding config and troubleshooting, is **[docs/DATA_PREP.md](docs/DATA_PREP.md)**. In short, the app reads ADaM-style datasets, one file per dataset, from a folder.

### 1. Put the files in a folder

Name each file after its dataset, in lower case: `adsl.sas7bdat`, `adlb.xpt`, `adae.parquet`, `adrs.rds`, `adex.csv` and so on.
- **Supported formats:** SAS (`.sas7bdat`, `.xpt`), Parquet, RDS and CSV.
- **CSV dates:** columns ending in `DT` are read as dates and columns ending in `DTM` as date-times. The other formats keep their own types.
- **Extra packages:** SAS and XPT files need `haven`, and Parquet needs `arrow`. Install them with `TRIAL_EXPLORER_OPTIONAL=true Rscript install.R`.

### 2. Check the variables

Only ADSL is required. A module whose dataset is missing is left out: no ADDIARY means no Patient diary, no ADEX means no dose panel, and so on. Every dataset joins to ADSL on `STUDYID` and `USUBJID`.

| Dataset | Required | Recommended (some views need these) |
|---|---|---|
| ADSL | `STUDYID`, `USUBJID`, `ARM` | `ARMCD`, `SAFFL` (the locked population filter keeps `SAFFL == "Y"`), `AGE`, `SEX`, `SITEID` |
| ADLB | `STUDYID`, `USUBJID`, `PARAMCD`, `PARAM`, `AVAL`, `ADY` | `AVISIT`, `BASE`, `CHG`, `PCHG`, `ANRLO`, `ANRHI`, `ANRIND` |
| ADEX | `STUDYID`, `USUBJID`, `AVAL` (dose), `ASTDY`, `AENDY` | `EXADJ` (for example "DOSE HELD") |
| ADRS | `STUDYID`, `USUBJID`, `AVALC`, `ADY` | |
| ADAE | `STUDYID`, `USUBJID` | `AEBODSYS`, `AEDECOD` |
| ADDIARY | `STUDYID`, `USUBJID`, `DIARYSEQ`, `ADTM`, `ADY`, `DIARYCAT`, `DIARYTXT` | |

A few things are handled for you:
- Columns without a `label` attribute get a standard CDISC label, or their own name.
- Response codes in ADRS are ordered from best (CR, PR, SD, PD) for "best response".
- Join keys are built from the columns that are actually present.

### 3. Add the study to `config/studies.yml`

Copy the commented `MY-STUDY` block at the end of that file and set these fields:
- **`data_dir`:** your folder.
- **`datasets`:** the datasets you have.
- **`lab_params`:** the ADLB `PARAMCD`s to feature (default `PLAT, HGB, WBC, NEUT`).
- **`status`:** `ongoing` or `completed`.

For an ongoing study, also set `blinding`. `mask_vars` must name the variables that reveal treatment in your data. Agree these with the unblinded statistician.

### 4. Check it, then launch

```r
source("launch.R")
check_trial_data("MY-STUDY")    # lists missing datasets/columns, unknown lab_params, blinding problems
run_trial_explorer(study = "MY-STUDY", role = "blinded")
```

If there are errors, for example a required column is missing or none of the `mask_vars` exist in the data, the app stops with the same messages rather than starting.

## Tests

```bash
Rscript -e 'testthat::test_file("tests/test_core.R")'
```

## Files

```
app.R                     teal app: init(), module tree, locked filter, role banner
launch.R                  run_trial_explorer() / stop_trial_explorer() for notebook sessions
install.R                 ensure_packages(): installs missing packages on first start
notebooks/                Jupyter (R kernel) launcher notebook
config/                   studies, roles, graph presets
R/                        auth, access/blinding, data loading and checks, analysis modules, synthetic data
tests/test_core.R         unit tests
docs/DATA_PREP.md         data preparation guide (bring your own data)
```
