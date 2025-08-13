USE hospital_db;

-- OBJECTIVE 1: ENCOUNTERS OVERVIEW
select extract(year from START) as year,count(*) from encounters group by year order by year;

SELECT
-- convert the total into percentage 
    year,
    ROUND(100.0 * inpatient_count / total_count, 2) AS inpatient_pct,
    ROUND(100.0 * outpatient_count / total_count, 2) AS outpatient_pct,
    ROUND(100.0 * emergency_count / total_count, 2) AS emergency_pct,
    ROUND(100.0 * ambulatory_count / total_count, 2) AS ambulatory_pct,
    ROUND(100.0 * wellness_count / total_count, 2) AS wellness_pct,
    ROUND(100.0 * ucare_count / total_count, 2) AS urgentcare_pct
FROM (
-- create a table with total of each class
    SELECT
        EXTRACT(YEAR FROM START) AS year,
        COUNT(CASE WHEN ENCOUNTERCLASS = 'inpatient' THEN 1 END) AS inpatient_count,
        COUNT(CASE WHEN ENCOUNTERCLASS = 'outpatient' THEN 1 END) AS outpatient_count,
        COUNT(CASE WHEN ENCOUNTERCLASS = 'emergency' THEN 1 END) AS emergency_count,
        COUNT(CASE WHEN ENCOUNTERCLASS = 'ambulatory' THEN 1 END) AS ambulatory_count,
        COUNT(CASE WHEN ENCOUNTERCLASS = 'wellness' THEN 1 END) AS wellness_count,
        COUNT(CASE WHEN ENCOUNTERCLASS = 'urgentcare' THEN 1 END) AS ucare_count,
        COUNT(*) AS total_count
    FROM encounters
    -- WHERE ENCOUNTERCLASS IN ('inpatient', 'outpatient', 'emergency','wellness','urgentcare','ambulatory')
    GROUP BY EXTRACT(YEAR FROM START)
) AS yearly_counts
ORDER BY year;

-- Categorize encounters as Short Stay (<24h) or Long Stay (>=24h)
WITH encounter_duration AS (
    SELECT 
        EXTRACT(YEAR FROM STR_TO_DATE(START, '%Y-%m-%dT')) AS year,
        CASE 
            WHEN STR_TO_DATE(STOP, '%Y-%m-%dT') - STR_TO_DATE(START, '%Y-%m-%dT') = 1 THEN 'Long_stay'
            WHEN STR_TO_DATE(STOP, '%Y-%m-%dT') - STR_TO_DATE(START, '%Y-%m-%dT') < 1 THEN 'Short_stay'
            ELSE 'Other'
        END AS stay_type
    FROM encounters
)
SELECT 
    year,
    ROUND(100.0 * SUM(CASE WHEN stay_type = 'Long_stay' THEN 1 ELSE 0 END) / COUNT(*), 2) AS long_stay_pct,
    ROUND(100.0 * SUM(CASE WHEN stay_type = 'Short_stay' THEN 1 ELSE 0 END) / COUNT(*), 2) AS short_stay_pct
FROM encounter_duration
WHERE stay_type IN ('Long_stay', 'Short_stay')
GROUP BY year
ORDER BY year;

SELECT 
   -- extract year and quarter from start and end date
    YEAR(STR_TO_DATE(en.START, '%Y-%m-%d')) AS Year,
    QUARTER(STR_TO_DATE(en.START, '%Y-%m-%d')) AS Quarter,
    COUNT(DISTINCT en.PATIENT) AS Distinct_Patients_Admitted
FROM 
    encounters en
GROUP BY 
    YEAR(STR_TO_DATE(en.START, '%Y-%m-%d')), 
    QUARTER(STR_TO_DATE(en.START, '%Y-%m-%d'))
ORDER BY 
    Year, Quarter;
    
SELECT COUNT(*) AS total_readmissions_within_30_days
FROM (
    -- table to keep previous admit date 
    WITH encounter_data AS (
        SELECT 
            PATIENT,
            STR_TO_DATE(START, '%Y-%m-%dT%H:%i:%sZ') AS StartDT, 
            STR_TO_DATE(STOP,  '%Y-%m-%dT%H:%i:%sZ') AS StopDT, 
            LAG(STR_TO_DATE(STOP, '%Y-%m-%dT%H:%i:%sZ')) OVER (
                PARTITION BY PATIENT 
                ORDER BY STR_TO_DATE(START, '%Y-%m-%dT%H:%i:%sZ')
            ) AS PrevStopDT
        FROM encounters
    )
    SELECT *
    FROM encounter_data
    WHERE PrevStopDT IS NOT NULL AND DATEDIFF(StartDT, PrevStopDT) <= 30
) AS readmissions;

-- OBJECTIVE 2: FINANCIAL INSIGHTS

SELECT 
     no_coverage.count AS no_coverage_count,
     total.count AS total_encounters,
     ROUND(100.0 * no_coverage.count / total.count, 2) AS no_coverage_percentage
FROM 
  -- table for no coverage count
    (SELECT COUNT(*) AS count FROM encounters WHERE PAYER_COVERAGE IS NULL OR PAYER_COVERAGE = '') AS no_coverage,
  -- table for total coverage count  
    (SELECT COUNT(*) AS count FROM encounters) AS total;
    
select CODE,count(*) as Procedure_Count,AVG(BASE_COST) as Avg_cost
from procedures group by CODE 
order by Procedure_Count desc limit 10; 

select CODE,count(*) as Procedure_Count,AVG(BASE_COST) as Avg_cost
from procedures group by CODE 
order by Avg_cost desc limit 10;

select en.PAYER,p.NAME,AVG(en.TOTAL_CLAIM_COST) from encounters en
inner join payers p on p.ï»¿Id=en.PAYER group by en.PAYER,p.NAME order by AVG(en.TOTAL_CLAIM_COST) desc;

-- OBJECTIVE 3: PATIENT BEHAVIOR ANALYSIS

WITH age_diagnosis AS (
-- create a table to create age range against a diagnosis 
    SELECT
        CASE 
            WHEN 2025 - YEAR(pat.BIRTHDATE) BETWEEN 0 AND 20 THEN '0-20'
            WHEN 2025 - YEAR(pdata_dictionaryat.BIRTHDATE) BETWEEN 21 AND 40 THEN '21-40'
            WHEN 2025 - YEAR(pat.BIRTHDATE) BETWEEN 41 AND 60 THEN '41-60'
            WHEN 2025 - YEAR(pat.BIRTHDATE) > 60 THEN '61+'
        END AS age_group,
        pro.DESCRIPTION AS diagnosis,
        COUNT(*) AS diagnosis_count
    FROM patients pat
    INNER JOIN procedures pro ON pro.PATIENT = pat.ï»¿Id
    GROUP BY age_group, diagnosis
),
-- DIAGNOSIS PER AGE GROUP 
ranked_diagnoses AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY age_group ORDER BY diagnosis_count DESC) AS rn
    FROM age_diagnosis
)
SELECT 
    age_group,
    diagnosis,
    diagnosis_count
FROM ranked_diagnoses
WHERE rn = 1;

 -- PATIENTS' LAST ENCOUNTER DETAILS
WITH encounter_dates AS (
-- create a table to enlist last encouter date for each patient
    SELECT 
        PATIENT,
        MAX(STR_TO_DATE(START, '%Y-%m-%dT%H:%i:%sZ')) AS LastEncounterDate
    FROM encounters
    GROUP BY PATIENT
) 
SELECT 
    e2.PATIENT,
    ed.LastEncounterDate,
    e2.ï»¿Id,
    p.DESCRIPTION,
    STR_TO_DATE(e2.START, '%Y-%m-%dT%H:%i:%sZ') AS StartDT
FROM encounter_dates ed
JOIN encounters e2 
    ON ed.PATIENT = e2.PATIENT
    AND STR_TO_DATE(e2.START, '%Y-%m-%dT%H:%i:%sZ') = ed.LastEncounterDate
JOIN procedures p 
    ON e2.ï»¿Id = p.ENCOUNTER;
-- PATIENTS ENCOUNTER PROFILE 
WITH encounter_counts AS (
-- create pivot table 
    SELECT 
        PATIENT,
        CASE WHEN ENCOUNTERCLASS = 'Emergency' THEN 1 ELSE 0 END AS EmergencyCount,
        CASE WHEN ENCOUNTERCLASS = 'Inpatient' THEN 1 ELSE 0 END AS InpatientCount,
        CASE WHEN ENCOUNTERCLASS = 'Outpatient' THEN 1 ELSE 0 END AS OutpatientCount,
        CASE WHEN ENCOUNTERCLASS = 'Ambulatory' THEN 1 ELSE 0 END AS AmbulatoryCount,
        CASE WHEN ENCOUNTERCLASS = 'Wellness' THEN 1 ELSE 0 END AS WellnessCount
    FROM encounters
)
SELECT 
    PATIENT,
    SUM(EmergencyCount) AS Emergency,
    SUM(InpatientCount) AS Inpatient,
    SUM(OutpatientCount) AS Outpatient,
    SUM(AmbulatoryCount) AS Ambulatory,
    SUM(WellnessCount) AS Wellness
FROM encounter_counts
GROUP BY PATIENT;
