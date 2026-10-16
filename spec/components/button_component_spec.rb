require "rails_helper"

RSpec.describe ButtonComponent, type: :component do
  it "renders a link button" do
    render_inline(described_class.new(text: "Open", href: "/merchants", variant: "secondary"))

    expect(page).to have_link("Open", href: "/merchants")
  end

  it "renders a submit button" do
    render_inline(described_class.new(text: "Save", type: "submit", variant: "primary"))

    expect(page).to have_button("Save")
  end
end
