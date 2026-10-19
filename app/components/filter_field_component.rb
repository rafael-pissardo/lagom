class FilterFieldComponent < ApplicationComponent
  INPUT_CLASSES = "w-full rounded-lg border border-white/10 bg-lagom-bg px-3 py-2 text-sm text-lagom-text outline-none ring-lagom-accent scheme-dark focus:ring-2".freeze

  def initialize(name:, label:, value: nil, type: :search, options: [])
    @name = name
    @label = label
    @value = value
    @type = type
    @options = options
  end

  def call
    content_tag(:label, class: "block space-y-1 text-sm text-white/70") do
      safe_join([ content_tag(:span, @label), input ])
    end
  end

  private

  def input
    case @type
    when :date
      date_field_tag @name, @value, class: INPUT_CLASSES, data: { action: "change->live-filter#submit" }
    when :month
      month_field_tag @name, @value, class: INPUT_CLASSES, data: { action: "change->live-filter#submit" }
    when :select
      select_tag @name,
        options_for_select(@options, @value),
        include_blank: t("filters.all"),
        class: INPUT_CLASSES,
        data: { action: "change->live-filter#submit" }
    else
      search_field_tag @name, @value, class: INPUT_CLASSES, autocomplete: "off", data: { action: "input->live-filter#search" }
    end
  end
end
