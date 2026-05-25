# frozen_string_literal: true

RSpec.describe Muze::Feature do
  let(:sr) { 22_050 }

  def sine(freq, duration: 1.0)
    sample_count = (sr * duration).to_i
    Numo::SFloat.cast(
      Array.new(sample_count) { |index| Math.sin((2.0 * Math::PI * freq * index) / sr) }
    )
  end

  describe "spectral features" do
    it "estimates centroid around sine frequency" do
      centroid = described_class.spectral_centroid(y: sine(440.0), sr:, n_fft: 1024, hop_length: 256)
      mean_centroid = centroid.mean

      expect(mean_centroid).to be_within(80.0).of(440.0)
    end

    it "returns high flatness for white noise" do
      noise = Numo::SFloat.new(sr).rand(-1.0, 1.0)
      flatness = described_class.spectral_flatness(y: noise, n_fft: 1024, hop_length: 256)

      expect(flatness.mean).to be > 0.5
    end

    it "zero crossing rate increases with frequency" do
      low = described_class.zero_crossing_rate(sine(220.0), frame_length: 1024, hop_length: 256).mean
      high = described_class.zero_crossing_rate(sine(880.0), frame_length: 1024, hop_length: 256).mean

      expect(high).to be > low
    end

    it "returns RMS with frame dimension" do
      values = described_class.rms(y: sine(440.0), frame_length: 1024, hop_length: 256)

      expect(values.shape[0]).to eq(1)
      expect(values.shape[1]).to be > 0
    end

    it "returns zero crossing rate with frame dimension" do
      values = described_class.zero_crossing_rate(sine(440.0), frame_length: 1024, hop_length: 256)

      expect(values.shape[0]).to eq(1)
      expect(values.shape[1]).to be > 0
    end

    it "rejects invalid time-domain feature input" do
      expect do
        described_class.rms(y: nil)
      end.to raise_error(Muze::ParameterError, /audio/)

      expect do
        described_class.zero_crossing_rate([[0.0, 1.0], [0.5, 0.5]])
      end.to raise_error(Muze::ParameterError, /mono/)
    end

    it "validates spectral parameters" do
      expect { described_class.spectral_rolloff(y: sine(440.0), roll_percent: 1.0) }.to raise_error(Muze::ParameterError)
      expect { described_class.spectral_bandwidth(y: sine(440.0), p: 0) }.to raise_error(Muze::ParameterError)
      expect { described_class.spectral_flatness(y: sine(440.0), amin: 0.0) }.to raise_error(Muze::ParameterError)
      expect { described_class.spectral_contrast(y: sine(440.0), quantile: 0.5) }.to raise_error(Muze::ParameterError)
    end

    it "computes additional spectral descriptors" do
      descriptors = [
        described_class.spectral_flux(y: sine(440.0), sr:, n_fft: 1024, hop_length: 256),
        described_class.spectral_entropy(y: sine(440.0), sr:, n_fft: 1024, hop_length: 256),
        described_class.spectral_crest(y: sine(440.0), sr:, n_fft: 1024, hop_length: 256),
        described_class.spectral_slope(y: sine(440.0), sr:, n_fft: 1024, hop_length: 256),
        described_class.spectral_decrease(y: sine(440.0), sr:, n_fft: 1024, hop_length: 256)
      ]

      expect(descriptors.all? { |descriptor| descriptor.shape[0] == 1 && descriptor.shape[1].positive? }).to be(true)
    end

    it "accepts power spectrogram input explicitly" do
      magnitude, = Muze.magphase(Muze.stft(sine(440.0), n_fft: 1024, hop_length: 256))
      power = magnitude**2
      centroid = described_class.spectral_centroid(s: power, s_kind: :power, sr:, n_fft: 1024, hop_length: 256)

      expect(centroid.shape[0]).to eq(1)
      expect(centroid.shape[1]).to eq(power.shape[1])
    end

    it "computes spectral polynomial features" do
      features = described_class.poly_features(y: sine(440.0), sr:, n_fft: 1024, hop_length: 256, order: 2)

      expect(features.shape[0]).to eq(3)
      expect(features.shape[1]).to be > 0
    end

    it "rejects NaN and negative power spectrogram input" do
      expect do
        described_class.spectral_centroid(s: Numo::SFloat[Float::NAN], sr:, n_fft: 0)
      end.to raise_error(Muze::ParameterError, /finite/)

      expect do
        described_class.spectral_centroid(s: Numo::SFloat[-1.0], s_kind: :power, sr:, n_fft: 0)
      end.to raise_error(Muze::ParameterError, /non-negative/)
    end
  end

  describe ".context" do
    it "extracts multiple features through a shared context" do
      result = described_class.extract(y: sine(440.0), sr:, features: %i[melspectrogram chroma_stft spectral_centroid tonnetz], n_fft: 1024, hop_length: 256)

      expect(result.keys).to contain_exactly(:melspectrogram, :chroma_stft, :spectral_centroid, :tonnetz)
      expect(result.fetch(:tonnetz).shape[0]).to eq(6)
    end

    it "exposes a public feature_stack convenience alias" do
      result = Muze.feature_stack(y: sine(440.0), sr:, features: %i[spectral_centroid rms], n_fft: 1024, hop_length: 256)

      expect(result.keys).to contain_exactly(:spectral_centroid, :rms)
    end
  end

  describe ".beat_sync" do
    it "aggregates frame features between beat boundaries" do
      data = Numo::SFloat.cast([[1.0, 3.0, 10.0, 14.0], [2.0, 4.0, 6.0, 8.0]])
      synced = described_class.beat_sync(data, beats: [2], aggregate: :mean)

      expect(synced.shape).to eq([2, 2])
      expect(synced[0, 0]).to eq(2.0)
      expect(synced[0, 1]).to eq(12.0)
    end

    it "supports median aggregation through the public API" do
      synced = Muze.beat_sync([1.0, 5.0, 3.0, 9.0], beats: [3], aggregate: :median)

      expect(synced.shape).to eq([1, 2])
      expect(synced[0, 0]).to eq(3.0)
    end
  end
end
