"""
FastAPI Production Application Example
======================================
"""
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import logging
import os

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="FastAPI Docker Example",
    description="Production-ready FastAPI application",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Pydantic models
class HealthResponse(BaseModel):
    status: str
    version: str
    environment: str


class MessageResponse(BaseModel):
    message: str


# Health check endpoint
@app.get("/health", response_model=HealthResponse, tags=["Health"])
async def health_check():
    """Health check endpoint for container orchestration"""
    return HealthResponse(
        status="healthy",
        version="1.0.0",
        environment=os.getenv("APP_ENV", "development")
    )


# Root endpoint
@app.get("/", response_model=MessageResponse, tags=["Root"])
async def root():
    """Root endpoint"""
    return MessageResponse(message="Welcome to FastAPI Docker Example")


# Example API endpoint
@app.get("/api/v1/items/{item_id}", tags=["Items"])
async def get_item(item_id: int):
    """Get item by ID"""
    if item_id < 0:
        raise HTTPException(status_code=400, detail="Item ID must be positive")
    return {"item_id": item_id, "name": f"Item {item_id}"}


# Startup event
@app.on_event("startup")
async def startup_event():
    logger.info("Application starting up...")
    logger.info(f"Environment: {os.getenv('APP_ENV', 'development')}")


# Shutdown event
@app.on_event("shutdown")
async def shutdown_event():
    logger.info("Application shutting down...")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=int(os.getenv("PORT", 8000)),
        reload=os.getenv("APP_ENV") == "development"
    )
