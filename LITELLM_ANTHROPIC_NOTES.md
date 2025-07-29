# LiteLLM Anthropic Integration Notes

## Problem
LiteLLM returns 404 for `/v1/messages` endpoint when trying to use Anthropic models.

## Understanding
LiteLLM acts as a unified interface that translates all requests to OpenAI's format. This means:

1. **All requests go through `/v1/chat/completions`** - regardless of the underlying model provider
2. **Model selection determines the provider** - e.g., `claude-3-5-haiku-20241022` tells LiteLLM to use Anthropic
3. **Request format is OpenAI-style** - LiteLLM handles the translation to Anthropic's format internally

## Solution
To use Anthropic models through LiteLLM:

1. Use the OpenAI endpoint: `/v1/chat/completions`
2. Specify the Anthropic model name: `"model": "claude-3-5-haiku-20241022"`
3. Use OpenAI-style request format
4. LiteLLM will handle the translation to Anthropic's API

## Example Request
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

## Proxy Behavior
The OIDC proxy correctly:
- Detects streaming requests for both `/chat/completions` and `/messages`
- Forwards requests with proper authentication
- Handles streaming responses

However, since LiteLLM doesn't support `/v1/messages`, those requests will return 404.

## Recommendation
If you need to support Anthropic's native `/v1/messages` endpoint, you would need to either:
1. Configure LiteLLM to support it (if possible)
2. Add endpoint translation in the proxy to convert `/v1/messages` requests to `/v1/chat/completions`
3. Use a different proxy that supports multiple endpoint formats