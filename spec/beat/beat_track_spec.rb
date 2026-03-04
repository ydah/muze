# frozen_string_literal: true

RSpec.describe Muze::Beat do
  let(:sr) { 22_050 }
  let(:hop_length) { 256 }
  let(:metronome) do
    duration = 10.0
    signal = Array.new((sr * duration).to_i, 0.0)
    beat_period = 0.5

    (0...(duration / beat_period).to_i).each do |beat|
      start = (beat * beat_period * sr).to_i
      100.times do |offset|
        index = start + offset
        break if index >= signal.length

        signal[index] = Math.exp(-offset / 20.0)
      end
    end

    Numo::SFloat.cast(signal)
  end

  describe ".beat_track" do
    it "estimates around 120 BPM for a metronome" do
      tempo, = described_class.beat_track(y: metronome, sr:, hop_length:)

      expect(tempo).to be_within(8.0).of(120.0)
    end

    it "returns beat positions aligned to estimated tempo" do
      tempo, beats = described_class.beat_track(y: metronome, sr:, hop_length:)
      intervals = beats.each_cons(2).map { |left, right| right - left }
      mean_interval = intervals.sum(0.0) / intervals.length
      expected_interval = 60.0 * sr / (tempo * hop_length)

      expect(mean_interval).to be_within(2.0).of(expected_interval)
    end
  end
end
