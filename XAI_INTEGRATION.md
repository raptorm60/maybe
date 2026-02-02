# xAI (Grok) Integration for Maybe Finance

## What Was Done

I've integrated xAI's Grok API as an alternative to OpenAI for AI features in Maybe Finance.

## Files Created/Modified

### New Files:
- `app/models/provider/xai.rb` - Main xAI provider
- `app/models/provider/xai/auto_categorizer.rb` - Auto-categorization logic
- `app/models/provider/xai/auto_merchant_detector.rb` - Merchant detection logic
- `app/models/provider/xai/chat_config.rb` - Chat configuration
- `app/models/provider/xai/chat_parser.rb` - Response parser
- `app/models/provider/xai/chat_stream_parser.rb` - Streaming parser

### Modified Files:
- `app/models/provider/registry.rb` - Added xAI provider registration
- `app/models/setting.rb` - Added `xai_api_key` field
- `app/models/family/auto_categorizer.rb` - Prefers xAI over OpenAI
- `app/models/family/auto_merchant_detector.rb` - Prefers xAI over OpenAI
- `.env` - Added XAI_API_KEY configuration
- `compose.yml` - Added XAI_API_KEY environment variable

## How It Works

The integration uses the `ruby-openai` gem's ability to connect to OpenAI-compatible APIs by setting a custom `uri_base`:

```ruby
@client = ::OpenAI::Client.new(
  access_token: access_token,
  uri_base: "https://api.x.ai/v1"  # xAI endpoint
)
```

## Priority System

The app now tries xAI first, then falls back to OpenAI:

```ruby
Provider::Registry.get_provider(:xai) || Provider::Registry.get_provider(:openai)
```

## Configuration

Add your xAI API key to `.env`:

```bash
XAI_API_KEY=xai-your-api-key-here
```

Get your API key from: https://console.x.ai/

## Supported Model

- `grok-4-1-fast-reasoning` - Latest Grok model with fast reasoning capabilities

## AI Features That Will Use Grok

1. **Chat Assistant** - Financial Q&A with access to your data
2. **Auto-Categorization** - Automatically categorize transactions
3. **Merchant Detection** - Identify merchants from transaction descriptions

## Next Steps

1. Get your xAI API key from https://console.x.ai/
2. Add it to `.env` file
3. Deploy to your Mac Mini
4. The app will automatically use Grok for all AI features!

## Cost Savings

Using your existing xAI credits instead of paying for OpenAI!
