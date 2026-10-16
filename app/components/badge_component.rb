class BadgeComponent < ApplicationComponent
  VARIANTS = {
    "default" => "bg-white/10 text-lagom-text",
    "success" => "bg-emerald-500/20 text-emerald-200",
    "warning" => "bg-amber-500/20 text-amber-200",
    "danger" => "bg-rose-500/20 text-rose-200",
    "accent" => "bg-lagom-accent/20 text-lagom-accent"
  }.freeze

  def initialize(text:, variant: "default")
    @text = text
    @variant = variant
  end

  def call
    content_tag(
      :span,
      @text,
      class: "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium #{VARIANTS.fetch(@variant)}"
    )
  end
end
