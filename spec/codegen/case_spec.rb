require 'spec_helper'

describe 'Code gen: case' do
  it "codegens case with one condition" do
    run('require "object"; case 1; when 1; 2; else; 3; end').to_i.should eq(2)
  end

  it "codegens case with two conditions" do
    run('require "object"; case 1; when 0, 1; 2; else; 3; end').to_i.should eq(2)
  end

  it "codegens case with else" do
    run('require "object"; case 1; when 0; 2; else; 3; end').to_i.should eq(3)
  end

  it "codegens case that always returns" do
    run(%q(
      require "object"
      def foo
        if true
          case 0
          when 1; return 2
          else return 3
          end
        end
        4
      end

      foo
    )).to_i.should eq(3)
  end

  it "codegens case when cond is a call" do
    run(%q(
      require "object"

      $a = 0

      def foo
        $a += 1
      end

      case foo
      when 2
        1
      when 1
        2
      else
        3
      end
    )).to_i.should eq(2)
  end
end
