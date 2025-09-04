#!/bin/bash

# Test script for the Anthropic proxy
# Run this after starting the Anthropic proxy on port 9001

echo "Testing Anthropic Proxy at localhost:9002"
echo "========================================="
echo ""

# Replace with your actual Anthropic API key
API_KEY="${ANTHROPIC_API_KEY:-sk-ant-api...}"

if [ "$API_KEY" == "sk-ant-api..." ]; then
    echo "⚠️  Warning: Please set your ANTHROPIC_API_KEY environment variable"
    echo "   Example: export ANTHROPIC_API_KEY='your-actual-key'"
    exit 1
fi

# Test 1: Simple non-streaming request
echo "Test 1: Non-streaming request"
echo "-----------------------------"

curl -X POST http://localhost:9002/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-3-haiku-20240307",
    "max_tokens": 100,
    "messages": [
      {
        "role": "user",
        "content": "Hello! Please respond with a brief greeting."
      }
    ]
  }'

echo -e "\n\n"

# Test 2: Streaming request
echo "Test 2: Streaming request"
echo "------------------------"

curl -X POST http://localhost:9002/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-3-haiku-20240307",
    "max_tokens": 100,
    "stream": true,
    "messages": [
      {
        "role": "user",
        "content": "Count from 1 to 5 slowly."
      }
    ]
  }'

echo -e "\n\n"

# Test 3: Model list (if supported)
echo "Test 3: Model list request"
echo "-------------------------"

curl -X GET http://localhost:9002/v1/models \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01"

echo -e "\n\nDone! Check the app's log viewer to see tracked requests."