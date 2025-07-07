# Use Python
FROM python:3.9

# Set working directory
WORKDIR /app

# Copy files
COPY . .

# Install dependencies
RUN pip install -r requirements.txt

# Expose port
EXPOSE 8080

# Run your app with gunicorn (production WSGI server)
CMD ["gunicorn", "-b", "0.0.0.0:8080", "main:app"]
