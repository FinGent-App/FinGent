"""
DAG: us_market_preindex_pipeline
Schedule: Every Monday - Friday at 14:00 WIB (07:00 UTC)
Goal: Scrapes US financial portals (Nasdaq, Investing.com, CNBC) during Indonesian daytime,
cleanses via PySpark, and pre-indexes into Milvus Vector DB before Wall Street opens at 20:30 WIB.
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
    'retry_delay': timedelta(minutes=5),
}

with DAG(
    'us_market_preindex_pipeline',
    default_args=default_args,
    description='Pre-index US Wall Street news into Lakehouse & Milvus RAG before trading hours',
    schedule_interval='0 14 * * 1-5',  # 14:00 WIB (Monday - Friday)
    catchup=False,
    tags=['fingent', 'market_us', 'rag_preindex']
) as dag:

    # Task 1: Extract US RSS feeds into Bronze Lake
    extract_us_bronze = BashOperator(
        task_id='extract_us_rss_bronze',
        bash_command='export PYTHONPATH=/home/airflow/gcs/dags:$PWD:$PYTHONPATH; cd /home/airflow/gcs/dags 2>/dev/null || true; python3 -m pipeline.scripts.extract_rss_bronze --market US'
    )

    # Task 2: Distributed PySpark Data Cleansing & Entity Extraction into Silver Parquet
    pyspark_cleanse_silver = BashOperator(
        task_id='pyspark_cleanse_silver',
        bash_command='export PYTHONPATH=/home/airflow/gcs/dags:$PWD:$PYTHONPATH; cd /home/airflow/gcs/dags 2>/dev/null || true; python3 -m pipeline.spark.spark_news_cleanser --market US'
    )

    # Task 3: Vectorize & Upsert to Milvus Vector DB
    sync_milvus_rag = BashOperator(
        task_id='sync_milvus_rag',
        bash_command='export PYTHONPATH=/home/airflow/gcs/dags:$PWD:$PYTHONPATH; cd /home/airflow/gcs/dags 2>/dev/null || true; python3 -m pipeline.scripts.sync_milvus_silver --market US'
    )

    extract_us_bronze >> pyspark_cleanse_silver >> sync_milvus_rag
