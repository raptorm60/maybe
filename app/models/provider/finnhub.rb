class Provider::Finnhub < Provider
  include ExchangeRateConcept, SecurityConcept

  # Subclass so errors caught in this provider are raised as Provider::Finnhub::Error
  Error = Class.new(Provider::Error)
  InvalidExchangeRateError = Class.new(Error)
  InvalidSecurityPriceError = Class.new(Error)

  def initialize(api_key)
    @api_key = api_key
  end

  def healthy?
    with_provider_response do
      response = client.get("#{base_url}/api/v1/quote?symbol=AAPL&token=#{api_key}")
      data = JSON.parse(response.body)
      data["c"].present? # current price exists
    end
  end

  def usage
    with_provider_response do
      response = client.get("#{base_url}/api/v1/api-usage?token=#{api_key}")
      parsed = JSON.parse(response.body)

      used = parsed.dig("usage")
      limit = parsed.dig("limit")

      UsageData.new(
        used: used,
        limit: limit,
        utilization: used.to_f / limit * 100,
        plan: "free",
      )
    end
  end

  # ================================
  #          Exchange Rates
  # ================================

  def fetch_exchange_rate(from:, to:, date:)
    with_provider_response do
      # Finnhub doesn't have historical forex rates in their free tier
      # We'll use the current rate as fallback for historical dates
      # For better accuracy, consider using a dedicated forex API or upgrading Finnhub plan
      response = client.get("#{base_url}/api/v1/forex/rates?base=#{from}&token=#{api_key}")
      rates = JSON.parse(response.body)

      rate_value = rates.dig("quote", to)

      if rate_value.nil?
        Rails.logger.warn("#{self.class.name} could not find rate for #{from}/#{to}")
        Sentry.capture_exception(InvalidExchangeRateError.new("#{self.class.name} could not find exchange rate"), level: :warning) do |scope|
          scope.set_context("rate", { from: from, to: to, date: date })
        end
       
        return Rate.new(date: date.to_date, from:, to:, rate: nil)
      end

      Rate.new(date: date.to_date, from:, to:, rate: rate_value)
    end
  end

  def fetch_exchange_rates(from:, to:, start_date:, end_date:)
    with_provider_response do
      # Finnhub's free tier doesn't provide historical forex data
      # We'll fetch the current rate and replicate it for all dates as a workaround
      # For production use, consider using a dedicated forex API or upgrading
      
      response = client.get("#{base_url}/api/v1/forex/rates?base=#{from}&token=#{api_key}")
      rates_data = JSON.parse(response.body)

      rate_value = rates_data.dig("quote", to)

      if rate_value.nil?
        Rails.logger.warn("#{self.class.name} could not find rate for #{from}/#{to}")
        return []
      end

      # Generate rates for each date in the range using the current rate
      # This is a limitation of Finnhub's free tier
      results = []
      current_date = start_date
      while current_date <= end_date
        results << Rate.new(date: current_date.to_date, from:, to:, rate: rate_value)
        current_date += 1.day
      end

      results
    end
  end

  # ================================
  #           Securities
  # ================================

  def search_securities(symbol, country_code: nil, exchange_operating_mic: nil)
    with_provider_response do
      response = client.get("#{base_url}/api/v1/search?q=#{symbol}&token=#{api_key}")
      parsed = JSON.parse(response.body)

      results = parsed.dig("result") || []

      # Filter by country and exchange if provided
      results = results.select { |s| s["type"] == "Common Stock" }
      results = results.select { |s| country_code.nil? || s.dig("displaySymbol")&.include?(country_code) } if country_code

      results.take(25).map do |security|
        Security.new(
          symbol: security.dig("symbol"),
          name: security.dig("description"),
          logo_url: "https://finnhub.io/api/logo?symbol=#{security.dig('symbol')}",
          exchange_operating_mic: nil, # Finnhub doesn't provide MIC codes in search
          country_code: nil # Will need to fetch this separately if needed
        )
      end
    end
  end

  def fetch_security_info(symbol:, exchange_operating_mic:)
    with_provider_response do
      response = client.get("#{base_url}/api/v1/stock/profile2?symbol=#{symbol}&token=#{api_key}")
      data = JSON.parse(response.body)

      SecurityInfo.new(
        symbol: symbol,
        name: data.dig("name"),
        links: { "homepage_url" => data.dig("weburl") },
        logo_url: data.dig("logo"),
        description: data.dig("finnhubIndustry"),
        kind: data.dig("finnhubIndustry"),
        exchange_operating_mic: data.dig("exchange")
      )
    end
  end

  def fetch_security_price(symbol:, exchange_operating_mic: nil, date:)
    with_provider_response do
      historical_data = fetch_security_prices(symbol:, exchange_operating_mic:, start_date: date, end_date: date)

      raise Error, "No prices found for security #{symbol} on date #{date}" if historical_data.data.empty?

      historical_data.data.first
    end
  end

  def fetch_security_prices(symbol:, exchange_operating_mic: nil, start_date:, end_date:)
    with_provider_response do
      # Convert dates to Unix timestamps
      from_timestamp = start_date.to_time.to_i
      to_timestamp = end_date.to_time.to_i

      response = client.get("#{base_url}/api/v1/stock/candle") do |req|
        req.params["symbol"] = symbol
        req.params["resolution"] = "D" # Daily resolution
        req.params["from"] = from_timestamp
        req.params["to"] = to_timestamp
        req.params["token"] = api_key
      end

      data = JSON.parse(response.body)

      # Check if we have valid data
      if data["s"] != "ok" || data["c"].nil?
        Rails.logger.warn("#{self.class.name} returned no data for #{symbol}")
        return []
      end

      # Finnhub returns arrays of data: t (timestamps), c (close), o (open), h (high), l (low), v (volume)
      timestamps = data["t"] || []
      closes = data["c"] || []
      opens = data["o"] || []

      prices = []
      timestamps.each_with_index do |timestamp, index|
        date = Time.at(timestamp).to_date
        price = closes[index] || opens[index]

        if price.nil?
          Rails.logger.warn("#{self.class.name} returned invalid price data for security #{symbol} on: #{date}")
          Sentry.capture_exception(InvalidSecurityPriceError.new("#{self.class.name} returned invalid security price data"), level: :warning) do |scope|
            scope.set_context("security", { symbol: symbol, date: date })
          end

          next
        end

        prices << Price.new(
          symbol: symbol,
          date: date,
          price: price.to_f,
          currency: "USD", # Finnhub prices are in USD by default
          exchange_operating_mic: nil # Finnhub doesn't provide this in candles response
        )
      end

      prices
    end
  end

  private
    attr_reader :api_key

    def base_url
      ENV["FINNHUB_URL"] || "https://finnhub.io"
    end

    def client
      @client ||= Faraday.new(url: base_url) do |faraday|
        faraday.request(:retry, {
          max: 2,
          interval: 0.05,
          interval_randomness: 0.5,
          backoff_factor: 2
        })

        faraday.response :raise_error
      end
   end
end
