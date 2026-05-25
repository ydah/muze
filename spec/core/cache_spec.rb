# frozen_string_literal: true

RSpec.describe Muze::Core::BoundedCache do
  it "reuses cached values and evicts the oldest entry" do
    cache = described_class.new(max_size: 2)
    builds = 0

    expect(cache.fetch(:a) { builds += 1 }).to eq(1)
    expect(cache.fetch(:a) { builds += 1 }).to eq(1)
    expect(cache.fetch(:b) { builds += 1 }).to eq(2)
    expect(cache.fetch(:c) { builds += 1 }).to eq(3)

    expect(cache.size).to eq(2)
    expect(cache.fetch(:a) { builds += 1 }).to eq(4)
  end

  it "rejects invalid cache sizes" do
    expect do
      described_class.new(max_size: 0)
    end.to raise_error(Muze::ParameterError, /max_size/)
  end
end
