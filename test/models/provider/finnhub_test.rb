require "test_helper"
require "ostruct"

class Provider::FinnhubTest < ActiveSupport::TestCase
  include ExchangeRateProviderInterfaceTest, SecurityProviderInterfaceTest

  setup do
    @subject = @finnhub = Provider::Finnhub.new(ENV["FINNHUB_API_KEY"])
  end

  test "health check" do
    VCR.use_cassette("finnhub/health") do
      assert @finnhub.healthy?
    end
  end

  test "usage info" do
    VCR.use_cassette("finnhub/usage") do
      usage = @finnhub.usage.data
      assert usage.used.present?
      assert usage.limit.present?
      assert usage.utilization.present?
    end
  end
end
