class Provider::Xai < Provider
  include LlmConcept

  # Subclass so errors caught in this provider are raised as Provider::Xai::Error
  Error = Class.new(Provider::Error)

  # xAI Grok models - support both native names and OpenAI-compatible aliases
  MODELS = %w[grok-2-1212 gpt-4.1 gpt-4.1-mini]
  
  # Map OpenAI model names to xAI Grok models
  MODEL_MAPPING = {
    "gpt-4.1" => "grok-2-1212",
    "gpt-4.1-mini" => "grok-2-1212"
  }.freeze

  def initialize(access_token)
    @client = ::OpenAI::Client.new(
      access_token: access_token,
      uri_base: "https://api.x.ai/v1"  # xAI API endpoint
    )
  end

  def supports_model?(model)
    MODELS.include?(model)
  end
  
  # Translate OpenAI model names to xAI equivalents
  def translate_model(model)
    MODEL_MAPPING[model] || model
  end

  def auto_categorize(transactions: [], user_categories: [])
    with_provider_response do
      raise Error, "Too many transactions to auto-categorize. Max is 25 per request." if transactions.size > 25

      AutoCategorizer.new(
        client,
        transactions: transactions,
        user_categories: user_categories
      ).auto_categorize
    end
  end

  def auto_detect_merchants(transactions: [], user_merchants: [])
    with_provider_response do
      raise Error, "Too many transactions to auto-detect merchants. Max is 25 per request." if transactions.size > 25

      AutoMerchantDetector.new(
        client,
        transactions: transactions,
        user_merchants: user_merchants
      ).auto_detect_merchants
    end
  end

  def chat_response(prompt, model:, instructions: nil, functions: [], function_results: [], streamer: nil, previous_response_id: nil)
    with_provider_response do
      chat_config = ChatConfig.new(
        functions: functions,
        function_results: function_results
      )

      collected_chunks = []

      # Proxy that converts raw stream to "LLM Provider concept" stream
      stream_proxy = if streamer.present?
        proc do |chunk|
          parsed_chunk = ChatStreamParser.new(chunk).parsed

          unless parsed_chunk.nil?
            streamer.call(parsed_chunk)
            collected_chunks << parsed_chunk
          end
        end
      else
        nil
      end

      raw_response = client.responses.create(parameters: {
        model: translate_model(model),  # Translate gpt-4.1 -> grok-2-1212
        input: chat_config.build_input(prompt),
        instructions: instructions,
        tools: chat_config.tools,
        previous_response_id: previous_response_id,
        stream: stream_proxy
      })

      # If streaming, Ruby OpenAI does not return anything, so to normalize this method's API, we search
      # for the "response chunk" in the stream and return it (it is already parsed)
      if stream_proxy.present?
        response_chunk = collected_chunks.find { |chunk| chunk.type == "response" }
        response_chunk.data
      else
        ChatParser.new(raw_response).parsed
      end
    end
  end

  private
    attr_reader :client
end
