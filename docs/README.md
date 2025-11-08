# Veeam task to show learning and use of Locust, Poetry and Docker

## Objective
In this project I will show to my future colleagues Dmitry and Ihor that I've learned Locust and Poetry at least enough to make a simple setup, and I will show that I know how to setup and use Docker to run our test in a container

## Pre-requisites
- Docker has to be installed in the pods that we'll use as load generators.

## Requirements
- No requirements from business yet, run benchmarks to provide data for the decision

## Project Structure
- `locustfile.py` - Locust test scenario
- `pyproject.toml` - This file holds the dependencies that must be set up for Poetry
- `Dockerfile` - Configuration of our docker container
- `reports/` - Generated HTML reports

## Batch run
- `chmod a+x run.sh` - Before running the batch file we have to make it executable
- `./run.sh` - This will check if docker is installed and started and then will load locust-docker-image and start the test in browser mode

## Build Docker Image
```bash
docker build -t locust-docker-image . 
```
## Run Tests
Browser mode
```bash
docker run -p 8089:8089 -v $(pwd)/reports:/app/reports locust-docker-image --host=https://jsonplaceholder.typicode.com
```    
Live test dashboard in http://localhost:8089

CLI mode
```bash
docker run -p 8089:8089 -v $(pwd)/reports:/app/reports locust-docker-image \
    --host=https://jsonplaceholder.typicode.com --headless -u 10 -r 2 -t 30s \
    --html /app/reports/report.html
```

## Results

After running in CLI mode, open /reports/report.html in a browser
