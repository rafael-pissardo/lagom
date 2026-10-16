require "rails_helper"

RSpec.describe FieldComponent, type: :component do
  it "renders a labeled text field" do
    merchant = Merchant.new
    form = ActionView::Helpers::FormBuilder.new(:merchant, merchant, vc_test_controller.view_context, {})

    render_inline(described_class.new(form: form, attribute: :reference, label: "Reference"))

    expect(page).to have_css("label", text: "Reference")
    expect(page).to have_field("merchant[reference]")
  end
end
