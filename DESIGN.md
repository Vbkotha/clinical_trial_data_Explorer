# Trial Explorer: design

A teal (R/Shiny) app covering four use cases: role-based blinded and unblinded access, cross-dimension haematology views, patient diary text, and bespoke graphs alongside a preset library.

Built against teal 1.2.1, teal.modules.clinical 0.14.0, teal.modules.general 0.9.0, teal.slice 0.8.2 and teal.data 0.8.0, the versions on the insightsengineering `latest-tag` docs as of Oct 2026. Pin these with renv.

---

## 1. Architecture

```
 Lifebit platform SSO / auth proxy
        |  identity headers (user, groups)
        v
 +-------------------- Shiny session ---------------------------------+
 |  study_data_module (teal_data_module, once = TRUE)                 |
 |    get_identity() -> resolve_role() -> access_policy()             |
 |    read_study_datasets() -> apply_policy() -> assert_policy()      |
 |    -> teal_data + join_keys      (fails closed on any leak)        |
 |                         |                                          |
 |   teal filter panel (locked SAFFL slice + user filters)            |
 |                         |                                          |
 |   About | Final TFLs* | Standard outputs | Analysis | Listings     |
 |                                     |- Exposure vs haematology     |
 |                                     |- Patient diary               |
 |                                     |- Graph builder & presets     |
 +--------------------------------------------------------------------+
   * only for status: completed
```

**One deployment per study** (`APP_STUDY`). teal builds its module tree once, when `init()` runs, not per session. Pinning a deployment to one study lets the module list follow that study's config (whether it has a TFL page, which datasets it has). Roles are still resolved per session. When a study locks, change `status` to `completed` and redeploy.

## 2. Blinded vs unblinded access

| Rule | Where it lives |
|---|---|
| Groups to role mapping, deny by default, most privileged role wins | `config/roles.yml`, `resolve_role()` |
| Per-study blinding spec: variables to mask, datasets to drop, free-text restriction | `config/studies.yml` → `blinding:` |
| Masking happens **server-side before teal gets the data** | `apply_policy()` in `study_data_module` |
| Fail-closed check: stop the session if a masked variable still holds real values or a dropped dataset is present | `assert_policy()` |
| Population flag the user cannot remove or change | `teal_slice(..., fixed = TRUE, anchored = TRUE)` |
| Visible role banner and audit line per session | `app.R`, `audit_log()` |

Why mask the data instead of hiding the UI: teal's data table, filter panel, "Show R code", reporter and the bespoke graph builder can each show any variable in memory. The only reliable blinding control is to keep unblinded values out of the session altogether.

**Blinding points to agree with the unblinded statistician for each study:**
- Exposure gives away the arm when placebo means dose = 0, or when dose levels differ by arm. The default drops `ADEX` for blinded roles. The exposure module then shows labs and response with a notice, and the cohort exposure scatter is turned off.
- Derived variables can carry arm information too, e.g. dose intensity in ADSL, PK concentrations, or arm-specific lab schedules. Add them to `mask_vars` or `drop_datasets`.
- Diary free text can unblind ("my injection site…"). It is hidden for blinded roles by default (`restrict_free_text`).
- Small subgroups plus AE patterns can leak indirectly. Consider a minimum-cell-size rule for blinded aggregate views.

**Completed trials, "closed TFLs":** final outputs come from the validated production pipeline, not from this app. `tm_closed_tfls()` serves them read-only and checks each file against the SHA-256 in the locked `manifest.csv`. A file that fails the check is not displayed. Interactive modules still run on the locked data and are labelled exploratory.

> Assumption to confirm: "closed TFLs" means the final outputs are frozen and served as-is, and exploration on the locked data is still allowed. If exploration should be switched off for completed studies, drop the `analysis` group when `completed` is true in `app.R`.

**Identity on the Lifebit platform:** `get_identity()` reads the user and group headers from `session$request`. The header names are placeholders, set with `AUTH_USER_HEADER` and `AUTH_GROUPS_HEADER`. Still to confirm with the platform team:
1. which headers the platform proxy injects;
2. that they reach `session$request` in your Shiny Server setup;
3. that the app container can only be reached through that proxy, since trusting headers depends on it.

## 3. Cross-dimension views (`tm_exposure_hem`)

A shared study-day window drives two views:

- **Patient profile:** time-aligned panels for one subject showing dose bars (with held and reduced annotations), each selected lab parameter against its normal-range band with LOW and HIGH points coloured, and response assessments.
- **Cohort scatter:** one point per subject. X is an exposure metric in the window (cumulative dose, dose intensity, or days on drug). Y is a lab metric in the window (nadir, % change at nadir, max, or last). Colour by best response, arm, sex or site, with a loess trend.

The global teal filter panel applies first. For example, filter ADSL to a site or ADRS to responders, and both views update. The computation is in plain functions (`patient_profile_data`, `cohort_window_summary`) so it can be unit-tested and reused in batch outputs.

Built-in alternatives you can add next to it: `tm_g_lineplot` (already in the standard library), and the teal.modules.clinical patient-profile modules (`tm_g_pp_patient_timeline`, `tm_t_pp_laboratory`, `tm_g_pp_vitals`).

## 4. Diary data (`tm_diary`)

- `ADDIARY` (custom ADaM-style): `STUDYID, USUBJID, DIARYSEQ, ADTM (POSIXct), ADY, DIARYCAT, DIARYTXT`. It joins to ADSL on `STUDYID, USUBJID`, so the global filters apply to it.
- Literal keyword search (comma-separated terms) with highlighting. Text is **HTML-escaped before highlighting** because patient text is untrusted input, which makes `DT::datatable(escape = FALSE)` safe here.
- Timeline of entries by subject and category. With 6 subjects or fewer, a lab parameter (e.g. platelets) can be overlaid with diary entries marked along the x-axis, so "bruising" entries can be read against platelet nadirs.
- If diary data arrives as raw ePRO, map it to this structure upstream. Timezone handling of `ADTM` should be fixed at that stage.

## 5. Bespoke graphs + preset library

One engine, `build_graph(df, spec)`, is used two ways:

- **Presets:** curated specs in `config/graph_presets.yml`. Adding a standard graph means adding a YAML entry through a reviewed pull request, with no code change. A test renders every preset.
- **Bespoke:** the same UI with free choice of dataset, geometry, x, y, colour, group, facet and PARAMCD. Users can save a spec to a personal library (`GRAPH_LIBRARY_DIR/<user>.json`).
- A spec stores **variable names only**. A saved graph therefore re-renders against whatever data the current user's role allows, and a spec saved by an unblinded user cannot leak arm values to a blinded one.
- ADSL variables (ARM, SEX…) are joined onto child datasets automatically, so they can be used for colour and facet.

The heavier standard outputs (demographics `tm_t_summary`, AE table `tm_t_events`, lab line plot `tm_g_lineplot`) come from teal.modules.clinical in `R/standard_library.R`. The reporter is left on (teal default), so users can collect outputs into a report.

## 6. Files

```
app.R                     init(), module tree, locked filter, role banner
config/studies.yml        study status, data source, blinding spec, TFL dir
config/roles.yml          IdP groups -> role per study
config/graph_presets.yml  preset graph library
R/auth.R                  identity from proxy headers (+ dev mode)
R/access.R                role resolution, policy, apply/assert blinding
R/data_module.R           teal_data_module, loaders, join keys, audit
R/tm_exposure_hem.R       cross-dimension module
R/tm_diary.R              diary module
R/tm_graph_builder.R      bespoke builder + preset engine
R/tm_closed_tfls.R        locked TFL viewer with checksum verification
R/standard_library.R      teal.modules.clinical presets
R/synthetic.R             synthetic ADSL/ADEX/ADLB/ADRS/ADAE/ADDIARY + demo TFLs
tests/test_core.R         unit tests for access, blinding, diary, metrics, presets
```

## 7. Run locally

```r
renv::install(c("teal", "teal.modules.general", "teal.modules.clinical", "teal.picks",
                "yaml", "DT", "ggplot2", "digest", "jsonlite", "testthat"))
```

```bash
# blinded study-team member on the ongoing study
APP_DEV_MODE=true DEV_USER=me@lifebit.ai DEV_GROUPS=study001-study-team APP_STUDY=STUDY-001 \
  Rscript -e 'shiny::runApp(".", port = 3838)'
# unblinded DMC statistician:   DEV_GROUPS=study001-dmc
# completed study with final TFLs: APP_STUDY=STUDY-002 DEV_GROUPS=study002-team
Rscript -e 'testthat::test_file("tests/test_core.R")'
```

## 8. Verification status

- **Tested:** the access, blinding, diary and metric logic, and preset rendering, with 35 passing unit tests on R 4.3.3. Module plots were rendered to PNG and checked by eye.
- **Not yet run end to end:** the teal wiring (`app.R`, the `teal::module()` wrappers, `standard_library.R`). teal could not be installed in the build environment. It is written against the current reference docs, but run it once locally before demoing. The calls most likely to need adjustment are the `teal.picks` arguments in `standard_library.R` (new in teal.modules.clinical 0.14) and `modify_header()` with the root-level `role_banner` output.

## 9. Next steps
1. Confirm the identity headers and the proxy-only network path with the platform team.
2. Get each study's `mask_vars` and `drop_datasets` signed off by its unblinded statistician, and add a CI test per study.
3. Replace `source: synthetic` with `source: files` pointing at the study's ADaM folder.
4. Send the audit log to durable storage or the platform audit API.
5. Optional: add `shinytest2` smoke tests per role, checking that a blinded session never renders an arm value.
