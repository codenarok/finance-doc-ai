import os
import psycopg2
import google.generativeai as genai
from flask import Flask, request, jsonify
from flask_cors import CORS # To handle CORS for frontend
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app) # Enable CORS for all routes

# Environment variables for database connection - now populated from Secret Manager
DB_HOST = os.environ.get("DB_HOST")
DB_USER = os.environ.get("DB_USER")
DB_PASSWORD = os.environ.get("DB_PASSWORD") # Fetched securely from Secret Manager
DB_NAME = os.environ.get("DB_NAME")

# Configure Gemini API - key fetched securely from Secret Manager
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY")
if not GEMINI_API_KEY:
    logger.error("GEMINI_API_KEY not set. AI functionality will not work.")
    # In a production app, you might raise an error or exit here.
genai.configure(api_key=GEMINI_API_KEY)
model = genai.GenerativeModel('gemini-2.0-flash')

def get_db_connection():
    """Establishes a connection to the PostgreSQL database."""
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            user=DB_USER,
            password=DB_PASSWORD,
            dbname=DB_NAME,
            sslmode="disable"
        )
        return conn
    except Exception as e:
        logger.error(f"Error connecting to database: {e}")
        raise

def retrieve_relevant_chunks(query, num_chunks=5):
    """
    Retrieves text chunks from the database relevant to the query.
    Uses a simple keyword search with ILIKE for demonstration.
    For production, consider full-text search (TSVECTOR) or embeddings.
    """
    conn = None
    chunks = []
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        # Using to_tsquery for basic full-text search if idx_text_content_gin is created
        # Otherwise, fall back to ILIKE
        search_query = " | ".join(query.split()) # Convert "word1 word2" to "word1 | word2" for OR search
        cur.execute(
            """
            SELECT text_content
            FROM document_chunks
            WHERE to_tsvector('english', text_content) @@ to_tsquery('english', %s)
            LIMIT %s;
            """,
            (search_query, num_chunks)
        )
        # Fallback if full-text search index isn't used or preferred:
        # cur.execute(
        #     """
        #     SELECT text_content
        #     FROM document_chunks
        #     WHERE text_content ILIKE %s
        #     LIMIT %s;
        #     """,
        #     (f"%{query}%", num_chunks)
        # )
        chunks = [row[0] for row in cur.fetchall()]
        logger.info(f"Retrieved {len(chunks)} relevant chunks for query: '{query}'")
    except Exception as e:
        logger.error(f"Error retrieving chunks: {e}")
    finally:
        if conn:
            conn.close()
    return chunks

def generate_ai_response(query, context_chunks):
    """
    Generates an AI response using Gemini, augmented with retrieved context.
    """
    if not GEMINI_API_KEY:
        return "AI service is not configured. Please set GEMINI_API_KEY."

    context = "\n\n".join(context_chunks)
    if not context:
        return "I couldn't find relevant information in the documents to answer your question. Please try rephrasing or ask about something else."

    prompt = f"""
    You are an AI assistant that answers questions based ONLY on the provided financial document content.
    If the answer cannot be found in the provided content, state that you don't have enough information.
    Do NOT make up information.

    Financial Document Content:
    ---
    {context}
    ---

    User Question: {query}

    Answer:
    """
    logger.info(f"Sending prompt to Gemini:\n{prompt[:500]}...") # Log first 500 chars of prompt

    try:
        response = model.generate_content(prompt)
        return response.text
    except Exception as e:
        logger.error(f"Error calling Gemini API: {e}")
        return "An error occurred while generating the AI response."

@app.route("/ask", methods=["POST"])
def ask_ai():
    """API endpoint for asking questions to the AI."""
    data = request.get_json()
    query = data.get("query")

    if not query:
        return jsonify({"error": "Query parameter is missing"}), 400

    logger.info(f"Received query: '{query}'")

    # 1. Retrieve relevant chunks from the database
    relevant_chunks = retrieve_relevant_chunks(query)

    # 2. Generate AI response using the retrieved chunks as context
    ai_response = generate_ai_response(query, relevant_chunks)

    return jsonify({"answer": ai_response})

@app.route("/health", methods=["GET"])
def health_check():
    """Health check endpoint for Cloud Run."""
    return jsonify({"status": "ok"}), 200

if __name__ == "__main__":
    # For local testing, load environment variables from .env file
    from dotenv import load_dotenv
    load_dotenv()
    create_table_if_not_exists()
    app.run(debug=True, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
