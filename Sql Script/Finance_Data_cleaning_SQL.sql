-- -----------------------------------------
-- PROJECT: Financial Transactions Data Cleaning
-- -----------------------------------------

-- 1. Create Clean Table (Keep Raw Data Safe)
DROP TABLE IF EXISTS transactions_cleaned;

CREATE TABLE transactions_cleaned AS
SELECT * FROM transactions;



-- 2. Remove Invalid Primary Keys


-- Audit before delete
SELECT COUNT(*) AS invalid_transaction_ids
FROM transactions_cleaned
WHERE transaction_id IS NULL OR transaction_id = '';

-- Delete invalid rows
DELETE FROM transactions_cleaned
WHERE transaction_id IS NULL OR transaction_id = '';



-- 3. Remove Duplicates Safely


WITH cte AS (
    SELECT ctid,
           ROW_NUMBER() OVER(PARTITION BY transaction_id ORDER BY transaction_id) AS rn
    FROM transactions_cleaned
)
DELETE FROM transactions_cleaned
WHERE ctid IN (
    SELECT ctid FROM cte WHERE rn > 1
);



-- 4. Add Primary Key Constraint


ALTER TABLE transactions_cleaned
ADD CONSTRAINT pk_transaction PRIMARY KEY (transaction_id);



-- 5. Add Data Issue Flag Column


ALTER TABLE transactions_cleaned
ADD COLUMN data_issue_flag TEXT;


-- 6. Handle Missing Critical Fields


UPDATE transactions_cleaned
SET data_issue_flag = COALESCE(data_issue_flag, '') || ' Missing Critical Field'
WHERE account_number IS NULL
   OR transaction_date IS NULL
   OR transaction_amount IS NULL;


-- 7. Clean Numeric Fields

-- Remove symbols
UPDATE transactions_cleaned
SET transaction_amount = REGEXP_REPLACE(transaction_amount, '[^0-9.]', '', 'g');

UPDATE transactions_cleaned
SET balance_after_transaction = REGEXP_REPLACE(balance_after_transaction, '[^0-9.]', '', 'g');

-- Convert empty strings to NULL
UPDATE transactions_cleaned
SET transaction_amount = NULL
WHERE transaction_amount = '';

UPDATE transactions_cleaned
SET balance_after_transaction = NULL
WHERE balance_after_transaction = '';

-- Convert to numeric
ALTER TABLE transactions_cleaned
ALTER COLUMN transaction_amount TYPE DECIMAL(12,2)
USING transaction_amount::DECIMAL;

ALTER TABLE transactions_cleaned
ALTER COLUMN balance_after_transaction TYPE DECIMAL(12,2)
USING balance_after_transaction::DECIMAL;



-- 8. Standardize Text Fields


-- Customer Name Cleaning
UPDATE transactions_cleaned
SET customer_name = INITCAP(TRIM(REGEXP_REPLACE(customer_name, '[@#]', '', 'g')));

-- Transaction Type Standardization
UPDATE transactions_cleaned
SET transaction_type = CASE 
    WHEN LOWER(transaction_type) IN ('debit','debi') THEN 'Debit'
    WHEN LOWER(transaction_type) IN ('credit','crdit') THEN 'Credit'
    WHEN LOWER(transaction_type) IN ('transfer','trnsfr') THEN 'Transfer'
    ELSE transaction_type
END;


-- 9. Validate Account Number


UPDATE transactions_cleaned
SET data_issue_flag = COALESCE(data_issue_flag,'') || ' Invalid Account Number'
WHERE account_number !~ '^[0-9]{8}$';

UPDATE transactions_cleaned
SET account_number = NULL
WHERE account_number !~ '^[0-9]{8}$';



-- 10. Date Standardization (Robust Multi-format)

ALTER TABLE transactions_cleaned
ADD COLUMN transaction_date_clean DATE;

UPDATE transactions_cleaned
SET transaction_date_clean =
CASE
    -- ISO format: 2026-03-29
    WHEN transaction_date ~ '^\d{4}-\d{2}-\d{2}$'
        THEN TO_DATE(transaction_date, 'YYYY-MM-DD')

    -- European format: 29/03/2026 or 29-03-2026
    WHEN transaction_date ~ '^\d{2}[-/]\d{2}[-/]\d{4}$'
        THEN TO_DATE(transaction_date, 'DD/MM/YYYY')

    -- US format: 03/29/2026 or 03-29-2026
    WHEN transaction_date ~ '^\d{2}[-/]\d{2}[-/]\d{4}$'
        THEN TO_DATE(transaction_date, 'MM/DD/YYYY')

    -- Text month short: Mar 29, 2026
    WHEN transaction_date ~ '^[A-Za-z]{3} \d{1,2}, \d{4}$'
        THEN TO_DATE(transaction_date, 'Mon DD, YYYY')

    -- Text month full: March 29, 2026
    WHEN transaction_date ~ '^[A-Za-z]+ \d{1,2}, \d{4}$'
        THEN TO_DATE(transaction_date, 'Month DD, YYYY')

    -- Timestamp: 2026-03-29 14:32:00
    WHEN transaction_date ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
        THEN TO_TIMESTAMP(transaction_date, 'YYYY-MM-DD HH24:MI:SS')::DATE

    ELSE NULL
END;

-- Preserve raw column for audit
ALTER TABLE transactions_cleaned
RENAME COLUMN transaction_date TO transaction_date_raw;

-- Flag invalid dates
UPDATE transactions_cleaned
SET data_issue_flag = COALESCE(data_issue_flag, '') || ' Invalid Date'
WHERE transaction_date_clean IS NULL;



-- 11. Currency Standardization


UPDATE transactions_cleaned
SET currency = CASE 
    WHEN UPPER(currency) IN ('USD','$') THEN 'USD'
    WHEN UPPER(currency) IN ('EUR','€') THEN 'EUR'
    WHEN UPPER(currency) IN ('INR','RS','₹') THEN 'INR'
    WHEN UPPER(currency) IN ('GBP','£') THEN 'GBP'
    ELSE 'INVALID'
END;


-- 12. Balance Validation


ALTER TABLE transactions_cleaned
ADD COLUMN balance_issue_flag TEXT;

WITH cte AS (
    SELECT 
        transaction_id,
        account_number,
        transaction_amount,
        balance_after_transaction,
        LAG(balance_after_transaction) OVER (
            PARTITION BY account_number 
            ORDER BY transaction_date_clean
        ) AS prev_balance
    FROM transactions_cleaned
)
UPDATE transactions_cleaned t
SET balance_issue_flag = 'Mismatch'
FROM cte
WHERE t.transaction_id = cte.transaction_id
  AND cte.prev_balance IS NOT NULL
  AND cte.balance_after_transaction <> cte.prev_balance + cte.transaction_amount;



-- 13. Clean Notes Field


UPDATE transactions_cleaned
SET notes = NULL
WHERE LOWER(notes) IN ('test entry','n/a');


-- 14. Final Data Quality Check


SELECT 
    COUNT(*) AS total_rows,
    COUNT(CASE WHEN data_issue_flag IS NOT NULL THEN 1 END) AS flagged_rows,
    COUNT(CASE WHEN balance_issue_flag IS NOT NULL THEN 1 END) AS balance_issues
FROM transactions_cleaned;

-- 15. Final Cleaned_Transaction_Table.
SELECT count(*) FROM transactions_cleaned where transaction_date_clean is null;

Select * from transactions_cleaned