class Provider::Xai < Provider
  include LlmConcept

  # Subclass so errors caught in this provider are raised as Provider::Xai::Error
  Error = Class.new(Provider::Error)

  # xAI Grok model
  MODELS = %w[grok-4-1-fast-reasoning]

  def initialize(access_token)
    @client = ::OpenAI::Client.new(
      access_token: access_token,
      uri_base: "https://api.x.ai/v1"  # xAI API endpoint
    )
  end

  def supports_model?(model)
    MODELS.include?(model)
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

      begin
        # Use blocking request (stream: false) to avoid chunk parsing issues
        # We then simulate streaming to the application to satisfy the architecture
        params = {
          model: model,
          messages: chat_config.build_input(prompt),
          stream: false 
        }

        # Only add tools if they exist (xAI might reject empty tools array)
        if chat_config.tools.present?
          params[:tools] = chat_config.tools
        end

        # Add system instructions if present
        if instructions.present?
          params[:messages].unshift({ role: "system", content: instructions })
        end

        Rails.logger.info "[Provider::Xai] Blocking Request Payload: #{params.to_json}"

        raw_response = client.chat(parameters: params)
        
        # Parse the full response using the reliable (non-streaming) ChatParser
        # This bypassed ChatStreamParser issues completely
        parsed_response = ChatParser.new(raw_response).parsed

        if streamer.present?
          # Simulate text streaming "chunk" (all at once)
          if parsed_response.messages.present?
            parsed_response.messages.each do |msg|
              streamer.call(
                Provider::LlmConcept::ChatStreamChunk.new(
                  type: "output_text",
                  data: msg.output_text
                )
              )
            end
          end
          
          # Emit the final response chunk (required for tools/completion)
          streamer.call(
            Provider::LlmConcept::ChatStreamChunk.new(
              type: "response",
              data: parsed_response
            )
          )
        end

        parsed_response
      rescue => e
        Rails.logger.error "xAI API Error: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        raise
      end
    end
  end

  private
    attr_reader :client
end
