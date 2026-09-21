import os
import io
import json
import logging
from pathlib import Path
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional

logger = logging.getLogger("FinGent.DataLake")

# Google Cloud Storage Data Lakehouse Bucket (Primary Production Lake)
GCS_LAKEHOUSE_BUCKET = os.getenv("GCS_LAKEHOUSE_BUCKET", "fingent-lakehouse-508006")

# Azure Data Lake Gen2 (Azurite Emulator / Multi-Cloud fallback)
AZURITE_CONNECTION_STRING = os.getenv(
    "ADLS_CONNECTION_STRING",
    "DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;"
    "AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;"
    "BlobEndpoint=http://127.0.0.1:10000/devstoreaccount1;"
)

LOCAL_LAKE_FALLBACK = Path(os.getenv("LOCAL_LAKE_PATH", "data/lakehouse"))


class FinGentDataLake:
    """
    Enterprise Data Lakehouse Client supporting Medallion Architecture:
    - Bronze (Raw unmanipulated JSON/XML payloads)
    - Silver (Cleaned, deduplicated, and schema-enforced Parquet)
    - Gold (Curated aggregates, feature store, quantitative indicators)

    Multi-Cloud Storage Providers:
    1. Google Cloud Storage (GCS Bucket: fingent-lakehouse-508006) - Primary Cloud Lake
    2. Azure Data Lake Storage Gen2 (ADLS Gen2 / Azurite) - Multi-Cloud
    3. Local Filesystem (data/lakehouse) - $0 Offline Dev Fallback
    """

    def __init__(self, file_system_name: str = "fingent-lake"):
        self.file_system_name = file_system_name
        self.local_root = LOCAL_LAKE_FALLBACK

        # GCS State
        self.gcs_client = None
        self.gcs_bucket = None
        self.is_gcs_connected = False

        # Azure State
        self.azure_service_client = None
        self.is_azure_connected = False

        self._init_clients()

    def _init_clients(self):
        # 1. Initialize Google Cloud Storage (Production Data Lake)
        try:
            from google.cloud import storage
            self.gcs_client = storage.Client()
            self.gcs_bucket = self.gcs_client.bucket(GCS_LAKEHOUSE_BUCKET)
            self.is_gcs_connected = True
            logger.info("✅ Connected to Google Cloud Lakehouse: gs://%s", GCS_LAKEHOUSE_BUCKET)
        except Exception as e:
            logger.info("ℹ️ GCS Lakehouse direct access deferred (%s)", str(e))
            self.is_gcs_connected = False

        # 2. Initialize Azure ADLS Gen2 (if connection string configured)
        if os.getenv("ADLS_CONNECTION_STRING"):
            try:
                from azure.storage.filedatalake import DataLakeServiceClient
                self.azure_service_client = DataLakeServiceClient.from_connection_string(AZURITE_CONNECTION_STRING)
                fs_client = self.azure_service_client.get_file_system_client(self.file_system_name)
                if not fs_client.exists():
                    fs_client.create_file_system()
                self.is_azure_connected = True
                logger.info("✅ Connected to Azure Data Lake Storage (ADLS Gen2)")
            except Exception as e:
                logger.info("ℹ️ Azure ADLS Gen2 not connected: %s", str(e))
                self.is_azure_connected = False

        # 3. Always prepare local filesystem as cache / fallback
        self.local_root.mkdir(parents=True, exist_ok=True)
        (self.local_root / "bronze").mkdir(parents=True, exist_ok=True)
        (self.local_root / "silver").mkdir(parents=True, exist_ok=True)
        (self.local_root / "gold").mkdir(parents=True, exist_ok=True)

    # --------------------------------------------------------------------------
    # Bronze Layer (Raw)
    # --------------------------------------------------------------------------

    def upload_raw_bronze(self, subpath: str, data: bytes, metadata: Optional[Dict[str, str]] = None) -> str:
        """
        Uploads immutable raw payload to Bronze container/bucket.
        subpath example: 'news/year=2026/month=09/day=21/kontan_1789965058.json'
        """
        clean_subpath = subpath.lstrip("/")
        saved_uri = ""

        # 1. Upload to GCS Bucket (fingent-lakehouse-508006)
        if self.is_gcs_connected and self.gcs_bucket:
            try:
                blob_path = f"bronze/{clean_subpath}"
                blob = self.gcs_bucket.blob(blob_path)
                blob.upload_from_string(data, content_type="application/json")
                saved_uri = f"gs://{GCS_LAKEHOUSE_BUCKET}/{blob_path}"
                logger.info("Uploaded Bronze payload to %s", saved_uri)
            except Exception as e:
                logger.warning("Failed GCS Bronze upload: %s", str(e))

        # 2. Upload to Azure ADLS Gen2 (if connected)
        if self.is_azure_connected and self.azure_service_client:
            try:
                fs_client = self.azure_service_client.get_file_system_client(self.file_system_name)
                dir_client = fs_client.get_directory_client("bronze")
                file_client = dir_client.get_file_client(clean_subpath)
                file_client.upload_data(data, overwrite=True)
                if not saved_uri:
                    saved_uri = f"adls://{self.file_system_name}/bronze/{clean_subpath}"
            except Exception as e:
                logger.warning("Failed ADLS Bronze upload: %s", str(e))

        # 3. Always write to local storage (cache & local worker access)
        target = self.local_root / "bronze" / clean_subpath
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)

        return saved_uri if saved_uri else str(target.resolve())

    def read_bronze_files(self, prefix: str = "") -> List[Dict[str, Any]]:
        """Reads all JSON payloads matching prefix from Bronze layer (GCS & local)."""
        results = []
        clean_prefix = prefix.strip("/")

        # Try reading from GCS
        if self.is_gcs_connected and self.gcs_bucket:
            try:
                gcs_prefix = f"bronze/{clean_prefix}".rstrip("/") + "/" if clean_prefix else "bronze/"
                blobs = self.gcs_client.list_blobs(self.gcs_bucket, prefix=gcs_prefix)
                for b in blobs:
                    if b.name.endswith(".json"):
                        try:
                            content = b.download_as_text()
                            parsed = json.loads(content)
                            if isinstance(parsed, list):
                                results.extend(parsed)
                            elif isinstance(parsed, dict):
                                results.append(parsed)
                        except Exception as parse_err:
                            logger.warning("Failed parsing GCS blob %s: %s", b.name, str(parse_err))
                if results:
                    logger.info("Loaded %d raw records from GCS Bronze (gs://%s/%s)", len(results), GCS_LAKEHOUSE_BUCKET, gcs_prefix)
                    return results
            except Exception as e:
                logger.warning("Failed reading GCS Bronze: %s", str(e))

        # Fallback to local
        bronze_dir = self.local_root / "bronze" / clean_prefix
        if bronze_dir.exists():
            for p in bronze_dir.glob("**/*.json"):
                try:
                    with open(p, "r", encoding="utf-8") as f:
                        data = json.load(f)
                        if isinstance(data, list):
                            results.extend(data)
                        elif isinstance(data, dict):
                            results.append(data)
                except Exception:
                    pass
        return results

    # --------------------------------------------------------------------------
    # Silver Layer (Cleaned & Schema-Enforced Parquet)
    # --------------------------------------------------------------------------

    def save_silver_parquet(self, relative_name: str, records: List[Dict[str, Any]]) -> str:
        """
        Saves cleansed records into Silver Parquet format (both local and GCS fingent-lakehouse-508006).
        """
        clean_name = relative_name.lstrip("/")
        target = self.local_root / "silver" / clean_name
        target.parent.mkdir(parents=True, exist_ok=True)
        saved_uri = ""

        # Write Parquet locally first
        try:
            import pandas as pd
            df = pd.DataFrame(records)
            df.to_parquet(str(target), index=False, compression="snappy")
            logger.info("Saved %d records to local Silver Parquet at %s", len(records), target)
        except Exception:
            json_target = target.with_suffix(".json")
            with open(json_target, "w", encoding="utf-8") as f:
                json.dump(records, f, indent=2, default=str)
            target = json_target

        # Upload to GCS Bucket fingent-lakehouse-508006
        if self.is_gcs_connected and self.gcs_bucket:
            try:
                gcs_blob_name = f"silver/{clean_name}"
                blob = self.gcs_bucket.blob(gcs_blob_name)
                blob.upload_from_filename(str(target))
                saved_uri = f"gs://{GCS_LAKEHOUSE_BUCKET}/{gcs_blob_name}"
                logger.info("✅ Uploaded Silver Parquet to %s", saved_uri)
            except Exception as e:
                logger.warning("Failed GCS Silver upload: %s", str(e))

        return saved_uri if saved_uri else str(target.resolve())

    def read_silver_records(self, prefix: str = "") -> List[Dict[str, Any]]:
        """Reads cleansed records from Silver Parquet files (GCS & local)."""
        clean_prefix = prefix.strip("/")
        results = []

        # Try GCS Silver
        if self.is_gcs_connected and self.gcs_bucket:
            try:
                import pandas as pd
                gcs_prefix = f"silver/{clean_prefix}".rstrip("/") + "/" if clean_prefix else "silver/"
                blobs = self.gcs_client.list_blobs(self.gcs_bucket, prefix=gcs_prefix)
                for b in blobs:
                    if b.name.endswith(".parquet"):
                        try:
                            buf = io.BytesIO(b.download_as_bytes())
                            df = pd.read_parquet(buf)
                            results.extend(df.to_dict(orient="records"))
                        except Exception as e:
                            logger.warning("Failed reading GCS parquet %s: %s", b.name, str(e))
                if results:
                    logger.info("Loaded %d records from GCS Silver (gs://%s/%s)", len(results), GCS_LAKEHOUSE_BUCKET, gcs_prefix)
                    return results
            except Exception as e:
                logger.warning("Failed querying GCS Silver: %s", str(e))

        # Local fallback
        silver_dir = self.local_root / "silver" / clean_prefix
        if silver_dir.exists():
            import pandas as pd
            for pf in silver_dir.glob("**/*"):
                if pf.suffix == ".parquet":
                    try:
                        df = pd.read_parquet(pf)
                        results.extend(df.to_dict(orient="records"))
                    except Exception:
                        pass
                elif pf.suffix == ".json":
                    try:
                        with open(pf, "r", encoding="utf-8") as f:
                            data = json.load(f)
                            if isinstance(data, list):
                                results.extend(data)
                    except Exception:
                        pass
        return results

    # --------------------------------------------------------------------------
    # Gold Layer (Curated Features & Technical Aggregates)
    # --------------------------------------------------------------------------

    def save_gold_features(self, feature_name: str, records: List[Dict[str, Any]]) -> str:
        """
        Saves curated financial indicators or sentiment aggregates into Gold layer (both local and GCS).
        """
        clean_name = feature_name.strip("/").replace(".parquet", "")
        target = self.local_root / "gold" / f"{clean_name}.parquet"
        target.parent.mkdir(parents=True, exist_ok=True)
        saved_uri = ""

        # Write Parquet locally first
        try:
            import pandas as pd
            df = pd.DataFrame(records)
            df.to_parquet(str(target), index=False, compression="snappy")
        except Exception:
            json_target = target.with_suffix(".json")
            with open(json_target, "w", encoding="utf-8") as f:
                json.dump(records, f, indent=2, default=str)
            target = json_target

        # Upload to GCS Bucket fingent-lakehouse-508006
        if self.is_gcs_connected and self.gcs_bucket:
            try:
                gcs_blob_name = f"gold/{clean_name}.parquet"
                blob = self.gcs_bucket.blob(gcs_blob_name)
                blob.upload_from_filename(str(target))
                saved_uri = f"gs://{GCS_LAKEHOUSE_BUCKET}/{gcs_blob_name}"
                logger.info("✅ Uploaded Gold Features to %s", saved_uri)
            except Exception as e:
                logger.warning("Failed GCS Gold upload: %s", str(e))

        return saved_uri if saved_uri else str(target.resolve())

    def read_gold_records(self, feature_name: str = "technical_indicators_latest") -> List[Dict[str, Any]]:
        """Reads curated Gold layer features (GCS & local)."""
        clean_name = feature_name.strip("/").replace(".parquet", "")

        # Try GCS Gold
        if self.is_gcs_connected and self.gcs_bucket:
            try:
                import pandas as pd
                gcs_blob_name = f"gold/{clean_name}.parquet"
                blob = self.gcs_bucket.blob(gcs_blob_name)
                if blob.exists():
                    buf = io.BytesIO(blob.download_as_bytes())
                    df = pd.read_parquet(buf)
                    return df.to_dict(orient="records")
            except Exception as e:
                logger.warning("Failed reading GCS Gold %s: %s", clean_name, str(e))

        # Local fallback
        target = self.local_root / "gold" / f"{clean_name}.parquet"
        if target.exists():
            import pandas as pd
            try:
                df = pd.read_parquet(target)
                return df.to_dict(orient="records")
            except Exception:
                pass

        return []


# Singleton instance
data_lake = FinGentDataLake()
