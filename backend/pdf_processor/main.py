import os
import json
import pdfplumber
import psycopg2
from flask import Flask, request, jsonify
from google.cloud import storage
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)


# Environment variables for database connection - now populated from Secret Manager
DB_USER = os.environ.get("DB_USER")
DB_PASSWORD = os.environ.get("DB_PASSWORD") # Fetched securely from Secret Manager
DB_NAME = os.environ.get("DB_NAME")

# Build the socket path explicitly
INSTANCE_CONNECTION_NAME = os.environ["INSTANCE_CONNECTION_NAME"]
socket_path = f"/cloudsql/{INSTANCE_CONNECTION_NAME}"

# Initialize Google Cloud Storage client
storage_client = storage.Client()

def get_db_connection():
    """Establishes a connection to the PostgreSQL database."""
    try:
        conn = psycopg2.connect(
            host=f"/cloudsql/{os.environ['INSTANCE_CONNECTION_NAME']}",
            dbname=os.environ['DB_NAME'],
            user=os.environ['DB_USER'],
            password=os.environ['DB_PASSWORD']
        )
        return conn
    except Exception as e:
        logger.error(f"Error connecting to database: {e}")
        raise

def create_table_if_not_exists():
    """Creates the document_chunks table if it doesn't exist."""
    conn = None
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS document_chunks (
                id SERIAL PRIMARY KEY,
                document_name VARCHAR(255) NOT NULL,
                page_number INTEGER NOT NULL,
                chunk_index INTEGER NOT NULL,
                text_content TEXT NOT NULL,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            );

            -- 👇 NEW: guarantee uniqueness so ON CONFLICT works
            CREATE UNIQUE INDEX IF NOT EXISTS uniq_doc_page_chunk
              ON document_chunks (document_name, page_number, chunk_index);

            CREATE INDEX IF NOT EXISTS idx_document_name ON document_chunks (document_name);
            CREATE INDEX IF NOT EXISTS idx_text_content_gin ON document_chunks USING GIN (to_tsvector('english', text_content));
        """)
        conn.commit()
        logger.info("Table 'document_chunks' checked/created successfully.")
    except Exception as e:
        logger.error(f"Error creating table: {e}")
    finally:
        if conn:
            conn.close()

def extract_text_from_pdf(bucket_name, file_name):
    """
    Downloads a PDF from GCS and extracts text using pdfplumber.
    Returns a list of (page_number, text_content) tuples.
    """
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(file_name)
    download_path = f"/tmp/{file_name}" # Use /tmp for temporary storage in Cloud Run

    try:
        blob.download_to_filename(download_path)
        logger.info(f"Downloaded {file_name} to {download_path}")

        extracted_data = []
        with pdfplumber.open(download_path) as pdf:
            for i, page in enumerate(pdf.pages):
                try:
                    text = page.extract_text()
                    if text:
                        extracted_data.append((i + 1, text))  # Page numbers are 1-indexed
                except Exception as e:
                    logger.error(f"Failed to extract text from page {i + 1} of {file_name}: {e}")
        logger.info(f"Extracted text from {len(extracted_data)} pages of {file_name}")
        return extracted_data
    except Exception as e:
        logger.error(f"Error processing PDF {file_name}: {e}")
        return []
    finally:
        if os.path.exists(download_path):
            os.remove(download_path) # Clean up temporary file

def chunk_text(text, chunk_size=1000, overlap=100):
    """
    Splits text into chunks with optional overlap.
    A more sophisticated chunking strategy might be needed for complex documents.
    """
    chunks = []
    current_chunk = ""
    words = text.split()
    for word in words:
        if len(current_chunk) + len(word) + 1 > chunk_size and current_chunk:
            chunks.append(current_chunk.strip())
            current_chunk = current_chunk[-overlap:] + " " if overlap > 0 else ""
        current_chunk += (word + " ")
    if current_chunk:
        chunks.append(current_chunk.strip())
    return chunks

def insert_chunks_to_db(document_name, page_number, chunks):
    """Inserts text chunks into the PostgreSQL database."""
    conn = None
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        for i, chunk_text in enumerate(chunks):
            cur.execute(
                """
                INSERT INTO document_chunks (document_name, page_number, chunk_index, text_content)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (document_name, page_number, chunk_index) DO UPDATE
                SET text_content = EXCLUDED.text_content, created_at = CURRENT_TIMESTAMP;
                """,
                (document_name, page_number, i, chunk_text)
            )
        conn.commit()
        logger.info(f"Inserted {len(chunks)} chunks for {document_name} page {page_number}")
    except Exception as e:
        logger.error(f"Error inserting chunks for {document_name} page {page_number}: {e}")
    finally:
        if conn:
            conn.close()

@app.route("/", methods=["POST"])
def process_pdf_event():
    """
    Handles Google Cloud Storage object finalization events.
    """
    create_table_if_not_exists() # Ensure table exists on each invocation

    event = request.get_json()
    if not event:
        return jsonify({"status": "No event data"}), 200

    logger.info(f"Received event: {json.dumps(event, indent=2)}")


    # Optional shortcut for manual POST testing (not from GCS)
    if "bucket" in event and "name" in event:
        bucket_name = event["bucket"]
        file_name = event["name"]
        logger.info(f"[Manual Trigger] Processing gs://{bucket_name}/{file_name}")
        # You can add content_type if needed, or set a default
        content_type = event.get("contentType", "")
    elif "message" in event and "data" in event["message"]:
        # Pub/Sub message from GCS notification
        data = json.loads(event["message"]["data"])
        bucket_name = data["bucket"]
        file_name = data["name"]
        content_type = data["contentType"]
    else:
        logger.warning("Unknown event format.")
        return jsonify({"status": "Unknown event format"}), 400

    if not file_name.lower().endswith(".pdf"):
        logger.info(f"Skipping non-PDF file: {file_name}")
        return jsonify({"status": "Skipped non-PDF file"}), 200

    logger.info(f"Processing PDF: gs://{bucket_name}/{file_name}")

    extracted_pages = extract_text_from_pdf(bucket_name, file_name)

    for page_num, page_text in extracted_pages:
        chunks = chunk_text(page_text)
        insert_chunks_to_db(file_name, page_num, chunks)

    return jsonify({"status": "PDF processed successfully", "file": file_name}), 200

if __name__ == "__main__":
    # For local testing, load environment variables from .env file
    from dotenv import load_dotenv
    load_dotenv()
    create_table_if_not_exists()
    app.run(debug=True, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
