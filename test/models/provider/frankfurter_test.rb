require "test_helper"

class Provider::FrankfurterTest < ActiveSupport::TestCase
  setup do
    @provider = Provider::Frankfurter.new
  end

  test "fetches current exchange rate" do
    VCR.use_cassette("frankfurter/latest_usd_eur") do
      rate = @provider.fetch_exchange_rate(from: "USD", to: "EUR", date: Date.current)
      
      assert_equal "USD", rate.from
      assert_equal "EUR", rate.to
      assert_not_nil rate.rate
      assert rate.rate > 0
    end
  end

  test "fetches historical exchange rate" do
    date = Date.parse("2023-01-01")
    # 2023-01-01 was Sunday, Frankfurter might adjust date/not return, let's use 2023-01-04
    date = Date.parse("2023-01-04") 

    VCR.use_cassette("frankfurter/historical_usd_eur") do
      rate = @provider.fetch_exchange_rate(from: "USD", to: "EUR", date: date)
      
      assert_equal date, rate.date
      assert_equal 0.94, rate.rate.round(2)
    end
  end

  test "fetches time series exchange rates" do
    start_date = Date.parse("2023-01-01")
    end_date = Date.parse("2023-01-07")

    VCR.use_cassette("frankfurter/timeseries_usd_eur") do
      rates = @provider.fetch_exchange_rates(from: "USD", to: "EUR", start_date: start_date, end_date: end_date)
      
      assert_operator rates.length, :>, 0
      assert_equal "USD", rates.first.from
      assert_equal "EUR", rates.first.to
    end
  end

  test "handles missing rates gracefully" do
    VCR.use_cassette("frankfurter/missing_rate") do
      rate = @provider.fetch_exchange_rate(from: "USD", to: "XXX", date: Date.current)
      assert_nil rate.rate
    end
  end
end
