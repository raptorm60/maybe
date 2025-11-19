require "test_helper"

class Provider::RegistryTest < ActiveSupport::TestCase
  test "finnhub configured with ENV" do
    Setting.stubs(:finnhub_api_key).returns(nil)

    with_env_overrides FINNHUB_API_KEY: "123" do
      assert_instance_of Provider::Finnhub, Provider::Registry.get_provider(:finnhub)
    end
  end

  test "finnhub configured with Setting" do
    Setting.stubs(:finnhub_api_key).returns("123")

    with_env_overrides FINNHUB_API_KEY: nil do
      assert_instance_of Provider::Finnhub, Provider::Registry.get_provider(:finnhub)
    end
  end

  test "finnhub not configured" do
    Setting.stubs(:finnhub_api_key).returns(nil)

    with_env_overrides FINNHUB_API_KEY: nil do
      assert_nil Provider::Registry.get_provider(:finnhub)
    end
  end
end
