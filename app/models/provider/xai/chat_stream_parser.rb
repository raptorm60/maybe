class Provider::Xai::ChatStreamParser
  def initialize(object)
    @object = object
  end

  def parsed
    # Handle standard OpenAI streaming chunk
    # Format: { choices: [ { delta: { content: ".." } } ] }
    
    choice = object.dig("choices", 0)
    return unless choice

    delta = choice["delta"]
    return unless delta

    content = delta["content"]
    tool_calls = delta["tool_calls"]
    
    if content.present?
      Chunk.new(type: "output_text", data: content)
    elsif tool_calls.present?
      # Pass the raw tool_calls array from the delta
      Chunk.new(type: "tool_call_chunk", data: tool_calls)
    elsif choice["finish_reason"].present?
      nil 
    end
  end

  private
    attr_reader :object

    Chunk = Provider::LlmConcept::ChatStreamChunk
end
