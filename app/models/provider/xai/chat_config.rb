class Provider::Xai::ChatConfig
  def initialize(functions: [], function_results: [])
    @functions = functions
    @function_results = function_results
  end

  def tools
    functions.map do |fn|
      {
        type: "function",
        function: {
          name: fn[:name],
          description: fn[:description],
          parameters: fn[:params_schema]
          # strict: fn[:strict] # Temporarily disable strict mode to ensure compatibility
        }
      }
    end
  end

  def build_input(prompt)
    messages = [{ role: "user", content: prompt }]

    if function_results.any?
      # Reconstruct the assistant's tool call message
      tool_calls = function_results.map do |res|
        {
          id: res[:call_id],
          type: "function",
          function: {
            name: res[:function_name],
            arguments: res[:function_arguments].to_json
          }
        }
      end

      messages << {
        role: "assistant",
        content: nil,
        tool_calls: tool_calls
      }

      # Append the tool results
      function_results.each do |fn_result|
        messages << {
          role: "tool",
          tool_call_id: fn_result[:call_id],
          content: fn_result[:output].to_json
        }
      end
    end

    messages
  end

  private
    attr_reader :functions, :function_results
end
