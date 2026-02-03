provider = Provider::Registry.new(:securities).providers.first
puts "Provider: #{provider.class.name}"

if provider.nil?
  puts "ERROR: Provider is nil. Check registry and environment variables."
  exit 1
end

key = ENV["FINNHUB_API_KEY"] || Setting.finnhub_api_key
puts "API Key present? #{key.present? ? 'Yes' : 'No'}"
puts "API Key: #{key.inspect}" if key.present?

puts "\n--- Connectivity Test ---"
begin
  if provider.respond_to?(:healthy?)
    puts "Healthy? #{provider.healthy?}" 
  else
    puts "Provider check skipped (no healthy? method)"
  end
rescue => e
  puts "Health check FAILED: #{e.message}"
end

puts "\n--- Search Test (AAPL) ---"
results = Security.search_provider("AAPL")
puts "Results count: #{results.size}"
results.each do |r|
  puts "- #{r.ticker}: #{r.name} (MIC: #{r.exchange_operating_mic})"
end

puts "\n--- Profile Test (AAPL) ---"
begin
  info = provider.fetch_security_info(symbol: "AAPL", exchange_operating_mic: "XNAS")
  if info.success?
    puts "Info: #{info.data.inspect}"
  else
    puts "Info API Failed: #{info.error.message}"
  end
rescue => e
  puts "Info Fetch Error: #{e.message}"
end
