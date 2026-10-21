# Data preparation guide

How to get your study data into a shape Trial Explorer can read, configure it, and check it before launching.

**In short:** Trial Explorer reads **ADaM-style datasets, one file per dataset, in one folder**. Every dataset links to ADSL by `STUDYID` and `USUBJID`. Only ADSL is required. Each other dataset turns on the views that use it.

---

## 1. Folder and file layout

```
/mnt/session_data/my_study/adam/
├── adsl.sas7bdat      required
├── adlb.sas7bdat      labs: haematology views, lab line plot
├── adex.xpt           exposure: dose panel, cohort exposure metrics
├── adrs.parquet       response: response panel, best response
├── adae.csv           adverse events: AE table
└── addiary.rds        patient diary: diary search and timeline
```

- **File names:** each file is named after its dataset, followed by the extension: `adsl.<ext>`, `adlb.<ext>` and so on. Upper or lower case both work.
- **One file per dataset:** if two files match (for example `adsl.csv` and `adsl.xpt`), the first one alphabetically is used.
- **Location:** the folder can be anywhere the session can read, such as `/mnt/session_data/...`. A relative path is taken from the app folder.

### Supported formats

| Extension | Read with | Notes |
|---|---|---|
| `.sas7bdat` | `haven::read_sas()` | Keeps SAS labels and dates. Needs `haven`. |
| `.xpt` | `haven::read_xpt()` | SAS transport files. Needs `haven`. |
| `.parquet` | `arrow::read_parquet()` | Needs `arrow`. |
| `.rds` | `readRDS()` | An R data frame saved with `saveRDS()`. Keeps every R type. |
| `.csv` | `read.csv()` | See [CSV rules](#csv-rules). |

`haven` and `arrow` are optional installs:

```bash
TRIAL_EXPLORER_OPTIONAL=true Rscript install.R
```

---

## 2. Datasets and variables

The conventions are standard ADaM: one row per subject in ADSL, and one row per record in the others.

- **Required columns:** without them, the module that uses the dataset fails, and the app refuses to start.
- **Recommended columns:** without them, a particular view or option is empty, but the app still runs.

Types: **chr** is text, **num** is a number, **date** is a calendar date, **datetime** is a date and time.

### ADSL: subject level (required dataset)

One row per subject. `USUBJID` must be unique.

| Variable | Type | Required? | Used for |
|---|---|---|---|
| `STUDYID` | chr | required | joins |
| `USUBJID` | chr | required | joins; subject pickers |
| `ARM` | chr | required | treatment column in tables, colour in plots (masked when blinded) |
| `ARMCD` | chr | recommended | alternative treatment variable |
| `SAFFL` | chr `Y`/`N` | recommended | **locked population filter: only `SAFFL == "Y"` subjects are shown** |
| `AGE` | num | recommended | demographics table |
| `SEX` | chr | recommended | demographics table, colour option |
| `SITEID` | chr | recommended | colour option, filters |
| `ACTARM`, `TRT01P`, `TRT01A`, `TRT01AN`, … | | optional | any treatment-revealing variable must be listed in `mask_vars` |

Any other ADSL column (race, region, baseline characteristics) can be used in filters and the graph builder. ADSL variables are also joined onto the other datasets in the graph builder, so you can colour or facet any plot by them.

### ADLB: laboratory results

One row per subject × parameter × visit.

| Variable | Type | Required? | Used for |
|---|---|---|---|
| `STUDYID`, `USUBJID` | chr | required | joins |
| `PARAMCD` | chr | required | parameter selection; must contain the codes in `lab_params` |
| `PARAM` | chr | required | panel and axis titles |
| `AVAL` | num | required | the value plotted |
| `ADY` | num | required | study day (x-axis, study-day window) |
| `AVISIT` | chr | recommended | visit axis of the lab line plot |
| `BASE` | num | recommended | "% change at nadir" metric |
| `CHG`, `PCHG` | num | recommended | lab line plot y options |
| `ANRLO`, `ANRHI` | num | recommended | normal-range band |
| `ANRIND` | chr `LOW`/`NORMAL`/`HIGH` | recommended | colours out-of-range points |

The lab codes featured in the views are set per study with `lab_params` (default `PLAT, HGB, WBC, NEUT`). Use the `PARAMCD` values in your data, for example `[PLT, HGB, WBC, ANC]`.

### ADEX: exposure (dose)

One row per dosing interval.

| Variable | Type | Required? | Used for |
|---|---|---|---|
| `STUDYID`, `USUBJID` | chr | required | joins |
| `AVAL` | num | required | dose in the interval; `0` = no dose given |
| `ASTDY`, `AENDY` | num | required | interval start and end study day |
| `EXADJ` | chr | recommended | label shown on the dose bar, e.g. `DOSE HELD`, `DOSE REDUCED` (blank otherwise) |

The cohort scatter's exposure metrics are calculated within the selected study-day window:

| Metric | Calculation |
|---|---|
| Cumulative dose | sum of `AVAL` |
| Dose intensity (per week) | cumulative dose ÷ days spanned × 7 |
| Days on drug | sum of `AENDY − ASTDY + 1` over intervals with `AVAL > 0` |

> **Blinding:** ADEX is dropped for blinded users by default (`drop_datasets: [ADEX]`), because dose levels or a placebo dose of 0 reveal the arm.

### ADRS: response

| Variable | Type | Required? | Used for |
|---|---|---|---|
| `STUDYID`, `USUBJID` | chr | required | joins |
| `AVALC` | chr | required | response code, e.g. `CR`, `PR`, `SD`, `PD`, `NE` |
| `ADY` | num | required | study day of the assessment |

- **Overall response only.** Include only overall-response records, filtered to one `PARAMCD` (for example `OVRLRESP`) before export. The app treats every ADRS row as an overall response assessment.
- **Best response** is the best code in the window. Text codes are ordered `CR` > `PR` > `SD` > `NON-CR/NON-PD` > `PD` > `NE`, then any other codes alphabetically. To use your own order, save `AVALC` as an R factor whose levels run from best to worst (`.rds`).

### ADAE: adverse events

| Variable | Type | Required? | Used for |
|---|---|---|---|
| `STUDYID`, `USUBJID` | chr | required | joins |
| `AEBODSYS` | chr | recommended | system organ class rows of the AE table |
| `AEDECOD` | chr | recommended | preferred term rows of the AE table |
| `AESEQ` | num | optional | record key |

### ADDIARY: patient diary (custom, ADaM-style)

One row per diary entry. This isn't a standard ADaM dataset. Map your ePRO export to this structure.

| Variable | Type | Required? | Used for |
|---|---|---|---|
| `STUDYID`, `USUBJID` | chr | required | joins |
| `DIARYSEQ` | num | required | entry number within subject |
| `ADTM` | datetime | required | entry date and time (fix the timezone before export) |
| `ADY` | num | required | study day of the entry |
| `DIARYCAT` | chr | required | category, e.g. `Fatigue`, `Bleeding/bruising` |
| `DIARYTXT` | chr | required | the free text |

> **Blinding:** diary text is hidden from blinded users by default (`restrict_free_text: true`), because patients can describe things that reveal the arm.

### Other datasets

You can list any other dataset in `datasets:`, for example ADVS or ADCM. It appears in the data listings, the filter panel and the graph builder. Include `STUDYID` and `USUBJID` so ADSL filters apply to it.

---

## 3. General rules

- **Study day (`ADY`, `ASTDY`, `AENDY`)** is numeric. Use the ADaM convention: day 1 is the first dose day, and days before it are negative. Days can be negative or beyond the end of treatment; the sliders size themselves to the data.
- **Missing values:** leave the cell empty, or `NA` in CSV.
- **Labels:** SAS files keep their variable labels. Columns without a label get a standard CDISC label (`AGE` → "Age") or, failing that, their own name. Tables use these labels.
- **Treatment variables in child datasets:** if ADLB, ADAE or another dataset carries a copy of `ARM` or `TRT01A`, it is masked too, because `mask_vars` applies to every dataset. Even so, a treatment-revealing variable that isn't listed in `mask_vars` is **not** masked.
- **Size:** everything is loaded into memory for each session. Tens of thousands of rows per dataset are fine; for millions, pre-filter to the variables and records you need.

### CSV rules

CSV files have no column types, so:
- **Dates:** columns whose names end in `DT` (e.g. `TRTSDT`, `ADT`) are read as dates. Write them as `YYYY-MM-DD`.
- **Datetimes:** columns whose names end in `DTM` (e.g. `ADTM`) are read as datetimes, in UTC. Write them as `YYYY-MM-DD HH:MM:SS`.
- **Everything else:** text stays text, and numbers become numbers.
- **Encoding:** use UTF-8, with a header row and comma separators.

Example `adsl.csv`:

```csv
STUDYID,USUBJID,SUBJID,SITEID,AGE,SEX,ARM,ARMCD,TRTSDT,SAFFL
MY-STUDY,MY-STUDY-001,001,S01,64,F,Drug X 10 mg,ARM A,2026-01-12,Y
MY-STUDY,MY-STUDY-002,002,S02,58,M,Placebo,ARM C,2026-01-19,Y
```

### Exporting from R

If your data is already in R as data frames, `.rds` is the easiest format, because it keeps types, factor levels and labels:

```r
dir <- "/mnt/session_data/my_study/adam"
dir.create(dir, recursive = TRUE, showWarnings = FALSE)
saveRDS(adsl, file.path(dir, "adsl.rds"))
saveRDS(adlb, file.path(dir, "adlb.rds"))
# ...one file per dataset
```

---

## 4. Configure the study

Add an entry to `config/studies.yml`. There's a commented `MY-STUDY` template at the bottom of the file.

```yaml
MY-STUDY:
  title: "MY-STUDY - Drug X in ... (Phase II)"
  status: ongoing                       # ongoing | completed
  source: files
  data_dir: /mnt/session_data/my_study/adam
  datasets: [ADSL, ADLB, ADEX, ADRS, ADAE, ADDIARY]   # only the ones you have
  lab_params: [PLAT, HGB, WBC, NEUT]    # your ADLB PARAMCDs
  tfl_dir: null
  blinding:                             # ongoing studies
    mask_value: "BLINDED"
    mask_vars: [ARM, ARMCD, ACTARM, ACTARMCD, TRT01P, TRT01A, TRT01PN, TRT01AN]
    drop_datasets: [ADEX]
    restrict_free_text: true
```

**Blinding (ongoing studies).** Agree the settings with the study's unblinded statistician:
- **`mask_vars`:** every variable, in any dataset, that reveals treatment. Think of dose intensity in ADSL, PK concentrations, or arm-specific visit schedules.
- **`drop_datasets`:** datasets that reveal treatment on their own (typically ADEX, or a PK dataset).
- **`restrict_free_text`:** hides diary text for blinded users.

**Completed studies:** set `status: completed`, `blinding: null`, and `tfl_dir` to a folder containing the final outputs plus a `manifest.csv`. The manifest has these columns:

```csv
output_id,title,type,file,sha256
T-14.1.1,"Demographics, Safety Population",Table,T-14.1.1.pdf,<sha256 of the file>
```

Each output is shown only if its SHA-256 matches the manifest. To compute one: `digest::digest(file = "T-14.1.1.pdf", algo = "sha256")`.

---

## 5. Check, then launch

```r
setwd("/path/to/clinical_trial_data_Explorer")
source("launch.R")
check_trial_data("MY-STUDY")
```

The check loads the files exactly as the app does, then reports:
- the rows and columns per dataset;
- **errors**, which stop the app from starting:
  - ADSL missing;
  - a required column missing;
  - duplicate `USUBJID` in ADSL;
  - none of the `mask_vars` present in the data, so the blinded view would hide nothing;
- **warnings**, where the app still starts:
  - a recommended column missing;
  - a `lab_params` code not found in `ADLB$PARAMCD`;
  - a dataset with no `USUBJID`.

When it reports no errors:

```r
run_trial_explorer(study = "MY-STUDY", role = "blinded")     # or "unblinded"
```

---

## 6. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Missing dataset ADLB in <dir>` | file not found or misnamed | name it `adlb.<ext>`; check `data_dir` |
| `Unsupported file type` | extension not in the table above | convert to `.rds`, `.csv`, `.xpt`, `.sas7bdat` or `.parquet` |
| `there is no package called 'haven'` / `'arrow'` | optional reader not installed | `TRIAL_EXPLORER_OPTIONAL=true Rscript install.R` |
| App shows "The study data does not match what the app needs" | `check_trial_data()` errors | run `check_trial_data("MY-STUDY")` and fix the listed items |
| No subjects anywhere | `SAFFL` is not `"Y"` for anyone, or is coded differently (e.g. `"YES"`) | recode `SAFFL` to `Y`/`N` |
| Haematology views empty | `lab_params` don't match your `PARAMCD`s | set `lab_params` in `studies.yml` |
| Dates show as text or numbers | CSV date column name doesn't end in `DT`/`DTM`, or isn't `YYYY-MM-DD` | rename or reformat, or use `.rds` |
| Best response looks wrong | ADRS has several `PARAMCD`s, or non-standard codes | keep overall response only; save `AVALC` as an ordered factor in `.rds` |
| Blinded user can still infer arm | a revealing variable isn't in `mask_vars`, or a revealing dataset isn't in `drop_datasets` | add it; re-check with the unblinded statistician |
