require "rails_helper"

RSpec.describe UuidHelper, type: :helper do
  it "accepts a hyphenated uuid" do
    expect(helper.uuid?("86312006-4d7e-45c4-9c28-788f4aa68a62")).to be true
  end

  it "rejects a blank value, a compact uuid, and a urn" do
    expect(helper.uuid?(nil)).to be false
    expect(helper.uuid?("")).to be false
    expect(helper.uuid?("863120064d7e45c49c28788f4aa68a62")).to be false
    expect(helper.uuid?("urn:uuid:86312006-4d7e-45c4-9c28-788f4aa68a62")).to be false
  end
end
