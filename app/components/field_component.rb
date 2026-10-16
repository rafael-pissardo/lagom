class FieldComponent < ApplicationComponent
  def initialize(form:, attribute:, label:, type: :text_field)
    @form = form
    @attribute = attribute
    @label = label
    @type = type
  end

  def call
    error = @form.object.errors[@attribute].first

    content_tag(:div, class: "space-y-2") do
      safe_join([
        @form.label(@attribute, @label, class: "block text-sm text-white/70"),
        input_tag,
        (error.present? ? content_tag(:p, error, class: "text-sm text-rose-300") : nil)
      ].compact)
    end
  end

  private

  def input_tag
    classes = "w-full rounded-lg border border-white/10 bg-lagom-bg px-3 py-2 text-sm text-lagom-text outline-none ring-lagom-accent focus:ring-2"

    case @type
    when :password_field
      @form.password_field(@attribute, class: classes, autocomplete: "current-password")
    when :email_field
      @form.email_field(@attribute, class: classes, autocomplete: "username")
    when :file_field
      @form.file_field(@attribute, class: "#{classes} file:mr-4 file:rounded-md file:border-0 file:bg-lagom-accent file:px-3 file:py-1.5 file:text-sm file:font-medium file:text-lagom-bg")
    else
      @form.text_field(@attribute, class: classes)
    end
  end
end
