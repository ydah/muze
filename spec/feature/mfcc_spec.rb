# frozen_string_literal: true

RSpec.describe Muze::Feature do
  let(:sr) { 22_050 }
  let(:signal) do
    Numo::SFloat.cast(
      Array.new(sr) do |index|
        Math.sin((2.0 * Math::PI * 440.0 * index) / sr)
      end
    )
  end

  describe ".melspectrogram" do
    it "returns [n_mels, frames]" do
      mel = described_class.melspectrogram(y: signal, sr:, n_fft: 512, hop_length: 128, n_mels: 40)

      expect(mel.shape[0]).to eq(40)
      expect(mel.shape[1]).to be > 0
    end

    it "accepts magnitude spectrogram input explicitly" do
      magnitude, = Muze.magphase(Muze.stft(signal, n_fft: 512, hop_length: 128))
      mel = described_class.melspectrogram(sr:, s: magnitude, s_kind: :magnitude, n_fft: 512, hop_length: 128, n_mels: 40)

      expect(mel.shape[0]).to eq(40)
      expect(mel.shape[1]).to eq(magnitude.shape[1])
    end

    it "rejects negative precomputed spectrogram input" do
      expect do
        described_class.melspectrogram(sr:, s: Numo::SFloat[[-1.0]], n_fft: 512, n_mels: 8)
      end.to raise_error(Muze::ParameterError, /non-negative/)
    end
  end

  describe ".mfcc" do
    it "returns [n_mfcc, frames]" do
      coeffs = described_class.mfcc(y: signal, sr:, n_mfcc: 13, n_fft: 512, hop_length: 128, n_mels: 40)

      expect(coeffs.shape[0]).to eq(13)
      expect(coeffs.shape[1]).to be > 0
    end

    it "respects n_mfcc" do
      coeffs = described_class.mfcc(y: signal, sr:, n_mfcc: 7, n_fft: 512, hop_length: 128, n_mels: 40)

      expect(coeffs.shape[0]).to eq(7)
    end

    it "supports liftering" do
      plain = described_class.mfcc(y: signal, sr:, n_mfcc: 13, n_fft: 512, hop_length: 128, n_mels: 40)
      lifted = described_class.mfcc(y: signal, sr:, n_mfcc: 13, n_fft: 512, hop_length: 128, n_mels: 40, lifter: 22)

      expect((plain - lifted).abs.max).to be > 0.0
    end

    it "accepts precomputed log-mel input" do
      mel = described_class.melspectrogram(y: signal, sr:, n_fft: 512, hop_length: 128, n_mels: 40)
      log_mel = Muze.power_to_db(mel)
      coeffs = described_class.mfcc(sr:, s: log_mel, s_kind: :log_mel, n_mfcc: 13)

      expect(coeffs.shape[0]).to eq(13)
      expect(coeffs.shape[1]).to eq(log_mel.shape[1])
    end

    it "rejects negative mel-power input" do
      expect do
        described_class.mfcc(sr:, s: Numo::SFloat[[-1.0]], s_kind: :mel_power)
      end.to raise_error(Muze::ParameterError, /non-negative/)
    end
  end

  describe ".delta" do
    it "keeps same shape" do
      coeffs = described_class.mfcc(y: signal, sr:, n_mfcc: 13, n_fft: 512, hop_length: 128, n_mels: 40)
      delta = described_class.delta(coeffs, order: 1, width: 9)

      expect(delta.shape).to eq(coeffs.shape)
    end

    it "accepts array input and alternate edge modes" do
      delta = described_class.delta([[1.0, 2.0, 4.0, 8.0]], width: 3, mode: :mirror)

      expect(delta.shape).to eq([1, 4])
    end
  end
end
