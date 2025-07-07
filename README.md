# Finance Doc AI

Finance Doc AI is a platform for processing financial documents and providing AI-powered Q&A services. This project includes a backend (with PDF processing and API services) and a React frontend.

## Project Structure

- `backend/` - Cloud Run services for PDF processing and AI Q&A API
- `frontend/` - React frontend application
- `terraform/` - Infrastructure as code

## Getting Started


## Building Docker Images for Cloud Run (Linux/amd64)

When building Docker images for deployment to Google Cloud Run, you must ensure the image is built for the `linux/amd64` platform (even if you are on macOS with Apple Silicon). This avoids compatibility issues in production.

**To build and push your Docker image for linux/amd64:**

```
docker buildx build --platform linux/amd64 -t gcr.io/<YOUR_PROJECT_ID>/<IMAGE_NAME>:latest <PATH_TO_DOCKERFILE_DIR> --push
```

**Example for the API service:**

```
docker buildx build --platform linux/amd64 -t gcr.io/finance-doc-ai/api-service:latest ./backend/api_service --push
```

Replace `<YOUR_PROJECT_ID>`, `<IMAGE_NAME>`, and `<PATH_TO_DOCKERFILE_DIR>` as needed.
