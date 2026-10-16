class PageHeaderComponent < ApplicationComponent
  def initialize(title:, subtitle: nil)
    @title = title
    @subtitle = subtitle
  end

  def call
    content_tag(:header, class: "mb-8 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between") do
      safe_join([
        content_tag(:div) do
          safe_join([
            content_tag(:h1, @title, class: "text-3xl font-semibold tracking-tight text-lagom-text"),
            (@subtitle.present? ? content_tag(:p, @subtitle, class: "mt-2 text-sm text-white/60") : nil)
          ].compact)
        end,
        content
      ])
    end
  end
end
