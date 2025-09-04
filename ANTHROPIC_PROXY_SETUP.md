# Anthropic Proxy Setup Guide

The Anthropic proxy (running on port 9002) can work in two modes:

## 1. HTTP CONNECT Proxy Mode (Current Implementation)

In this mode, the proxy acts as a standard HTTP proxy:
- Client establishes CONNECT tunnel for HTTPS
- Proxy only sees encrypted traffic
- Can only log CONNECT requests, not actual API calls

```bash
# Usage with curl
curl -x http://localhost:9002 https://api.anthropic.com/v1/messages ...

# Usage with Claude CLI
HTTP_PROXY=http://localhost:9002 HTTPS_PROXY=http://localhost:9002 claude -p "Hello"
```

## 2. Direct API Proxy Mode (Recommended for Logging)

To log request/response bodies and headers, configure your client to send requests directly to the proxy, which will forward them to Anthropic:

```bash
# Instead of sending to https://api.anthropic.com/v1/messages
# Send to http://localhost:9002/v1/messages

# Example with curl
curl -X POST http://localhost:9002/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-3-haiku-20240307",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

### Configure Claude CLI for Direct Proxy Mode

Set the base URL to point to the proxy:

```bash
# Set Claude CLI to use proxy as API endpoint
export ANTHROPIC_BASE_URL="http://localhost:9002"

# Now Claude CLI will send requests through the proxy
claude -p "Hello"
```

This way, the proxy receives unencrypted requests and can:
- Log full request headers and body
- Log full response headers and body  
- Track token usage
- Monitor API performance

## 3. MITM Proxy Mode (Not Implemented)

A full MITM proxy would:
- Generate certificates on-the-fly
- Decrypt HTTPS traffic
- Require installing a CA certificate

This is complex and has security implications, so the Direct API Proxy mode is recommended instead.
EOF < /dev/null