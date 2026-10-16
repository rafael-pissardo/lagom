class DataTableComponent < ApplicationComponent
  def initialize(headers:)
    @headers = headers
  end

  def call
    content_tag(:div, class: "overflow-x-auto rounded-xl border border-white/10") do
      content_tag(:table, class: "min-w-full divide-y divide-white/10 text-sm") do
        safe_join([
          content_tag(:thead, class: "bg-white/5") do
            content_tag(:tr) do
              safe_join(@headers.map { |header| content_tag(:th, header, class: "px-4 py-3 text-left font-medium text-white/60") })
            end
          end,
          content_tag(:tbody, content, class: "divide-y divide-white/10")
        ])
      end
    end
  end
end
