class StatComponent < ApplicationComponent
  def initialize(label:, value:)
    @label = label
    @value = value
  end

  def call
    content_tag(:div, class: "rounded-xl border border-white/10 bg-white/5 p-4") do
      safe_join([
        content_tag(:p, @label, class: "text-xs uppercase tracking-wide text-white/50"),
        content_tag(:p, @value, class: "mt-2 text-xl font-semibold text-lagom-text")
      ])
    end
  end
end
