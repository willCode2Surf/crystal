require "spec"
require "../../spec_helper"
require "../../../../bootstrap/crystal/parser"
require "../../../../bootstrap/crystal/type_inference"
require "../../../../bootstrap/crystal/to_s"

include Crystal

describe "Type inference: var" do
  it "types an assign" do
    input = parse "a = 1"
    if input.is_a?(Assign)
      mod = infer_type input
      input.target.type.should eq(mod.int)
      input.value.type.should eq(mod.int)
      input.type.should eq(mod.int)
    else
      fail "expected input to be an Assign"
    end
  end

  it "types a variable" do
    input = parse "a = 1; a"
    mod = infer_type input

    if input.is_a?(Expressions)
      input.last.type.should eq(mod.int)
      input.type.should eq(mod.int)
    else
      fail "expected input to be an Expressions"
    end
  end
end