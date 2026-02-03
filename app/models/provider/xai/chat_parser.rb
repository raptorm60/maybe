class Provider::Xai::ChatParser
  def initialize(object)
    @object = object
  end

  def parsed
    # Debug log for standard response parsing
    Rails.logger.info "[ChatParser] Raw Object: #{object.inspect}"

    # Handle standard OpenAI response
    ChatResponse.new(
      id: object["id"],
      model: object["model"],
      messages: parse_messages,
      function_requests: parse_function_requests
    )
  end

  private
    attr_reader :object

    # Use classes from LlmConcept
    ChatResponse = Provider::LlmConcept::ChatResponse
    ChatMessage = Provider::LlmConcept::ChatMessage
    ChatFunctionRequest = Provider::LlmConcept::ChatFunctionRequest

    def parse_messages
      # Extract content from choices
      # OpenAI format: { choices: [ { message: { content: ".." } } ] }
      choice = object.dig("choices", 0, "message")
      return [] unless choice

      content = choice["content"]
      return [] unless content.present?

      [
        ChatMessage.new(
          id: object["id"], # Use response ID as message ID since message object doesn't have one
          output_text: content
        )
      ]
    end

    def parse_function_requests
      choice = object.dig("choices", 0, "message")
      return [] unless choice

      # OpenAI format: { tool_calls: [ { function: { name: "..", arguments: ".." } } ] }
      tool_calls = choice["tool_calls"] || []
      
      tool_calls.map do |tool_call|
        ChatFunctionRequest.new(
          id: tool_call["id"],
          call_id: tool_call["id"],
          function_name: tool_call.dig("function", "name"),
          function_args: JSON.parse(tool_call.dig("function", "arguments"))
        )
      end
    end
end
