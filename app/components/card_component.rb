class CardComponent < ApplicationComponent
  def initialize(title: nil)
    @title = title
  end

  def call
    content_tag(:section, class: "rounded-2xl border border-white/10 bg-lagom-surface p-6 shadow-xl shadow-black/20") do
      safe_join([
        (@title.present? ? content_tag(:h2, @title, class: "mb-4 text-lg font-semibold text-lagom-text") : nil),
        content
      ].compact)
    end
  end
end
