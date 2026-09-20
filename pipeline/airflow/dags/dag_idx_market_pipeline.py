"""
DAG: idx_market_preindex_pipeline
Schedule: Every Monday - Friday at 20:00 WIB (13:00 UTC)
Goal: Scrapes Indonesian financial portals (Kontan, Detik, Liputan6, Tempo) and IDX disclosures
at night, cleanses via PySpark, and pre-indexes into Milvus Vector DB before Jakarta trading opens at 09:00 WIB.
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
    'idx_market_preindex_pipeline',
    default_args=default_args,
    description='Pre-index IDX Jakarta market news into Lakehouse & Milvus RAG before trading hours',
    schedule_interval='0 20 * * 1-5',  # 20:00 WIB (Monday - Friday)
    catchup=False,
    tags=['fingent', 'market_idx', 'rag_preindex']
) as dag:

    # Task 1: Extract IDX RSS feeds into Bronze Lake
    extract_idx_bronze = BashOperator(
        task_id='extract_idx_rss_bronze',
        bash_command='python3 -m pipeline.scripts.extract_rss_bronze --market IDX'
    )

    # Task 2: Distributed PySpark Data Cleansing & Entity Extraction into Silver Parquet
    pyspark_cleanse_silver_idx = BashOperator(
        task_id='pyspark_cleanse_silver_idx',
        bash_command='python3 -m pipeline.spark.spark_news_cleanser --market IDX'
    )

    # Task 3: Vectorize & Upsert to Milvus Vector DB
    sync_milvus_rag_idx = BashOperator(
        task_id='sync_milvus_rag_idx',
        bash_command='python3 -m pipeline.scripts.sync_milvus_silver --market IDX'
    )

    extract_idx_bronze >> pyspark_cleanse_silver_idx >> sync_milvus_rag_idx
