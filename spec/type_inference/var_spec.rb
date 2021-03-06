require 'spec_helper'

describe 'Type inference: var' do
  it "types an assign" do
    input = Assign.new('a'.var, 1.int)
    mod = infer_type input
    input.target.type.should eq(mod.int)
    input.value.type.should eq(mod.int)
    input.type.should eq(mod.int)
  end

  it "types a variable" do
    input = parse 'a = 1; a'
    mod = infer_type input

    input.last.type.should eq(mod.int)
    input.type.should eq(mod.int)
  end

  it "types a variable that gets a new type" do
    assert_type('a = 1; a; a = 2.3; a') { UnionType.new(int, double) }
  end
end