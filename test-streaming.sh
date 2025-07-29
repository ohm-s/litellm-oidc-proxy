#!/bin/bash

# Test script for streaming endpoints
# This tests both OpenAI-compatible and Anthropic-compatible streaming

echo "Testing streaming endpoints..."
echo

# Test OpenAI-style streaming
echo "1. Testing OpenAI /chat/completions streaming..."
curl -X POST http://localhost:9000/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [{"role": "user", "content": "Hello, count to 5"}],
    "stream": true
  }' \
  -N

echo
echo

# Test Anthropic-style streaming
echo "2. Testing Anthropic /messages streaming..."
curl -X POST http://localhost:9000/messages \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-3-sonnet",
    "messages": [{"role": "user", "content": "Hello, count to 5"}],
    "stream": true
  }' \
  -N

echo
echo

# Test non-streaming OpenAI
echo "3. Testing OpenAI /chat/completions non-streaming..."
curl -X POST http://localhost:9000/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [{"role": "user", "content": "Say hello"}],
    "stream": false
  }'

echo
echo

# Test non-streaming Anthropic
echo "4. Testing Anthropic /messages non-streaming..."
curl -X POST http://localhost:9000/messages \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-3-sonnet",
    "messages": [{"role": "user", "content": "Say hello"}],
    "stream": false
  }'

echo
echo "Streaming tests completed."