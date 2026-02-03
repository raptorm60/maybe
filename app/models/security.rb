class Security < ApplicationRecord
  include Provided
  alias_attribute :symbol, :ticker

  before_validation :upcase_symbols

  has_many :trades, dependent: :nullify, class_name: "Trade"
  has_many :prices, dependent: :destroy

  validates :ticker, presence: true
  validates :ticker, uniqueness: { scope: :exchange_operating_mic, case_sensitive: false }

  scope :online, -> { where(offline: false) }

  def current_price
    @current_price ||= find_or_fetch_price
    return nil if @current_price.nil?
    Money.new(@current_price.price, @current_price.currency)
  end

  def to_combobox_option
    # TODO: Implement replacement for SynthComboboxOption or use generic
    OpenStruct.new(
      id:ticker, 
      display: "#{ticker} - #{name} (#{exchange_operating_mic})"
    )
  end

  private
    def upcase_symbols
      self.ticker = ticker.upcase
      self.exchange_operating_mic = exchange_operating_mic.upcase if exchange_operating_mic.present?
    end
end
