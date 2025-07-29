#!/bin/bash

# Test script for the LiteLLM OIDC Proxy

echo "Testing LiteLLM OIDC Proxy..."
echo "=============================="

# Test 1: Simple GET request
echo -e "\nTest 1: GET request to /v1/models"
curl -i http://localhost:9000/v1/models

# Test 2: POST request to chat completions
echo -e "\n\nTest 2: POST request to /v1/chat/completions"
curl -i -X POST http://localhost:9000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [
      {"role": "user", "content": "Hello, world!"}
    ]
  }'

# Test 3: Invalid endpoint
echo -e "\n\nTest 3: GET request to invalid endpoint"
curl -i http://localhost:9000/invalid/endpoint

# Test 4: Malformed request
echo -e "\n\nTest 4: Malformed POST request"
curl -i -X POST http://localhost:9000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d 'invalid json'

echo -e "\n\nTests completed. Check the Log Viewer in the app to see tracked requests."