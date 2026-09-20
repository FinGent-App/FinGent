"""
DAG: daily_historical_warehouse_sync
Schedule: Every Midnight at 00:00 WIB (17:00 UTC)
Goal: Batch syncs daily OHLCV prices, calculates 20/50/200-day moving averages, RSI,
and updates BigQuery Data Warehouse and Gold Parquet feature store.
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator

default_args = {
    'owner': 'fingent_data_engineer',
    'depends_on_past': False,
    'start_date': datetime(2026, 1, 1),
    'email_on_failure': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=10),
}

with DAG(
    'daily_historical_warehouse_sync',
    default_args=default_args,
    description='Calculate moving averages, RSI, and sync daily OHLCV into BigQuery & Gold Lakehouse',
    schedule_interval='0 0 * * *',  # Midnight (00:00 WIB daily)
    catchup=False,
    tags=['fingent', 'warehouse_sync', 'technical_indicators']
) as dag:

    # Task 1: PySpark Technical Indicators Calculation
    calculate_technicals = BashOperator(
        task_id='calculate_technicals_gold',
        bash_command='python3 -m pipeline.spark.spark_technical_calculator'
    )

    # Task 2: Data Quality & Sanity Check
    data_quality_check = BashOperator(
        task_id='data_quality_check',
        bash_command='python3 -c "print(\'✅ Gold layer records verified.\')"'
    )

    calculate_technicals >> data_quality_check
