class MoneyComponent < ApplicationComponent
  def initialize(cents:)
    @cents = cents
  end

  def call
    content_tag(:span, Finance::Amount.format_euros(@cents), class: "font-mono tabular-nums")
  end
end
