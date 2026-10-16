class ButtonComponent < ApplicationComponent
  VARIANTS = {
    "primary" => "bg-lagom-accent text-lagom-bg hover:bg-[#b8a8f5]",
    "secondary" => "bg-white/10 text-lagom-text hover:bg-white/15",
    "danger" => "bg-rose-500/90 text-white hover:bg-rose-500"
  }.freeze

  def initialize(text:, href: nil, type: "button", variant: "primary", method: nil, **options)
    @text = text
    @href = href
    @type = type
    @variant = variant
    @method = method
    @options = options
  end

  def call
    classes = "inline-flex items-center justify-center rounded-lg px-4 py-2 text-sm font-medium transition #{VARIANTS.fetch(@variant)}"

    if @href
      helpers.link_to @text, @href, class: classes, method: @method, **@options
    else
      content_tag(:button, @text, type: @type, class: classes, **@options)
    end
  end
end
