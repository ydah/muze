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

    it "changes beat selection when tightness is changed" do
      envelope = Array.new(220, 0.0)
      interval = 20
      start_frame = 10

      10.times do |index|
        anchor = start_frame + (index * interval)
        shifted = anchor + (index.even? ? 6 : -6)
        envelope[anchor] = 0.55
        envelope[shifted] = 1.0 if shifted.between?(0, envelope.length - 1)
      end

      _, loose_beats = described_class.beat_track(
        onset_envelope: envelope,
        sr:,
        hop_length:,
        start_bpm: 120.0,
        tightness: 10
      )
      _, strict_beats = described_class.beat_track(
        onset_envelope: envelope,
        sr:,
        hop_length:,
        start_bpm: 120.0,
        tightness: 400
      )

      expect(loose_beats).not_to eq(strict_beats)
    end

    it "supports fixed BPM and metadata return" do
      result = described_class.beat_track(y: metronome, sr:, hop_length:, bpm: 120.0, return_metadata: true)

      expect(result.fetch(:tempo)).to eq(120.0)
      expect(result.fetch(:confidence)).to be_between(0.0, 1.0)
    end

    it "returns nil tempo for silent envelopes" do
      tempo, beats = described_class.beat_track(onset_envelope: Array.new(32, 0.0), sr:, hop_length:)

      expect(tempo).to be_nil
      expect(beats).to eq([])
    end

    it "validates beat tracking controls and envelopes" do
      expect do
        described_class.beat_track(onset_envelope: [0.0, Float::NAN], sr:, hop_length:)
      end.to raise_error(Muze::ParameterError, /finite/)

      expect do
        described_class.beat_track(onset_envelope: [0.0, 1.0], sr:, hop_length:, min_bpm: 120.0, max_bpm: 60.0)
      end.to raise_error(Muze::ParameterError, /max_bpm/)
    end
  end

  describe ".tempo_frequencies" do
    it "maps tempogram lag to BPM" do
      frequencies = described_class.tempo_frequencies(sr:, hop_length:, win_length: 4)

      expect(frequencies[1]).to be_within(1.0e-6).of(60.0 * sr / hop_length)
    end
  end

  describe ".tempogram" do
    it "can compute normalized autocorrelation values" do
      tempo = described_class.tempogram(onset_envelope: [1.0, 0.0, 1.0, 0.0, 1.0], win_length: 4, normalize: true)

      expect(tempo.max).to be <= 1.0
      expect(tempo[2, 4]).to be_within(1.0e-6).of(1.0)
    end

    it "validates tempogram controls" do
      expect do
        described_class.tempogram(onset_envelope: [1.0], win_length: 0)
      end.to raise_error(Muze::ParameterError, /win_length/)
    end
  end
end
