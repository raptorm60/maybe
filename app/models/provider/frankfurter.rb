class Provider::Frankfurter < Provider
  include ExchangeRateConcept

  # Subclass so errors caught in this provider are raised as Provider::Frankfurter::Error
  Error = Class.new(Provider::Error)

  def initialize
  end

  def healthy?
    with_provider_response do
      response = client.get("/v1/latest")
      response.success?
    end
  end

  # ================================
  #          Exchange Rates
  # ================================

  def fetch_exchange_rate(from:, to:, date:)
    with_provider_response do
      # Frankfurter defaults to latest if date is today/future, or specific date
      endpoint = date >= Date.current ? "/v1/latest" : "/v1/#{date.to_s}"
      
      response = client.get(endpoint) do |req|
        req.params["base"] = from
        req.params["symbols"] = to
      end

      data = JSON.parse(response.body)
      
      # Frankfurter returns { "amount": 1.0, "base": "USD", "date": "2023-01-01", "rates": { "EUR": 0.9 } }
      rate_value = data.dig("rates", to)

      if rate_value.nil?
        Rails.logger.warn("#{self.class.name} returned no rate for #{from}/#{to} on #{date}")
        return Rate.new(date: date.to_date, from:, to:, rate: nil)
      end

      returned_date = data["date"].to_date
      
      Rate.new(date: returned_date, from:, to:, rate: rate_value.to_f)
    end
  end

  def fetch_exchange_rates(from:, to:, start_date:, end_date:)
    with_provider_response do
      # Frankfurter Time Series: /v1/2020-01-01..2020-01-31
      endpoint = "/v1/#{start_date.to_s}..#{end_date.to_s}"
      
      response = client.get(endpoint) do |req|
        req.params["base"] = from
        req.params["symbols"] = to
      end

      data = JSON.parse(response.body)
      rates_hash = data.dig("rates") || {}

      # Format: { "2020-01-01": { "EUR": 0.9 }, "2020-01-02": { "EUR": 0.91 } }
      rates_hash.map do |date_str, rates|
        val = rates[to]
        next unless val

        Rate.new(date: date_str.to_date, from:, to:, rate: val.to_f)
      end.compact
    end
  end

  private

    def base_url
      ENV["FRANKFURTER_URL"] || "https://api.frankfurter.dev"
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
