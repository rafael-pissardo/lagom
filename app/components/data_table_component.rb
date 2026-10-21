class DataTableComponent < ApplicationComponent
  def initialize(headers:, sorts: nil, sort: nil, marked: [])
    @headers = headers
    @sorts = sorts
    @sort = sort
    @marked = marked
  end

  def call
    content_tag(:div, class: "overflow-x-auto rounded-xl border border-white/10") do
      content_tag(:table, class: "min-w-full divide-y divide-white/10 text-sm") do
        safe_join([
          content_tag(:thead, class: "bg-white/5") { content_tag(:tr) { header_cells } },
          content_tag(:tbody, content, class: "divide-y divide-white/10")
        ])
      end
    end
  end

  private

  def header_cells
    safe_join(@headers.each_with_index.map { |header, index| header_cell(header, @sorts&.at(index)) })
  end

  def header_cell(label, column)
    classes = [ "px-4 py-3 text-left font-medium", marked?(column) ? "bg-lagom-accent/10 text-lagom-accent" : "text-white/60" ]
    content_tag(:th, class: classes) do
      if column.nil?
        label
      else
        safe_join([
          content_tag(:span, label, data: { sort_label: true }),
          content_tag(:span, class: "ml-2 inline-flex gap-2 text-xs") do
            safe_join([ direction_link(column, "asc"), direction_link(column, "desc") ])
          end
        ])
      end
    end
  end

  def marked?(column)
    column.present? && @marked.include?(column)
  end

  def direction_link(column, direction)
    active = @sort&.column == column && @sort.direction == direction
    helpers.link_to(
      t("tables.sort_#{direction}"),
      sort_url(column, direction),
      class: active ? "text-lagom-accent" : "text-white/35 hover:text-white",
      aria: { current: (active ? "true" : nil), label: t("tables.sort_#{direction}_label") },
      data: {
        sort: column,
        direction: direction,
        turbo_frame: "results",
        turbo_action: "advance"
      }
    )
  end

  def sort_url(column, direction)
    query = helpers.request.query_parameters.except("page", "sort", "direction")
    helpers.url_for(query.merge("sort" => column, "direction" => direction))
  end
end
