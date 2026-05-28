from celery import Celery
import os
from docling.document_converter import DocumentConverter
from docling.datamodel.base_models import ConversionStatus
import logging
from typing import List, Dict, Union
import tempfile

logger = logging.getLogger(__name__)

celery_app = Celery(
    "pdf_converter",
    broker=os.getenv("CELERY_BROKER_URL", "redis://redis:6379/0"),
    backend=os.getenv("CELERY_RESULT_BACKEND", "redis://redis:6379/0"),
)

celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,
    task_track_started=True,
    task_time_limit=3600,  # 1 hour max runtime
    task_soft_time_limit=3300,  # 55 minutes soft limit
)

# Check if running in OpenShift mode
OPENSHIFT_MODE = os.getenv("OPENSHIFT_MODE", "false").lower() == "true"

# Initialize storage manager for OpenShift mode
storage_manager = None
if OPENSHIFT_MODE:
    from shared.storage import StorageManager
    from shared.otel import OpenTelemetryInstrumentation, OpenTelemetryConfig

    telemetry = OpenTelemetryInstrumentation()
    config = OpenTelemetryConfig(
        service_name="pdf-celery-worker",
        otlp_endpoint=os.getenv("OTLP_ENDPOINT", "http://jaeger:4317"),
        enable_redis=False,
        enable_requests=False,
    )
    telemetry.initialize(config)
    storage_manager = StorageManager(telemetry=telemetry)
    logger.info("Running in OpenShift mode with MinIO storage")


@celery_app.task(bind=True, max_retries=3)
def convert_pdf_task(self, arg1: Union[str, List[str]], arg2: List[str] = None) -> List[Dict[str, str]]:
    """
    Convert PDF files to markdown.

    Args:
        arg1: Either job_id (str) for OpenShift mode, or file_paths (List[str]) for local mode
        arg2: file_ids (List[str]) for OpenShift mode, None for local mode
    """
    temp_files = []
    try:
        converter = DocumentConverter()
        results = []

        if OPENSHIFT_MODE and arg2 is not None:
            # OpenShift mode: arg1 is job_id, arg2 is file_ids
            job_id = arg1
            file_ids = arg2
            file_paths = []

            # Download files from MinIO to temp directory
            for file_id in file_ids:
                filename = f"{file_id}.pdf"
                content = storage_manager.get_file(
                    user_id="pdf-service",
                    job_id=job_id,
                    filename=filename
                )

                if content is None:
                    logger.error(f"File {filename} not found in MinIO")
                    results.append({
                        "filename": filename,
                        "status": "failed",
                        "error": "File not found in storage"
                    })
                    continue

                # Write to temporary file
                temp_file = tempfile.NamedTemporaryFile(mode='wb', suffix='.pdf', delete=False)
                temp_file.write(content)
                temp_file.close()
                temp_files.append(temp_file.name)
                file_paths.append(temp_file.name)
                logger.info(f"Downloaded {filename} from MinIO to {temp_file.name}")
        else:
            # Local mode: arg1 is file_paths
            file_paths = arg1

        conversion_results = converter.convert_all(
            file_paths,
            raises_on_error=True,
        )

        for result in conversion_results:
            file_path = str(result.input.file)
            try:
                if result.status in {
                    ConversionStatus.SUCCESS,
                    ConversionStatus.PARTIAL_SUCCESS,
                }:
                    markdown = result.document.export_to_markdown()
                    results.append(
                        {
                            "filename": os.path.basename(file_path),
                            "status": "success",
                            "content": markdown,
                        }
                    )
                else:
                    error_msg = (
                        "; ".join(str(error) for error in result.errors)
                        if result.errors
                        else f"Conversion failed with status: {result.status}"
                    )
                    logger.error(f"Failed to convert {file_path}: {error_msg}")
                    results.append(
                        {
                            "filename": os.path.basename(file_path),
                            "status": "failed",
                            "error": error_msg,
                        }
                    )
            finally:
                # Clean up the temporary file
                try:
                    os.unlink(file_path)
                    logger.info(f"Cleaned up file: {file_path}")
                except Exception as e:
                    logger.error(f"Error cleaning up file: {e}")

        # Clean up MinIO files if in OpenShift mode
        if OPENSHIFT_MODE and arg2 is not None:
            try:
                storage_manager.delete_job_files("pdf-service", arg1)
                logger.info(f"Cleaned up MinIO files for job {arg1}")
            except Exception as e:
                logger.error(f"Error cleaning up MinIO files: {e}")

        return results

    except Exception as exc:
        logger.error(f"Error in batch conversion: {exc}")
        # Clean up temp files on error
        for temp_file in temp_files:
            try:
                if os.path.exists(temp_file):
                    os.unlink(temp_file)
            except Exception as e:
                logger.error(f"Error cleaning up temp file {temp_file}: {e}")
        retry_in = 5 * (2**self.request.retries)
        raise self.retry(exc=exc, countdown=retry_in)
