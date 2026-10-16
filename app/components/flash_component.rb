class FlashComponent < ApplicationComponent
  def initialize(type:, message:)
    @type = type.to_s
    @message = message
  end

  def call
    return if @message.blank?

    role = @type == "alert" ? "alert" : "status"
    tone = @type == "alert" ? "border-rose-400/40 bg-rose-500/10 text-rose-100" : "border-emerald-400/40 bg-emerald-500/10 text-emerald-100"

    content_tag(:div, @message, role: role, class: "mb-6 rounded-xl border px-4 py-3 text-sm #{tone}")
  end
end
