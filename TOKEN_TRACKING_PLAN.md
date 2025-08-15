# Token Usage Tracking Implementation Plan

## Overview
This document outlines the comprehensive plan for tracking token usage from both OpenAI-compatible (`/v1/chat/completions`) and Anthropic-compatible (`/v1/messages`) endpoints in the LiteLLM OIDC Proxy. The implementation will handle both streaming and non-streaming responses and store the data in our existing request tracking database.

## Database Schema Design

### Core Token Fields (Required)
- **`prompt_tokens`** (INTEGER) - Number of input tokens used
- **`completion_tokens`** (INTEGER) - Number of output tokens generated  
- **`total_tokens`** (INTEGER) - Total tokens (prompt + completion)

### Advanced Token Fields (Anthropic/Claude Specific)
- **`cache_creation_input_tokens`** (INTEGER) - Tokens used to create cache entry
- **`cache_read_input_tokens`** (INTEGER) - Tokens read from cache
- **`cache_creation_input_tokens_5m`** (INTEGER) - 5-minute cache creation tokens
- **`cache_creation_input_tokens_1h`** (INTEGER) - 1-hour cache creation tokens

### Cost Tracking Fields
- **`response_cost`** (REAL) - Total cost in dollars for this request
- **`input_cost`** (REAL) - Cost for input tokens
- **`output_cost`** (REAL) - Cost for output tokens

### Performance Metrics
- **`time_to_first_token`** (REAL) - Latency to first token (streaming responses)
- **`tokens_per_second`** (REAL) - Token generation speed

### Additional Metadata
- **`litellm_call_id`** (TEXT) - Unique call ID from x-litellm-call-id header (always available)
- **`cache_hit`** (BOOLEAN) - Whether prompt cache was used
- **`usage_tier`** (TEXT) - Priority/standard/batch tier (Anthropic)
- **`litellm_model_id`** (TEXT) - LiteLLM's model identifier hash
- **`litellm_response_cost`** (REAL) - Cost from x-litellm-response-cost header (non-streaming only)
- **`response_duration_ms`** (REAL) - From x-litellm-response-duration-ms (non-streaming only)
- **`attempted_fallbacks`** (INTEGER) - Number of fallback attempts (non-streaming only)
- **`attempted_retries`** (INTEGER) - Number of retry attempts (non-streaming only)

**Note**: Several LiteLLM headers are only available in non-streaming responses. For streaming responses, we'll need to calculate costs from token usage.

## Token Extraction Patterns

### OpenAI Format (`/v1/chat/completions`)
#### Non-Streaming Response
```json
{
  "choices": [...],
  "usage": {
    "prompt_tokens": 57,
    "completion_tokens": 17,
    "total_tokens": 74
  }
}
```

#### Streaming Response
- Usage data is always included in the final chunk (even without `stream_options`)
- Final chunk before `[DONE]` contains usage data:
```
data: {"id":"...", "choices":[{"index":0,"delta":{}}], "usage":{"prompt_tokens":9,"completion_tokens":9,"total_tokens":18}}
data: [DONE]
```
- Headers: `Content-Type: text/event-stream; charset=utf-8`

### Anthropic Format (`/v1/messages`)
#### Non-Streaming Response
```json
{
  "content": [...],
  "usage": {
    "input_tokens": 100,
    "output_tokens": 50,
    "cache_creation_input_tokens": 0,
    "cache_read_input_tokens": 80
  }
}
```

#### Streaming Response  
- Initial usage in `message_start` event (with partial output_tokens):
```
event: message_start
data: {"type":"message_start","message":{...,"usage":{"input_tokens":14,"output_tokens":3,...}}}
```
- Final usage in `message_delta` event (with complete output_tokens):
```
event: message_delta
data: {"type":"message_delta","delta":{...},"usage":{"output_tokens":10}}
```
- No usage data in `message_stop` event

## Implementation Steps

### 1. Database Migration
- Add new columns with NULL defaults for backward compatibility
- Create migration version 2 in `DatabaseMigrations.swift`
- Ensure existing data remains intact

### 2. Update Data Models
- Extend `RequestLog` struct with token fields
- Update `DatabaseManager` to handle new columns
- Add computed properties for cost calculations

### 3. Token Extraction Service
Create `TokenUsageExtractor` with methods to:
- Detect response format (OpenAI vs Anthropic)
- Extract usage from non-streaming responses
- Parse SSE streams for usage data
- Handle missing or malformed usage data gracefully

### 4. HTTPServer Integration
- Capture token usage during response processing
- Buffer streaming responses to extract final usage
- Calculate costs using model pricing data
- Store usage data with request log

### 5. UI Enhancements
- Display token counts in `LogViewerView`
- Show costs if pricing data available
- Add token statistics to quick stats menu
- Create token usage summary views

## Key Considerations

### LiteLLM Response Caching
- **Important Discovery**: LiteLLM caches responses for identical requests (same model, messages, temperature=0)
- Cached OpenAI responses return the same `id` and `created` timestamp
- Cached Claude responses return different `id` values each time
- Token usage is still reported for cached responses
- Costs are still tracked (`x-litellm-key-spend` header)
- No explicit cache headers indicate when a response is cached

### Streaming Response Handling
- Buffer entire response to find usage data
- Track time to first token for performance metrics
- Handle incomplete streams gracefully

### Cost Calculation
- Integrate with Models Explorer pricing data
- Support different pricing tiers
- Handle free tier models appropriately
- Note: LiteLLM tracks costs even for cached responses

### Error Resilience
- Continue logging requests even if token extraction fails
- Use NULL/0 values when data unavailable
- Log extraction errors for debugging

### Performance Impact
- Minimize overhead in request processing
- Use efficient parsing for large responses
- Consider async processing for cost calculations

## Testing Strategy

### Unit Tests
- Token extraction from various response formats
- Cost calculation accuracy
- Database migration integrity

### Integration Tests
- End-to-end token tracking for all endpoints
- Streaming vs non-streaming comparison
- Provider-specific feature validation

### Manual Testing
- Verify UI displays token data correctly
- Test with real LiteLLM proxy responses
- Validate cost calculations against provider pricing

## Future Enhancements

1. **Token Budgeting**: Set limits per user/team
2. **Usage Analytics**: Charts and trends over time
3. **Export Features**: CSV/JSON export of usage data
4. **Alerts**: Notify when approaching token limits
5. **Multi-Model Comparison**: Compare token efficiency across models

## Migration Notes

- Existing logs will have NULL values for new fields
- No data loss or corruption expected
- UI will gracefully handle missing token data
- Can be rolled back by removing new columns

## References

- [OpenAI API Usage Documentation](https://platform.openai.com/docs/api-reference/chat/object)
- [Anthropic API Usage Documentation](https://docs.anthropic.com/en/api/messages)
- [LiteLLM Proxy Cost Tracking](https://docs.litellm.ai/docs/proxy/cost_tracking)