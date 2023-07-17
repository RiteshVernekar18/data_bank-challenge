                          /*A. Customer Nodes Exploration*/
---1.How many unique nodes are there on the Data Bank system? 
       select 
	      count(distinct node_id) as uni_nodes
	    from customer_nodes

---2.What is the number of nodes per region?
     select 
	     r.region_name,
		 count(c.node_id) as nodes
	  from regions r
	  inner join customer_nodes c on r.region_id = c.region_id
	  group by r.region_name

---3.How many customers are allocated to each region?
      select 
	      r.region_id,
		  r.region_name,
		  count(distinct c.customer_id) as customers
	  from regions r 
	  inner join customer_nodes c on r.region_id = c.region_id
	  group by r.region_id,r.region_name

---4.How many days on average are customers reallocated to a different node?
      select 
	      avg(datediff(day,start_date,end_date)) as average
		from customer_nodes
		where end_date != '9999-12-31'

---5.What is the median, 80th and 95th percentile for this same reallocation days metric for each region?
      with find_percentile as (
	             select 
				    c.customer_id,
					c.region_id,
					r.region_name,
					datediff(day,start_date,end_date) as reallocation_days
				 from customer_nodes c
				 inner join regions r on c.region_id = r.region_id
				 where end_date != '9999-12-31'
			)
			  select 
			      distinct region_id,
				  region_name,
				  PERCENTILE_CONT(0.5) within group(order by reallocation_Days) over(partition by region_name) as mediun,
				  PERCENTILE_CONT(0.8) within group(order by reallocation_days) over(partition by region_name) as percentile_80th,
				  PERCENTILE_CONT(0.95) within group(order by reallocation_days) over(partition by region_name) as percentile_95th
			  from find_percentile
			  order by region_name

			                      /*B. Customer Transactions*/
---1.What is the unique count and total amount for each transaction type?
     select 
	     txn_type as type,
		 count(customer_id) as uni_count,
		 sum(txn_amount) as total_amount
	 from customer_trans
	 group by txn_type
	 order by total_amount desc

---2.What is the average total historical deposit counts and amounts for all customers?
      with deposits as (
	           select 
			       customer_id,
				   txn_type,
				   count(*) as counts,
				   sum(txn_amount) as amount
				from customer_trans
				group by customer_id,txn_type
			)
			   select 
			       txn_type,
				   avg(counts) as avg_counts,
				   avg(amount) as avg_amount
			   from deposits
			   where txn_type = ' deposit'
			   group by txn_type

/*3.For each month - how many Data Bank customers make more than 1 deposit and 
either 1 purchase or 1 withdrawal in a single month?*/
with monthly_activities as (   
   select 
       customer_id,
	   datename(month,txn_date) as month_name,
	   count(case when txn_type = ' deposit' then 1 end) as no_of_deposits,
	   count(case when txn_type  = ' withdrawal' then 1 end) as no_of_withdrawals,
	   count(case when txn_type = ' purchase' then 1 end) as no_of_purchases
	from customer_trans
	group by customer_id,datename(month,txn_date)
)
  select 
      month_name,
	  count(distinct customer_id) as active_customers
from monthly_activities
where no_of_deposits > 1 and 
(no_of_purchases = 1 or no_of_withdrawals = 1)
group by month_name
order by active_customers desc

---4.What is the closing balance for each customer at the end of the month?
     with a as (
	      select 
		      customer_id,
			  txn_amount,
			  dateadd(month,datediff(month,0,txn_date),0) as trans_month,
			  sum(case when txn_type = ' deposit' then txn_amount
			        else -1*txn_amount end) as net_amount
		  from customer_trans
		  group by customer_id,dateadd(month,datediff(month,0,txn_date),0),txn_amount
		)
		  select 
		      customer_id,
			  datename(month,a.trans_month) as month_name,
			  net_amount,
			  sum(a.net_amount) over(partition by a.customer_id order by trans_month) as closing_balance
		  from a

                                 /*C. Data Allocation Challenge*/
---1.running customer balance column that includes the impact each transaction
     select 
	     customer_id,
		 txn_date,
		 txn_type,
		 txn_amount,
		 sum(case when txn_type = ' deposit' then txn_amount
		          when txn_type = ' withdrawal' then -txn_amount
				  when txn_type = ' purchase' then -txn_amount
			else 0 end) over (partition by customer_id order by txn_date) as running_balance
	 from customer_trans

---2.customer balance at the end of each month
     select 
	    customer_id,
		datepart(month,txn_date) as months,
		datename(month,txn_date) as month_name,
		sum(case when txn_type = ' deposit' then txn_amount
		         when txn_type = ' withdrawal' then -txn_amount
				 when txn_type = ' purchase' then -txn_amount
			else 0 end) as closing_balance
	from customer_trans
	group by customer_id,datename(month,txn_date),datepart(month,txn_date)

---3.minimum, average and maximum values of the running balance for each customer
     with cte as (
	 select 
	     customer_id,
		 txn_date,
		 txn_type,
		 txn_amount,
		 sum(case when txn_type = ' deposit' then txn_amount
		          when txn_type = ' withdrawal' then -txn_amount
				  when txn_type = ' purchase' then -txn_amount
				  else 0 end) over(partition by customer_id order by txn_date) as running_balance
	from customer_trans
	)
	select 
	    customer_id,
	    min(running_balance) as minimum_running_balance,
		max(running_balance) as maximum_running_balance,
		round(avg(running_balance),0) as average_running_balance
	from cte
	group by customer_id


	/*extra challenge*/

with bonus as (
    select 
	   customer_id,
	   txn_date,
	   sum(txn_amount) as total_amount,
	   datefromparts(year(txn_date),month(txn_date),1) as start_date,
	   datediff(day,datefromparts(year(txn_date),month(txn_Date),1),txn_date) as days_month,
	   cast(sum(txn_amount) as decimal(18,2)) * power((1+0.06/365),datediff(day,'1900-01-01',txn_date)) as daily_interest_rate
	 from customer_trans
	 group by customer_id,txn_Date
	)
	select
	    customer_id,
		datefromparts(year(start_date),month(start_date),1) as trans_month,
		round(sum(daily_interest_rate * days_month),2) as data
	from bonus
	group by customer_id,datefromparts(year(start_date),month(start_date),1)
	order by data desc
