select * from transactions 
select * from users
select * from banking_cards where client_id = 260 order by client_id
select * from codes
--Q1:What is the total number of card transactions made by Xóm Bank in 2023?
select COUNT(*) as total_tramsaction
from transactions
where date>= '2023-01-01' and date <'2024-01-01'

--Q2: Which are the top 5 merchant cities by transaction volume, and what is the total transaction amount in each city?
select top 5
	merchant_city,
	COUNT(*) as total_transaction,
	SUM(amount) as total_amount
from transactions
group by merchant_city
order by total_transaction desc;

--Q3: What is the customer distribution across five credit score categories: 
--Poor (below 580), Fair (580–669), Good (670–739), Very Good (740–799), and Excellent (800 or above)?
select 
	(case 
	when credit_score >=800 then '5. Excellent (800+)'
	when credit_score <=799 and credit_score>=740  then '4. Very good (740-799)'
	when credit_score <=739 and credit_score>=670 then '3. Good (670-739)'
	when credit_score <=699 and credit_score >=580 then '2. Fair (580-669)'
	else '1. Poor (<580)' end) as customer_distribution,
	COUNT(*) as total_customer,
	cast (COUNT(*)*100.0/ SUM(COUNT(*)) over () as decimal(5,2)) as pct_total
from users
group by 
case 
	when credit_score >=800 then '5. Excellent (800+)'
	when credit_score <=799 and credit_score>=740  then '4. Very good (740-799)'
	when credit_score <=739 and credit_score>=670 then '3. Good (670-739)'
	when credit_score <=699 and credit_score >=580 then '2. Fair (580-669)'
	else '1. Poor (<580)' end
order by customer_distribution

--Q4: What is the number of cards by brand (Visa, Mastercard, Amex, and Discover), 
--and what percentage does each brand represent of the total card portfolio?
select
	card_brand,
	COUNT(*) as total_card,
	COUNT(*)*100.0 / SUM(COUNT(*)) over () as pct
from banking_cards
group by card_brand

--Q5: What is the percentage of failed transactions out of total transactions, and what is the breakdown by failure type?
select
	errors,
	count(*) as transaction_count,
	cast(COUNT(*)*100.0 / SUM(COUNT(*)) over () as decimal(5,2)) as pct_errors
from transactions
group by errors
order by pct_errors desc

--Q6: Who are the top 10 customers with the highest spending in any given month, 
--based on their total spending within that month? What are their gender and annual income profiles?
WITH monthly_spend AS (
  SELECT
    t.client_id,
    DATEFROMPARTS(YEAR(t.date), MONTH(t.date), 1) AS month_start,
    SUM(t.amount) AS spend
  FROM transactions AS t
  WHERE t.amount > 0
  GROUP BY t.client_id, DATEFROMPARTS(YEAR(t.date), MONTH(t.date), 1)
)
SELECT TOP (10)
  m.client_id,
  FORMAT(m.month_start, 'yyyy-MM') AS year_month,
  CAST(m.spend AS DECIMAL(14, 2)) AS spend,
  u.gender,
  CAST(u.yearly_income AS DECIMAL(14, 2)) AS yearly_income
FROM monthly_spend AS m
JOIN users AS u
  ON u.id = m.client_id
ORDER BY m.spend DESC, m.client_id;


--Q7: Which are the top 10 merchant categories by total customer spending, based only on successful transactions and excluding refunds?
select top 10
	c.mcc_id,
	max (c.description) as mcc_name,
	COUNT(*) as transaction_count,
	SUM(t.amount) as total_spend,
	COUNT(*) as total_customer
from transactions t 
join codes c on t.mcc = c.mcc_id
where t.amount>0 and errors = 'Success'
group by c.mcc_id
order by total_spend desc;

--Q8: What is the credit card utilization ratio for each card over the last 30 days, 
--calculated as total spending divided by total credit limit? Only credit cards are included, excluding debit and prepaid cards.
SELECT 
    t.card_id,
    c.client_id,
    c.credit_limit,
    ROUND(SUM(t.amount), 2) AS spend_last_30_days,
    ROUND(SUM(t.amount) * 1.0 / NULLIF(c.credit_limit, 0), 4) AS utilization_ratio,
    CONCAT(ROUND((SUM(t.amount) * 100.0) / NULLIF(c.credit_limit, 0), 2), '%') AS utilization_pct
FROM dbo.transactions t
INNER JOIN dbo.banking_cards c 
    ON t.card_id = c.id
WHERE c.card_type = 'Credit'
  AND t.errors = 'Success'
  AND t.amount > 0
  AND t.date >= DATEADD(DAY, -30, (SELECT MAX(date) FROM dbo.transactions))
GROUP BY 
    t.card_id,
    c.client_id,
    c.credit_limit
ORDER BY 
    utilization_ratio DESC;

--Q9: Which cards have been open for more than two years but have never had any transactions?
select 
	c.id,
	c.acct_open_date,
	c.card_brand,
	c.card_type
from banking_cards c
left join transactions t on t.card_id = c.id
where t.id is null and
c.acct_open_date <= dateadd(year, -2, (select max(date) from transactions));

--Q11: What is each customer's monthly spending and cumulative spending up to each month over the most recent 24 months?
with consumtion as 
(
select 
	client_id,
	DATEFROMPARTS(YEAR(date), MONTH(date), 1) AS month_start,
	SUM(amount) as monthly_expenditure
from transactions
where amount>0
and errors = 'Success'
and date >= DATEADD(MONTH, -24, (select MAX(date) from transactions))
group by client_id, DATEFROMPARTS(YEAR(date), MONTH(date), 1)
)
select
	client_id,
	month_start,
	round(monthly_expenditure, 2) as monthly_expenditure,
	round(SUM(monthly_expenditure) over (partition by client_id order by month_start asc), 2) as chitieutichluy
from consumtion

--Q13: Which transactions have unusually high amounts compared with other transactions within the same merchant category? 
--Flag transactions exceeding the 95th percentile (P95).
create view vw_outlier as 
with outlier as
(select 
	id,
	client_id,
	date,
	mcc,
	round(amount, 2) as amount,
	round((PERCENTILE_CONT(0.5) within group (order by amount) over (partition by mcc)),2) as med,
	round((PERCENTILE_CONT(0.95) within group (order by amount) over (partition by mcc)),2) as p95
from transactions
where amount>0 and errors = 'Success'
)
select 
	id,
	description,
	client_id,
	date,
	mcc,
	amount,
	med, 
	p95,
	round((amount*1.0/med),2) as med_times,
	case when amount>p95 then 'flag' else '0' end as flag
from outlier o 
join codes c on o.mcc = c.mcc_id


--Q14: Do customers with higher credit scores spend more? 
--Divide customers into five groups based on credit score, and calculate the average monthly spending and average annual income for each group.
with amount as
(
	select 
		client_id,
		--datefromparts(YEAR(date), month(date), 1) as date,
		--format(date, 'yyyy-MM') as month_date,
		round((SUM(amount)),2) as total_amount,
		round((SUM(amount)/COUNT(distinct format(date, 'yyyy-MM'))),2) as avg_month
	from transactions
	where amount>0 and errors = 'Success'
	group by client_id
),
ranking as (
select 
	u.id,
	--month_date,
	isnull(total_amount,0) as total_amount,
	isnull(avg_month,0) as avg_month,
	u.yearly_income,
	u.credit_score,
	NTILE(5) over (order by u.credit_score desc) as ranking
from users u 
left join amount a on a.client_id = u.id
)
select 
	ranking,
	COUNT(id) as customer,
	MIN(credit_score) as min_score,
	MAX(credit_score) as max_score,
	round(isnull((avg(avg_month)),0),2) as avg_month,
	isnull((avg(yearly_income)),0) as avg_income
from ranking
group by ranking;

--Q15: Which are the top 10 states and top 10 merchant categories by spending? 
--Create a state-by-category spending heatmap, where each matrix cell represents total spending..
create or alter view vw_heatmap as
WITH clean_trans AS (
    SELECT 
        t.merchant_state,
        c.description AS category_name,
        t.amount
    FROM dbo.transactions t
    INNER JOIN dbo.codes c 
        ON t.mcc = c.mcc_id
    WHERE t.errors = 'Success'
      AND t.amount > 0
      AND t.merchant_state IS NOT NULL 
      AND t.merchant_state <> 'ONLINE'
),
top_states AS (
    SELECT  top 10
        merchant_state,
        SUM(amount) AS state_spend
    FROM clean_trans
    GROUP BY merchant_state
	ORDER BY state_spend DESC
),
top_categories AS (
    SELECT top 10
		category_name,
        SUM(amount) AS cat_spend
    FROM clean_trans
    GROUP BY category_name
	ORDER BY cat_spend DESC

)
-- Bước 4: Lọc giao dịch thuộc giao điểm của Top 10 Bang x Top 10 Ngành
SELECT 
    ct.merchant_state,
    ct.category_name,
    CAST(SUM(ct.amount) AS DECIMAL(14, 2)) AS total_amount
FROM clean_trans ct
INNER JOIN top_states s 
    ON ct.merchant_state = s.merchant_state
INNER JOIN top_categories c 
    ON ct.category_name = c.category_name
GROUP BY 
    ct.merchant_state,
    ct.category_name;


--Q12: Which customers have gaps of more than 30 days between consecutive transactions, potentially indicating churn? 
--For each customer, calculate the longest gap between consecutive transactions.
CREATE OR ALTER VIEW dbo.vw_churn AS
WITH customer_dates AS (
    -- Mỗi khách chỉ giữ một dòng cho mỗi ngày có giao dịch
    SELECT DISTINCT
        client_id,
        CAST([date] AS DATE) AS trans_date
    FROM dbo.transactions
    WHERE errors = 'Success'
        AND amount > 0
),
trans_gaps AS (
    SELECT
        client_id,
        trans_date,
        LAG(trans_date) OVER (
            PARTITION BY client_id
            ORDER BY trans_date
        ) AS prev_trans_date,
        ROW_NUMBER() OVER (
            PARTITION BY client_id
            ORDER BY trans_date DESC
        ) AS rn
    FROM customer_dates
),
customer_summary AS (
    SELECT
        client_id,
        MAX(trans_date) AS latest_trans,
        MAX(
            CASE WHEN rn = 1
                THEN prev_trans_date
            END
        ) AS prev_trans,
        MAX(
            CASE WHEN rn = 1
                THEN DATEDIFF(DAY, prev_trans_date, trans_date)
            END
        ) AS latest_gap_days,
        MAX(
            DATEDIFF(DAY, prev_trans_date, trans_date)
        ) AS max_gap_days
    FROM trans_gaps
    GROUP BY client_id
),
data_cutoff AS (
    SELECT CAST(MAX([date]) AS DATE) AS data_as_of
    FROM dbo.transactions
)
SELECT
    s.client_id,
    s.latest_trans,
    s.prev_trans,
    s.latest_gap_days,
    s.max_gap_days,
    d.data_as_of,
    DATEDIFF(
        DAY, s.latest_trans, d.data_as_of
    ) AS days_since_last_txn
FROM customer_summary AS s
CROSS JOIN data_cutoff AS d;

--Q10: Which customers have conducted transactions across three or more different states on the same day? 
--For each case, identify the customer ID, transaction date, number of states, number of transactions, and total transaction amount.
CREATE OR ALTER VIEW dbo.vw_multistate AS
SELECT
    t.client_id,
    CAST(t.[date] AS DATE) AS transaction_date,
    COUNT(DISTINCT t.merchant_state) AS distinct_states,
    COUNT(*) AS total_transactions,
    CAST(SUM(t.amount) AS DECIMAL(14, 2)) AS total_amount
FROM dbo.transactions AS t
WHERE t.merchant_state IS NOT NULL
    AND t.merchant_state <> 'ONLINE'
    AND t.errors = 'Success'
    AND t.amount > 0
GROUP BY
    t.client_id,
    CAST(t.[date] AS DATE)
HAVING COUNT(DISTINCT t.merchant_state) >= 3;


--real dormant card
with client_list as (
select distinct 
	client_id
from transactions
),
card_list as (
select 
	l.client_id,
	c.id as card_id,
	c.card_type,
	c.credit_limit
from client_list l 
join banking_cards c on l.client_id = c.client_id
where (year(cast(getdate() as date)) - year(c.acct_open_date))>2
),
dormant_real as
(
select
	cl.client_id,
	cl.card_id,
	max(cl.card_type) as card_type,
	max(credit_limit) as credit_limit,
	COUNT(t.id)as total_trans
from transactions t 
right join card_list cl  on t.card_id = cl.card_id
group by cl.client_id, cl.card_id
having COUNT(t.id) = 0
)
select 
	card_type,
	SUM(credit_limit)
from dormant_real
group by card_type






