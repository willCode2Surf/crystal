#!/usr/bin/env bin/crystal -run
require "spec"

describe "String" do
  describe "[]" do
    it "gets with positive index" do
      "hello!"[1].should eq('e')
    end

    it "gets with negative index" do
      "hello!"[-1].should eq('!')
    end

    it "gets with inclusive range" do
      "hello!"[1 .. 4].should eq("ello")
    end

    it "gets with inclusive range with negative indices" do
      "hello!"[-5 .. -2].should eq("ello")
    end

    it "gets with exclusive range" do
      "hello!"[1 ... 4].should eq("ell")
    end

    it "gets with start and count" do
      "hello"[1, 3].should eq("ell")
    end
  end

  it "does to_i" do
    "1234".to_i.should eq(1234)
  end

  it "does to_f" do
    "1234.56".to_f.should eq(1234.56f)
  end

  it "does to_d" do
    "1234.56".to_d.should eq(1234.56)
  end

  it "compares strings: different length" do
    "foo".should_not eq("fo")
  end

  it "compares strings: same object" do
    f = "foo"
    f.should eq(f)
  end

  it "compares strings: same length, same string" do
    "foo".should eq("fo" + "o")
  end

  it "compares strings: same length, different string" do
    "foo".should_not eq("bar")
  end

  it "interpolates string" do
    foo = "<foo>"
    bar = 123
    "foo #{bar}".should eq("foo 123")
    "foo #{ bar}".should eq("foo 123")
    "#{foo} bar".should eq("<foo> bar")
  end

  it "multiplies" do
    str = "foo"
    (str * 0).should eq("")
    (str * 3).should eq("foofoofoo")
  end

  describe "downcase" do
    assert { "HELLO!".downcase.should eq("hello!") }
    assert { "HELLO MAN!".downcase.should eq("hello man!") }
  end

  describe "upcase" do
    assert { "hello!".upcase.should eq("HELLO!") }
    assert { "hello man!".upcase.should eq("HELLO MAN!") }
  end

  describe "capitalize" do
    assert { "HELLO!".capitalize.should eq("Hello!") }
    assert { "HELLO MAN!".capitalize.should eq("Hello man!") }
    assert { "".capitalize.should eq("") }
  end

  describe "chomp" do
    assert { "hello\n".chomp.should eq("hello") }
    assert { "hello\r".chomp.should eq("hello") }
    assert { "hello\r\n".chomp.should eq("hello") }
    assert { "hello".chomp.should eq("hello") }
  end

  describe "strip" do
    assert { "  hello  \n\t\f\v\r".strip.should eq("hello") }
    assert { "hello".strip.should eq("hello") }
  end

  describe "rstrip" do
    assert { "  hello  ".rstrip.should eq("  hello") }
    assert { "hello".rstrip.should eq("hello") }
  end

  describe "lstrip" do
    assert { "  hello  ".lstrip.should eq("hello  ") }
    assert { "hello".lstrip.should eq("hello") }
  end

  describe "empty?" do
    assert { "a".empty?.should be_false }
    assert { "".empty?.should be_true }
  end

  describe "index" do
    describe "by char" do
      assert { "foo".index('o').should eq(1) }
      assert { "foo".index('g').should eq(-1) }

      describe "with offset" do
        assert { "foobarbaz".index('a', 5).should eq(7) }
        assert { "foobarbaz".index('a', -4).should eq(7) }
        assert { "foo".index('g', 1).should eq(-1) }
      end
    end

    describe "by string" do
      assert { "foo bar".index("o b").should eq(2) }
      assert { "foo".index("fg").should eq(-1) }
      assert { "foo".index("").should eq(0) }

      describe "with offset" do
        assert { "foobarbaz".index("ba", 4).should eq(6) }
        assert { "foobarbaz".index("ba", -5).should eq(6) }
        assert { "foo".index("ba", 1).should eq(-1) }
      end
    end
  end

  describe "includes?" do
    describe "by char" do
      assert { "foo".includes?('o').should be_true }
      assert { "foo".includes?('g').should be_false }
    end

    describe "by string" do
      assert { "foo bar".includes?("o b").should be_true }
      assert { "foo".includes?("fg").should be_false }
      assert { "foo".includes?("").should be_true }
    end
  end

  describe "split" do
    describe "by char" do
      assert { "foo,bar,,baz,".split(',').should eq(["foo", "bar", "", "baz"]) }
      assert { "foo,bar,,baz".split(',').should eq(["foo", "bar", "", "baz"]) }
      assert { "foo".split(',').should eq(["foo"]) }
    end

    describe "by string" do
      assert { "foo:-bar:-:-baz:-".split(":-").should eq(["foo", "bar", "", "baz"]) }
      assert { "foo:-bar:-:-baz".split(":-").should eq(["foo", "bar", "", "baz"]) }
      assert { "foo".split(":-").should eq(["foo"]) }
      assert { "foo".split("").should eq(["f", "o", "o"]) }
    end
  end

  describe "starts_with?" do
    assert { "foobar".starts_with?("foo").should be_true }
    assert { "foobar".starts_with?("").should be_true }
    assert { "foobar".starts_with?("foobarbaz").should be_false }
    assert { "foobar".starts_with?("foox").should be_false }
  end

  describe "ends_with?" do
    assert { "foobar".ends_with?("bar").should be_true }
    assert { "foobar".ends_with?("").should be_true }
    assert { "foobar".ends_with?("foobarbaz").should be_false }
    assert { "foobar".ends_with?("xbar").should be_false }
  end
end