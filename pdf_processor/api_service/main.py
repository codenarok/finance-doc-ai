# AI Q&A API Service using Flask
from flask import Flask
import os

app = Flask(__name__)

@app.route("/")
def index():
    return "API Service Running"

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False, use_reloader=False)
