# 🏥 Medical Appointment No-Show Analysis

Analyzing **110,527 medical appointments** from public healthcare clinics in Brazil to understand *why patients miss appointments* — and to build a simple, queryable risk model that flags high-risk appointments before they happen.

Built entirely in **T-SQL (Microsoft SQL Server Management Studio)**, using CTEs, window functions, and a persistent view for downstream reporting.

![Schema and query results in SSMS](images/schema_screenshot.png)

---

## 📌 Project Overview

No-shows are one of the most expensive, quietly-recurring problems in healthcare operations — every missed appointment is wasted clinical capacity, a lost slot another patient could have used, and a hit to revenue. This project digs into a real-world appointment dataset to answer a simple operational question:

> **Which patients, appointments, and conditions are most associated with no-shows — and can we flag that risk in advance?**

The project covers the full analytics workflow: importing raw data into SQL Server, cleaning and typing it correctly, exploring it with aggregate and window-function queries, and packaging the result into a reusable SQL **view** that scores every future appointment's risk.

---

## 🛠️ Tools & Technologies

| Tool | Purpose |
|---|---|
| **Microsoft SQL Server (SSMS)** | Database engine + query editor for the entire analysis |
| **T-SQL** | All data cleaning, exploration, and modeling logic |
| **Kaggle Medical Appointment No-Show Dataset** | Source data (110,527 rows, 14 columns) |

---

## 🗂️ Dataset

Source: [Medical Appointment No Shows — Kaggle](https://www.kaggle.com/datasets/joniarroba/noshowappointments)

Each row is one scheduled medical appointment, with fields covering:

- **Patient info**: `PatientId`, `Gender`, `Age`
- **Scheduling**: `ScheduledDay` (when the appointment was booked), `AppointmentDay` (the actual appointment date)
- **Location**: `Neighbourhood`
- **Health/social flags**: `Scholarship` (welfare program enrollment), `Hipertension`, `Diabetes`, `Alcoholism`, `Handcap`
- **Reminders**: `SMS_received`
- **Target**: `No-show` (`Yes` = patient missed the appointment, `No` = patient showed up)

---

## 🧹 Data Cleaning

Before analysis, the raw import was cleaned and typed properly:

- **Renamed columns** for clarity and consistency (`Hipertension` → `hypertension`, `Handcap` → `disability_count`) using `sp_rename`.
- **Fixed data types** with `ALTER TABLE ... ALTER COLUMN`: cast `hypertension`/`disability_count` to `INT`, `No_show` to `VARCHAR(3)`, `ScheduledDay` to `DATETIME2(0)`, and `AppointmentDay` to `DATE`.
- **Removed invalid ages**: one row had `Age = -1`, which is not a valid human age — deleted.
- **Engineered a lead-time feature**: added a `lead_time_days` column (`DATEDIFF(day, ScheduledDay, AppointmentDay)`), then found and removed a handful of rows where the appointment was logged *before* it was scheduled (negative lead time) — a data-entry artifact, not a real appointment.
- Final analysis-ready dataset: **110,521 appointments**.

---

## ❓ Business Questions & SQL Techniques

Each question below maps to a query in [`medical_appointment_analysis.sql`](medical_appointment_analysis.sql).

| # | Question | SQL techniques used |
|---|---|---|
| 1 | What's our overall no-show rate? | `GROUP BY`, `COUNT`, `CAST`/`DECIMAL` for percentages |
| 2 | Does the day of the week matter? | `DATENAME`, `DATEPART`, conditional aggregation (`SUM(CASE WHEN...)`) |
| 3 | Does lead time (booking-to-appointment gap) matter? | Derived buckets via subquery + `CASE`, conditional aggregation |
| 4 | Does age matter? | Subquery + `CASE` for age banding, conditional aggregation |
| 5 | Do SMS reminders actually reduce no-shows? | `CASE`, `GROUP BY`, rate comparison |
| 6 | Which neighborhoods carry the most risk? | `GROUP BY`, `HAVING` (minimum volume threshold), `RANK() OVER (ORDER BY ...)` |
| 7 | Can we score each patient/appointment's risk *using only prior history*? | **Window functions** (`COUNT`, `SUM` with `PARTITION BY` + `ORDER BY` + `ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING`), a `CTE`, and a persisted `VIEW` |

The final query builds `v_appointment_risk`, a view that — for every appointment — looks *only* at that patient's appointment history up to (but not including) that date, and assigns a `risk_tier`:

- **New Patient – Monitor**: no prior appointment history to judge from
- **High Risk**: prior no-show rate ≥ 50%, or booked 8+ days out
- **Medium Risk**: prior no-show rate ≥ 20%, or booked 4–7 days out
- **Low Risk**: everything else

Because it only uses information available *before* the appointment happens, this view could realistically sit in front of a clinic's scheduling system to flag risky bookings in real time.

---

## 📊 Key Findings

*(Numbers below were independently re-verified against the cleaned dataset.)*

**1. Overall no-show rate: ~20.2%** — roughly 1 in 5 appointments are missed (22,314 of 110,521).

**2. Day of the week has a mild effect.** No-show rates ranged narrowly from **19.3% (Thursday)** to **21.2% (Friday)**, with Saturday appointments (a tiny sample, 39 total) running slightly higher. Day of week alone isn't a strong lever.

**3. Lead time is the single strongest driver in this dataset.**

| Lead time bucket | No-show rate |
|---|---|
| Same day | **4.7%** |
| Short (1–3 days) | 22.9% |
| Within a week (4–7 days) | 25.2% |
| Long lead (8+ days) | **32.1%** |

Booking far in advance is strongly correlated with no-shows — same-day appointments are missed at roughly **1/7th** the rate of appointments booked 8+ days out. This is the clearest actionable signal in the data.

**4. Age matters — younger patients are less reliable.**

| Age group | No-show rate |
|---|---|
| Teen (13–19) | **26.0%** |
| Young Adult (20–39) | 23.1% |
| Child (0–12) | 20.5% |
| Adult (40–59) | 18.8% |
| Senior (60+) | **15.3%** |

No-show risk falls steadily as age increases — seniors are the most reliable age group, teens the least.

**5. SMS reminders correlate with *more* no-shows, not fewer — likely a confound, not a causal effect.** Patients who received an SMS reminder had a **27.6%** no-show rate vs. **16.7%** for those who didn't. This is counterintuitive, but it lines up with finding #3: SMS reminders in this system are only sent for appointments booked well in advance (same-day bookings don't get an SMS at all), and long-lead-time appointments are exactly the ones most likely to be missed. **SMS isn't causing no-shows — lead time is driving both.** This is a good example of why single-variable comparisons can mislead without controlling for a confounding factor.

**6. Neighborhood risk varies meaningfully.** Among neighborhoods with at least 100 appointments, no-show rates ranged from about **14.6%** (safest: Mário Cypreste) up to **28.9%** (highest risk: Santos Dumont), with Santa Cecília, Santa Clara, and Itararé also in the 26–27% range. A ~2x spread between the safest and riskiest neighborhoods suggests location-targeted interventions (e.g., extra reminder calls, transport support) could be worthwhile.

**7. Patient history is highly predictive — more so than any single factor above.** Using only each patient's *prior* appointment record (via the window-function-based `v_appointment_risk` view):

| Risk tier | Share of appointments | Actual no-show rate |
|---|---|---|
| High Risk | 20.1% | **30.8%** |
| Medium Risk | 8.0% | 21.2% |
| New Patient – Monitor | 56.4% | 19.5% |
| Low Risk | 15.6% | **8.4%** |

The model cleanly separates risk: patients flagged **High Risk** no-show at nearly **4x the rate** of patients flagged **Low Risk** (30.8% vs. 8.4%) — using nothing but each patient's own history and their lead time, calculated *before* the appointment occurs. Of the ~62,300 unique patients in the dataset, about 24,400 have more than one appointment, which is what makes this history-based scoring possible.

---

## 💡 How This Is Useful

Put together, these findings suggest a clinic could meaningfully cut no-shows without any new technology, just by:
- **Front-loading same-day and short-notice slots** where possible, since lead time is the biggest single driver of no-shows.
- **Double-confirming long-lead-time bookings** (8+ days out) closer to the appointment date, rather than relying on the reminder system alone.
- **Layering in patient history**: a returning patient with a poor attendance record is a stronger risk signal than the appointment's day of week or the patient's demographics alone — the `v_appointment_risk` view operationalizes this directly.
- **Investigating the SMS/lead-time confound further** before concluding reminders don't work — a fairer test would compare SMS vs. no-SMS *within* the same lead-time bucket.

---

## 📁 Repository Contents

```
├── README.md                          # You are here
├── medical_appointment_analysis.sql   # Full cleaning + exploration + view-building script
└── images/
    └── schema_screenshot.png          # SSMS schema & query output screenshot
```

## 🚀 How to Reproduce

1. Import [`KaggleV2-May-2016.csv`](https://www.kaggle.com/datasets/joniarroba/noshowappointments) into a SQL Server database (e.g. via the Import Flat File wizard in SSMS) as `dbo.medicalappointment`.
2. Run `medical_appointment_analysis.sql` top to bottom — it renames/retypes columns, cleans invalid rows, engineers `lead_time_days`, and walks through all seven analysis questions.
3. Query the `v_appointment_risk` view directly to pull current high-risk appointments:
   ```sql
   SELECT * FROM v_appointment_risk WHERE risk_tier = 'High Risk';
   ```

---

*Dataset source: [Kaggle — Medical Appointment No Shows](https://www.kaggle.com/datasets/joniarroba/noshowappointments)*
