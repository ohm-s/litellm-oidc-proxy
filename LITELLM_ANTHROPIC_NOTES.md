# LiteLLM Anthropic Integration Notes

## Overview
LiteLLM supports both OpenAI and Anthropic API formats, providing flexibility for different client implementations.

## Supported Endpoints
LiteLLM supports multiple endpoint formats:

1. **OpenAI-compatible**: `/v1/chat/completions` - Standard OpenAI format
2. **Anthropic-compatible**: `/v1/messages` - Native Anthropic format
3. **Model listing**: `/v1/models` - Lists available models

## Using Anthropic Models
You can use Anthropic models through either endpoint:

### Option 1: OpenAI Format (`/v1/chat/completions`)
- Use OpenAI-style request format
- Specify the Anthropic model name: `"model": "claude-3-5-haiku-20241022"`
- LiteLLM handles the translation internally

### Option 2: Anthropic Format (`/v1/messages`)
- Use Anthropic's native message format
- Specify the Anthropic model name
- Direct compatibility with Anthropic SDKs

## Example Requests

### OpenAI Format
```bash
curl -X POST http://127.0.0.1:9000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-3-5-haiku-20241022",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Hello"}
    ],
    "stream": true,
    "max_tokens": 512,
    "temperature": 0
  }'
```

### Anthropic Format
```bash
curl -X POST http://127.0.0.1:9000/v1/messages \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-3-5-haiku-20241022",
    "messages": [
      {"role": "user", "content": "Hello"}
    ],
    "stream": true,
    "max_tokens": 512
  }'
```

## Proxy Behavior
The OIDC proxy correctly:
- Detects streaming requests for both `/v1/chat/completions` and `/v1/messages`
- Forwards requests with proper authentication
- Handles streaming responses for both endpoint formats
- Maintains compatibility with both OpenAI and Anthropic client libraries