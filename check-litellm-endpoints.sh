#!/bin/bash

# Check what endpoints LiteLLM supports

echo "Checking LiteLLM endpoints..."
echo

# Test base endpoint
echo "1. Testing base endpoint:"
curl -X GET http://localhost:9000/
echo
echo

# Test models endpoint
echo "2. Testing /models endpoint:"
curl -X GET http://localhost:9000/models
echo
echo

# Test v1/models endpoint
echo "3. Testing /v1/models endpoint:"
curl -X GET http://localhost:9000/v1/models
echo
echo

# Test health endpoint
echo "4. Testing /health endpoint:"
curl -X GET http://localhost:9000/health
echo
echo

# Show available models
echo "5. Testing OpenAI-style completions:"
curl -X POST http://localhost:9000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-3-5-haiku-20241022",
    "messages": [{"role": "user", "content": "test"}],
    "max_tokens": 10
  }'
echo
echo

# Try Anthropic endpoint without v1
echo "6. Testing /messages without v1:"
curl -X POST http://localhost:9000/messages \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-3-5-haiku-20241022",
    "messages": [{"role": "user", "content": "test"}],
    "max_tokens": 10
  }'
echo