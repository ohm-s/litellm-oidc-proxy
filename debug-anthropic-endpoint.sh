#!/bin/bash

echo "Debugging Anthropic endpoint on LiteLLM..."
echo

# First, let's check if the proxy is properly forwarding the request
echo "1. Testing direct request to see proxy behavior:"
curl -v -X POST http://127.0.0.1:9000/v1/messages \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-3-5-haiku-20241022",
    "messages": [{"role": "user", "content": "test"}],
    "max_tokens": 10
  }' 2>&1 | grep -E "(< HTTP|< |> |POST)"

echo
echo

# Try OpenAI-style completion with Claude model
echo "2. Testing OpenAI endpoint with Claude model:"
curl -X POST http://127.0.0.1:9000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-3-5-haiku-20241022",
    "messages": [{"role": "user", "content": "test"}],
    "max_tokens": 10
  }'

echo
echo

# Check what models are available
echo "3. Listing available models:"
curl -X GET http://127.0.0.1:9000/v1/models

echo
echo

# Try without the v1 prefix
echo "4. Testing /messages without v1 prefix:"
curl -X POST http://127.0.0.1:9000/messages \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-3-5-haiku-20241022",
    "messages": [{"role": "user", "content": "test"}],
    "max_tokens": 10
  }'

echo
echo

# Test with the exact request format from the user
echo "5. Testing with exact user request format:"
curl -H "Content-Type: application/json" \
  "http://127.0.0.1:9000/v1/messages?beta=true" \
  --data '{
    "model": "claude-3-5-haiku-20241022",
    "max_tokens": 512,
    "messages": [{"role": "user", "content": "hi"}],
    "system": [{"type": "text", "text": "You are a helpful assistant."}],
    "temperature": 0,
    "stream": false
  }'

echo