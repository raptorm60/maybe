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
        # Use standard Chat Completions API
        params = {
          model: model,
          messages: chat_config.build_input(prompt),
          stream: stream_proxy
        }

        # Only add tools if they exist (xAI might reject empty tools array)
        if chat_config.tools.present?
          params[:tools] = chat_config.tools
        end

        # Add system instructions if present
        if instructions.present?
          params[:messages].unshift({ role: "system", content: instructions })
        end

        # Capture the payload for debugging
        Rails.logger.info "[Provider::Xai] Request Payload: #{params.except(:stream).to_json}"

        raw_response = client.chat(parameters: params)

        # If streaming, manually construct the response from collected chunks
        if stream_proxy.present?
          full_content = ""
          tool_calls_buffer = {}

          collected_chunks.each do |chunk|
            if chunk.type == "output_text"
              full_content << (chunk.data || "")
            elsif chunk.type == "tool_call_chunk"
              chunk.data.each do |tool_call_delta|
                index = tool_call_delta["index"]
                buffer = tool_calls_buffer[index] ||= { id: nil, name: "", arguments: "" }
                
                buffer[:id] = tool_call_delta["id"] if tool_call_delta["id"]
                
                if fn = tool_call_delta["function"]
                  buffer[:name] << fn["name"] if fn["name"]
                  buffer[:arguments] << fn["arguments"] if fn["arguments"]
                end
              end
            end
          end

          # checking if tool calls are present
          function_requests = tool_calls_buffer.values.map do |tc|
            # Ensure we have an ID (sometimes ID is only in the first chunk)
            # If strictly needed and missing, might need more robust handling, but usually first chunk has it.
            
            Provider::LlmConcept::ChatFunctionRequest.new(
              id: tc[:id],
              call_id: tc[:id],
              function_name: tc[:name],
              function_args: JSON.parse(tc[:arguments])
            )
          rescue JSON::ParserError => e
            Rails.logger.error "Failed to parse function arguments: #{tc[:arguments]} - #{e.message}"
            nil
          end.compact

          # Return constructed ChatResponse
          final_response = Provider::LlmConcept::ChatResponse.new(
            id: "stream-#{SecureRandom.uuid}",
            model: model,
            messages: [
              Provider::LlmConcept::ChatMessage.new(
                id: "msg-#{SecureRandom.uuid}",
                output_text: full_content
              )
            ],
            function_requests: function_requests
          )

          # CRITICAL: Emit the final response to the streamer so the Responder knows the stream is done
          # and can trigger tool execution or final update.
          streamer.call(
            Provider::LlmConcept::ChatStreamChunk.new(
              type: "response",
              data: final_response
            )
          )

          final_response
        else
          ChatParser.new(raw_response).parsed
        end
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
