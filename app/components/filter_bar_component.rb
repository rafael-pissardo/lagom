class FilterBarComponent < ApplicationComponent
  def initialize(url:)
    @url = url
  end

  def call
    content_tag(
      :form,
      safe_join([ sort_fields, content ]),
      method: "get",
      action: @url,
      role: "search",
      class: "mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4",
      data: { controller: "live-filter", turbo_frame: "results", turbo_action: "advance" }
    )
  end

  private

  def sort_fields
    safe_join(%w[sort direction].filter_map { |name|
      value = helpers.params[name]
      helpers.hidden_field_tag(name, value) if value.present?
    })
  end
end
