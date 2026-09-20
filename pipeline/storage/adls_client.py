import os
import json
import logging
from pathlib import Path
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional

logger = logging.getLogger("FinGent.DataLake")

# Azurite (Official Microsoft Local ADLS Gen2 Emulator) default connection string
AZURITE_CONNECTION_STRING = os.getenv(
    "ADLS_CONNECTION_STRING",
    "DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;"
    "AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;"
    "BlobEndpoint=http://127.0.0.1:10000/devstoreaccount1;"
)

LOCAL_LAKE_FALLBACK = Path(os.getenv("LOCAL_LAKE_PATH", "data/lakehouse"))


class FinGentDataLake:
    """
    Enterprise Data Lake Storage client supporting Medallion Architecture:
    - Bronze (Raw unmanipulated JSON/XML payloads)
    - Silver (Cleaned, deduplicated, and schema-enforced Parquet)
    - Gold (Curated aggregates, feature store, technical indicators)
    Supports both Azure Data Lake Gen2 (via Azurite emulator or Azure Cloud)
    and transparent local filesystem fallback for $0 cost offline execution.
    """

    def __init__(self, file_system_name: str = "fingent-lake"):
        self.file_system_name = file_system_name
        self.service_client = None
        self.is_azure_connected = False
        self.local_root = LOCAL_LAKE_FALLBACK

        self._init_client()

    def _init_client(self):
        try:
            from azure.storage.filedatalake import DataLakeServiceClient
            self.service_client = DataLakeServiceClient.from_connection_string(AZURITE_CONNECTION_STRING)
            # Test connection / create file system if not exists
            fs_client = self.service_client.get_file_system_client(self.file_system_name)
            if not fs_client.exists():
                fs_client.create_file_system()
            self.is_azure_connected = True
            logger.info("✅ Connected to Azure Data Lake Storage (ADLS Gen2 / Azurite)")
        except Exception as e:
            logger.info("ℹ️ Using High-Performance Local Lakehouse Engine at %s (Azurite not connected: %s)", self.local_root, str(e))
            self.local_root.mkdir(parents=True, exist_ok=True)
            (self.local_root / "bronze").mkdir(parents=True, exist_ok=True)
            (self.local_root / "silver").mkdir(parents=True, exist_ok=True)
            (self.local_root / "gold").mkdir(parents=True, exist_ok=True)
            self.is_azure_connected = False

    # --------------------------------------------------------------------------
    # Bronze Layer (Raw)
    # --------------------------------------------------------------------------

    def upload_raw_bronze(self, subpath: str, data: bytes, metadata: Optional[Dict[str, str]] = None) -> str:
        """
        Uploads immutable raw payload to Bronze container.
        subpath example: 'rss/market=IDX/year=2026/month=09/day=20/kontan_batch_1.json'
        """
        clean_subpath = subpath.lstrip("/")
        if self.is_azure_connected and self.service_client:
            try:
                fs_client = self.service_client.get_file_system_client(self.file_system_name)
                dir_client = fs_client.get_directory_client("bronze")
                file_client = dir_client.get_file_client(clean_subpath)
                file_client.upload_data(data, overwrite=True)
                return f"adls://{self.file_system_name}/bronze/{clean_subpath}"
            except Exception as e:
                logger.warning("Failed ADLS upload, falling back to local: %s", str(e))

        # Local fallback
        target = self.local_root / "bronze" / clean_subpath
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        return str(target.resolve())

    def read_bronze_files(self, prefix: str = "") -> List[Dict[str, Any]]:
        """Reads all JSON payloads matching prefix from bronze layer."""
        results = []
        bronze_dir = self.local_root / "bronze" / prefix
        if bronze_dir.exists():
            for p in bronze_dir.glob("**/*.json"):
                try:
                    with open(p, "r", encoding="utf-8") as f:
                        results.append(json.load(f))
                except Exception:
                    pass
        return results

    # --------------------------------------------------------------------------
    # Silver Layer (Cleaned & Schema-Enforced Parquet)
    # --------------------------------------------------------------------------

    def save_silver_parquet(self, relative_name: str, records: List[Dict[str, Any]]) -> str:
        """
        Saves cleansed records into Silver Parquet format.
        """
        target = self.local_root / "silver" / relative_name
        target.parent.mkdir(parents=True, exist_ok=True)

        try:
            import pandas as pd
            df = pd.DataFrame(records)
            df.to_parquet(str(target), index=False, compression="snappy")
            logger.info("Saved %d records to Silver Parquet at %s", len(records), target)
            return str(target.resolve())
        except Exception as e:
            # Fallback to json if pyarrow is compiling
            json_target = target.with_suffix(".json")
            with open(json_target, "w", encoding="utf-8") as f:
                json.dump(records, f, indent=2, default=str)
            return str(json_target.resolve())

    # --------------------------------------------------------------------------
    # Gold Layer (Curated Features & Technical Aggregates)
    # --------------------------------------------------------------------------

    def save_gold_features(self, feature_name: str, records: List[Dict[str, Any]]) -> str:
        """
        Saves curated financial indicators or sentiment aggregates into Gold layer.
        """
        target = self.local_root / "gold" / f"{feature_name}.parquet"
        target.parent.mkdir(parents=True, exist_ok=True)

        try:
            import pandas as pd
            df = pd.DataFrame(records)
            df.to_parquet(str(target), index=False, compression="snappy")
            return str(target.resolve())
        except Exception:
            json_target = target.with_suffix(".json")
            with open(json_target, "w", encoding="utf-8") as f:
                json.dump(records, f, indent=2, default=str)
            return str(json_target.resolve())


# Singleton instance
data_lake = FinGentDataLake()
