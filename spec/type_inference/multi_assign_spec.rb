require 'spec_helper'

describe 'Type inference: multi assign' do
  it "types multi assign first exp" do
    assert_type("a, b = 1, 1.5; a") { int }
  end

  it "types multi assign second exp" do
    assert_type("a, b = 1, 1.5; b") { double }
  end

  it "types multi assign as nil" do
    assert_type("a, b = 1, 1.5") { self.nil }
  end
end
