# frozen_string_literal: true

RSpec.describe Muze do
  describe "::VERSION" do
    it "has a version number" do
      expect(Muze::VERSION).not_to be_nil
    end
  end

  describe "RAF alias" do
    it "exposes Muze via RAF" do
      expect(RAF).to equal(Muze)
    end
  end
end
