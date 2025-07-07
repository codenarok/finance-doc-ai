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

# Run your app
CMD ["python", "main.py"]
