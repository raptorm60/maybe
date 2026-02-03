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
    
    if content.present?
      Chunk.new(type: "output_text", data: content)
    elsif choice["finish_reason"].present?
      # Capture the full response object when finished if needed
      # But for streaming, we mainly care about content chunks
      # The main ChatParser handles the full response object if we reconstruct it
      # For now, just return nil or handle completion if needed by the consumer
      nil 
    end
  end

  private
    attr_reader :object

    Chunk = Provider::LlmConcept::ChatStreamChunk
end
