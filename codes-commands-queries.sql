CREATE DATABASE healthcare_analytics;
USE healthcare_analytics;

SELECT TOP 20 * FROM dbo.medicalappointment

--DATA CLEANING

EXEC sp_rename 'dbo.medicalappointment.Hipertension','hypertension','COLUMN';
EXEC sp_rename 'dbo.medicalappointment.Handcap','disability_count','COLUMN';


ALTER TABLE dbo.medicalappointment ALTER COLUMN hypertension INT;
ALTER TABLE dbo.medicalappointment ALTER COLUMN disability_count INT;
ALTER TABLE dbo.medicalappointment ALTER COLUMN No_show VARCHAR(3);

SELECT 
	disability_count, 
    COUNT(*)
FROM medicalappointment
GROUP BY disability_count
ORDER BY disability_count;
	


ALTER TABLE dbo.medicalappointment ALTER COLUMN ScheduledDay DATETIME2(0);
ALTER TABLE dbo.medicalappointment ALTER COLUMN AppointmentDay DATE;

SELECT TOP 10
	ScheduledDay, 
    AppointmentDay 
FROM medicalappointment;

SELECT MIN(AGE), MAX(AGE)
FROM medicalappointment; 

SELECT AGE 
FROM medicalappointment
ORDER BY AGE; 

DELETE FROM medicalappointment 
WHERE AGE = -1;

ALTER TABLE medicalappointment ADD lead_time_days INT; 

UPDATE medicalappointment
SET lead_time_days = DATEDIFF(day, ScheduledDay, AppointmentDay);

SELECT MIN(lead_time_days), MAX(lead_time_days)
FROM medicalappointment;

SELECT * FROM medicalappointment
WHERE lead_time_days < 0;

DELETE FROM medicalappointment
WHERE lead_time_days < 0;



--DATA EXPLORATION
-- 1: What's our overall no-show rate?
 
SELECT
	No_show, 
    COUNT(*) as total_appointments, 
    CAST(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM medicalappointment)AS DECIMAL(5,1)) as pct_of_total
FROM medicalappointment
GROUP BY no_show;


-- 2: Does the day of the week matter

SELECT
	DATENAME(weekday, AppointmentDay) as appointment_day, 
    COUNT(*) as total_appointments, 
    SUM(CASE WHEN No_show = '1' THEN 1 ELSE 0 END) as no_shows,
	CAST(SUM(CASE WHEN No_show = '1' THEN 1 ELSE 0 END) * 100/ COUNT(*) AS DECIMAL(5,1)) as rate_of_no_shows
FROM medicalappointment
GROUP BY DATENAME(weekday,AppointmentDay),DATEPART(weekday, AppointmentDay)
ORDER BY DATEPART(weekday, AppointmentDay);


-- 3: Does lead time matter

-- same day
-- 1-3 days
-- within a week (4-7 days)
-- long lead (8+ days)

SELECT
	lead_time_bucket,
	COUNT(*) as total_appointments, 
	CAST(SUM(CASE WHEN no_show = '1' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) as no_show_rate
FROM (
	SELECT No_Show,
		CASE
			WHEN lead_time_days = 0 THEN 'Same Day'
			WHEN lead_time_days BETWEEN 1 AND 3 THEN 'Short (1-3 Days)'
			WHEN lead_time_days BETWEEN 4 AND 7 THEN 'Within a week'
			ELSE 'Long Lead (8+ days)'
		END AS lead_time_bucket 
	FROM medicalappointment
) AS subquery
GROUP BY lead_time_bucket
ORDER BY no_show_rate DESC;

-- 4: Age groups

-- child 0-12
-- teen (13-19)
-- young adult (20-39)
-- adult (40-59)

SELECT
	age_group,
	COUNT(*) as total_appointments,
	CAST(SUM(CASE WHEN no_show = '1' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) as no_show_rate
FROM (
	SELECT No_Show,
		CASE
			WHEN Age BETWEEN 0 AND 12 THEN 'Child'
			WHEN Age BETWEEN 13 AND 19 THEN 'Teen'
			WHEN Age BETWEEN 20 AND 39 THEN 'Young Adult'
			WHEN Age BETWEEN 40 AND 59 THEN 'Adult'
			ELSE 'Senior'
		END AS age_group 
    FROM medicalappointment
) AS subquery
GROUP BY age_group
ORDER BY no_show_rate DESC;

-- 5: Do SMS reminders help
SELECT
	CASE WHEN sms_received = 1 THEN 'Received SMS' ELSE 'No SMS' 
    END AS sms_status,
    COUNT(*) as total_appointments,
	CAST(SUM(CASE WHEN no_show = '1' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) as no_show_rate
FROM medicalappointment
GROUP BY CASE WHEN sms_received = 1 THEN 'Received SMS' ELSE 'No SMS' END;


-- 6: Which neighborhoods have the highest risk? 

 SELECT TOP 15
	Neighbourhood, 
    COUNT(*) as total_appointments, 
    CAST(SUM(CASE WHEN no_show = '1' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) as no_show_rate, 
    RANK() OVER (ORDER BY CAST(SUM(CASE WHEN no_show = '1' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) DESC) as risk_rank
	FROM medicalappointment
    GROUP BY Neighbourhood
    HAVING COUNT(*) >= 100
    ORDER BY no_show_rate DESC


-- 7: Patient-level risk scoring

SELECT
	patientid, 
    appointmentid, 
    appointmentday, 
    no_show, 
    COUNT(*) OVER (
		PARTITION BY PatientID
        ORDER BY AppointmentDay
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) as prior_appointments,
	SUM(CASE WHEN no_show = '1' THEN 1 ELSE 0 END) OVER 
		(PARTITION BY PatientID
        ORDER BY AppointmentDay
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) as prior_no_shows
	FROM medicalappointment
    ORDER BY patientid, appointmentday;

CREATE VIEW v_appointment_risk AS
WITH patient_history AS (
    SELECT
        PatientId, AppointmentID, AppointmentDay, Neighbourhood, lead_time_days, sms_received, Scholarship, no_show,
        COUNT(*) OVER (
            PARTITION BY PatientId 
            ORDER BY AppointmentDay 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prior_appointments,
        SUM(CASE WHEN no_show = '1' THEN 1 ELSE 0 END) OVER (
            PARTITION BY PatientId 
            ORDER BY AppointmentDay 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prior_no_shows
    FROM medicalappointment
)
SELECT
    PatientId, AppointmentID, AppointmentDay, Neighbourhood, lead_time_days, prior_appointments, prior_no_shows,
    ROUND(prior_no_shows / NULLIF(prior_appointments, 0), 2) AS prior_no_show_rate,
    CASE
        WHEN prior_appointments = 0 THEN 'New Patient - Monitor'
        WHEN (prior_no_shows / NULLIF(prior_appointments, 0)) >= 0.5 
             OR lead_time_days >= 8 THEN 'High Risk'
        WHEN (prior_no_shows / NULLIF(prior_appointments, 0)) >= 0.2 
             OR lead_time_days BETWEEN 4 AND 7 THEN 'Medium Risk'
        ELSE 'Low Risk'
    END AS risk_tier
FROM patient_history;


SELECT TOP 50 * 
FROM v_appointment_risk
WHERE risk_tier = 'High Risk'
ORDER BY AppointmentDay;
