# frozen_string_literal: true

RSpec.describe Muze::Core::STFT do
  let(:sr) { 22_050 }
  let(:signal) do
    Numo::SFloat.cast(
      Array.new(4096) do |index|
        Math.sin((2.0 * Math::PI * 440.0 * index) / sr)
      end
    )
  end

  describe ".stft" do
    it "returns expected shape" do
      result = Muze.stft(signal, n_fft: 256, hop_length: 64, center: false)

      expect(result.shape).to eq([129, 61])
    end

    it "changes frame count with center" do
      centered = Muze.stft(signal, n_fft: 256, hop_length: 64, center: true)
      uncentered = Muze.stft(signal, n_fft: 256, hop_length: 64, center: false)

      expect(centered.shape[1]).to be > uncentered.shape[1]
    end

    it "honors pad mode" do
      reflected = Muze.stft([1.0, 2.0, 3.0], n_fft: 4, hop_length: 2, center: true, pad_mode: :reflect)
      constant = Muze.stft([1.0, 2.0, 3.0], n_fft: 4, hop_length: 2, center: true, pad_mode: :constant)

      expect((reflected.abs - constant.abs).abs.max).to be > 0.0
    end

    it "rejects unsupported pad mode" do
      expect do
        Muze.stft(signal, n_fft: 256, hop_length: 64, pad_mode: :unsupported)
      end.to raise_error(Muze::ParameterError, /pad_mode/)
    end

    it "rejects multi-channel input with a clear error" do
      expect do
        Muze.stft([[0.0, 1.0], [0.5, 0.5]], n_fft: 4, hop_length: 2)
      end.to raise_error(Muze::ParameterError, /mono/)
    end

    it "supports even non-power-of-two FFT lengths" do
      result = Muze.stft(signal, n_fft: 300, hop_length: 75, center: false)

      expect(result.shape[0]).to eq(151)
    end

    it "can pad the trailing partial frame" do
      dropped = Muze.stft(Array.new(11, 1.0), n_fft: 4, hop_length: 3, center: false)
      padded = Muze.stft(Array.new(11, 1.0), n_fft: 4, hop_length: 3, center: false, pad_end: true)

      expect(padded.shape[1]).to eq(dropped.shape[1] + 1)
    end

    it "supports periodic analysis windows" do
      symmetric = Muze.stft(signal, n_fft: 256, hop_length: 64, center: false, periodic: false)
      periodic = Muze.stft(signal, n_fft: 256, hop_length: 64, center: false, periodic: true)

      expect((symmetric.abs - periodic.abs).abs.max).to be > 0.0
    end
  end

  describe ".istft" do
    it "reconstructs waveform with small error" do
      spectrum = Muze.stft(signal, n_fft: 256, hop_length: 64, center: true)
      reconstructed = Muze.istft(spectrum, hop_length: 64, center: true, length: signal.size)

      error = (reconstructed - signal).abs.max
      expect(error).to be < 0.05
    end

    it "can return float64 output" do
      spectrum = Muze.stft(signal, n_fft: 256, hop_length: 64, center: true)
      reconstructed = Muze.istft(spectrum, hop_length: 64, center: true, length: signal.size, dtype: :dfloat)

      expect(reconstructed).to be_a(Numo::DFloat)
    end

    it "rejects invalid STFT matrices" do
      expect do
        Muze.istft(Numo::DComplex[Complex(Float::NAN, 0.0)])
      end.to raise_error(Muze::ParameterError, /two-dimensional|complex STFT/)
    end

    it "uses matching periodic windows for reconstruction" do
      spectrum = Muze.stft(signal, n_fft: 256, hop_length: 64, center: true, periodic: true)
      reconstructed = Muze.istft(spectrum, hop_length: 64, center: true, length: signal.size, periodic: true)

      expect((reconstructed - signal).abs.max).to be < 0.05
    end

    it "reconstructs non-power-of-two FFT lengths when the trailing frame is padded" do
      spectrum = Muze.stft(signal, n_fft: 300, hop_length: 75, center: true, pad_end: true)
      reconstructed = Muze.istft(spectrum, hop_length: 75, center: true, length: signal.size)

      expect((reconstructed - signal).abs.max).to be < 1.0e-4
    end
  end

  describe ".magphase" do
    it "supports custom epsilon and dtype" do
      spectrum = Muze.stft(signal, n_fft: 256, hop_length: 64, center: true)
      magnitude, phase = Muze.magphase(spectrum, eps: 1.0e-9, dtype: :dfloat)

      expect(magnitude).to be_a(Numo::DFloat)
      expect(phase.shape).to eq(spectrum.shape)
    end

    it "rejects invalid epsilon" do
      expect do
        Muze.magphase(Muze.stft(signal, n_fft: 256, hop_length: 64), eps: 0.0)
      end.to raise_error(Muze::ParameterError, /eps/)
    end
  end

  describe ".stft_stream" do
    it "returns one STFT matrix per chunk" do
      chunks = [signal[0...1024], signal[1024...2048]]
      matrices = Muze.stft_stream(chunks, n_fft: 256, hop_length: 128)

      expect(matrices.length).to eq(2)
      expect(matrices.all? { |matrix| matrix.shape[0] == 129 }).to be(true)
    end
  end

  describe "dB conversion" do
    it "is invertible for amplitude" do
      amplitude = Numo::SFloat[[0.1, 0.5, 1.0, 2.0]]
      db = Muze.amplitude_to_db(amplitude, ref: 1.0, top_db: nil)
      restored = Muze.db_to_amplitude(db, ref: 1.0)

      error = (restored - amplitude).abs.max
      expect(error).to be < 1.0e-4
    end

    it "is invertible for power" do
      power = Numo::SFloat[[0.1, 0.5, 1.0, 2.0]]
      db = Muze.power_to_db(power, ref: 1.0, top_db: nil)
      restored = Muze.db_to_power(db, ref: 1.0)

      error = (restored - power).abs.max
      expect(error).to be < 1.0e-4
    end

    it "validates inverse dB references" do
      expect do
        Muze.db_to_amplitude([0.0], ref: 0.0)
      end.to raise_error(Muze::ParameterError, /ref/)
    end

    it "rejects negative amplitudes unless abs is requested" do
      expect do
        Muze.amplitude_to_db(Numo::SFloat[-1.0])
      end.to raise_error(Muze::ParameterError, /non-negative/)

      expect(Muze.amplitude_to_db(Numo::SFloat[-1.0], abs: true, top_db: nil)[0]).to eq(0.0)
    end

    it "rejects negative top_db" do
      expect do
        Muze.power_to_db(Numo::SFloat[1.0], top_db: -1.0)
      end.to raise_error(Muze::ParameterError, /top_db/)
    end
  end

  describe "frame/time helpers" do
    it "converts between frames, samples, and time" do
      expect(Muze.frames_to_samples(10, hop_length: 512)).to eq(5120)
      expect(Muze.samples_to_frames(5120, hop_length: 512)).to eq(10)
      expect(Muze.frames_to_time(10, sr:, hop_length: 512)).to be_within(1.0e-6).of(5120.0 / sr)
      expect(Muze.time_to_frames(5120.0 / sr, sr:, hop_length: 512)).to eq(10)
      expect(Muze.samples_to_time(5120, sr:)).to be_within(1.0e-6).of(5120.0 / sr)
      expect(Muze.time_to_samples(5120.0 / sr, sr:)).to eq(5120)
    end

    it "returns FFT frequency bins" do
      expect(Muze.fft_frequencies(sr: 8_000, n_fft: 8).to_a).to eq([0.0, 1000.0, 2000.0, 3000.0, 4000.0])
    end

    it "validates FFT frequency parameters" do
      expect do
        Muze.fft_frequencies(sr: 8_000.0, n_fft: 8)
      end.to raise_error(Muze::ParameterError, /sr/)
    end
  end

  describe "validation" do
    it "rejects unreasonably large FFT sizes" do
      expect do
        Muze.stft(signal, n_fft: Muze::Core::STFT::MAX_N_FFT + 2, hop_length: 512)
      end.to raise_error(Muze::ParameterError, /n_fft/)
    end
  end
end
