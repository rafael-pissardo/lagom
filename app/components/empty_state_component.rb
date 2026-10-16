class EmptyStateComponent < ApplicationComponent
  def initialize(message:)
    @message = message
  end

  def call
    content_tag(:div, @message, class: "rounded-xl border border-dashed border-white/15 bg-white/5 px-6 py-10 text-center text-sm text-white/60")
  end
end
