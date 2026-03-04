# frozen_string_literal: true

module Muze
  module Feature
    module_function

    # @param y [Numo::SFloat, Array<Float>, nil]
    # @param s [Numo::SFloat, nil]
    # @param sr [Integer]
    # @param n_fft [Integer]
    # @param hop_length [Integer]
    # @return [Numo::SFloat] shape: [1, frames]
    def spectral_centroid(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512)
      magnitude, frequencies = prepare_magnitude(y:, s:, sr:, n_fft:, hop_length:)
      _, frames = magnitude.shape
      output = Numo::SFloat.zeros(1, frames)

      frames.times do |frame_index|
        spectrum = magnitude[true, frame_index]
        denominator = spectrum.sum
        if denominator <= 0.0
          output[0, frame_index] = 0.0
          next
        end

        numerator = 0.0
        frequencies.length.times { |bin| numerator += frequencies[bin] * spectrum[bin] }
        output[0, frame_index] = numerator / denominator
      end

      output
    end

    # @param y [Numo::SFloat, Array<Float>, nil]
    # @param s [Numo::SFloat, nil]
    # @param sr [Integer]
    # @param n_fft [Integer]
    # @param hop_length [Integer]
    # @param p [Integer]
    # @return [Numo::SFloat] shape: [1, frames]
    def spectral_bandwidth(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, p: 2)
      magnitude, frequencies = prepare_magnitude(y:, s:, sr:, n_fft:, hop_length:)
      centroids = spectral_centroid(y:, s: magnitude, sr:, n_fft:, hop_length:)
      _, frames = magnitude.shape
      output = Numo::SFloat.zeros(1, frames)

      frames.times do |frame_index|
        spectrum = magnitude[true, frame_index]
        denominator = spectrum.sum
        if denominator <= 0.0
          output[0, frame_index] = 0.0
          next
        end

        sum = 0.0
        frequencies.length.times do |bin|
          distance = (frequencies[bin] - centroids[0, frame_index]).abs
          sum += spectrum[bin] * (distance**p)
        end

        output[0, frame_index] = (sum / denominator)**(1.0 / p)
      end

      output
    end

    # @param y [Numo::SFloat, Array<Float>, nil]
    # @param s [Numo::SFloat, nil]
    # @param sr [Integer]
    # @param n_fft [Integer]
    # @param hop_length [Integer]
    # @param roll_percent [Float]
    # @return [Numo::SFloat] shape: [1, frames]
    def spectral_rolloff(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, roll_percent: 0.85)
      magnitude, frequencies = prepare_magnitude(y:, s:, sr:, n_fft:, hop_length:)
      _, frames = magnitude.shape
      output = Numo::SFloat.zeros(1, frames)

      frames.times do |frame_index|
        spectrum = magnitude[true, frame_index]
        threshold = spectrum.sum * roll_percent
        cumulative = 0.0
        rolloff_frequency = frequencies.last

        frequencies.length.times do |bin|
          cumulative += spectrum[bin]
          if cumulative >= threshold
            rolloff_frequency = frequencies[bin]
            break
          end
        end

        output[0, frame_index] = rolloff_frequency
      end

      output
    end

    # @param y [Numo::SFloat, Array<Float>, nil]
    # @param s [Numo::SFloat, nil]
    # @param amin [Float]
    # @return [Numo::SFloat] shape: [1, frames]
    def spectral_flatness(y: nil, s: nil, n_fft: 2048, hop_length: 512, amin: 1.0e-10)
      magnitude, = prepare_magnitude(y:, s:, sr: 22_050, n_fft:, hop_length:)
      _, frames = magnitude.shape
      output = Numo::SFloat.zeros(1, frames)

      frames.times do |frame_index|
        spectrum = magnitude[true, frame_index].to_a.map { |value| [value, amin].max }
        geometric = Math.exp(spectrum.sum { |value| Math.log(value) } / spectrum.length)
        arithmetic = spectrum.sum(0.0) / spectrum.length
        output[0, frame_index] = geometric / arithmetic
      end

      output
    end

    # @param y [Numo::SFloat, Array<Float>, nil]
    # @param s [Numo::SFloat, nil]
    # @param n_bands [Integer]
    # @param quantile [Float]
    # @return [Numo::SFloat] shape: [n_bands + 1, frames]
    def spectral_contrast(y: nil, s: nil, n_fft: 2048, hop_length: 512, n_bands: 6, quantile: 0.02)
      magnitude, = prepare_magnitude(y:, s:, sr: 22_050, n_fft:, hop_length:)
      bins, frames = magnitude.shape
      edges = Array.new(n_bands + 2) { |idx| ((bins - 1) * idx / (n_bands + 1).to_f).round }
      output = Numo::SFloat.zeros(n_bands + 1, frames)

      (n_bands + 1).times do |band|
        lower = edges[band]
        upper = [edges[band + 1], lower + 1].max

        frames.times do |frame_index|
          segment = magnitude[lower...upper, frame_index].to_a.sort
          next if segment.empty?

          low_idx = [(segment.length * quantile).floor, segment.length - 1].min
          high_idx = [(segment.length * (1.0 - quantile)).floor, segment.length - 1].min
          valley = [segment[low_idx], 1.0e-10].max
          peak = [segment[high_idx], 1.0e-10].max
          output[band, frame_index] = 10.0 * Math.log10(peak / valley)
        end
      end

      output
    end

    # @param y [Numo::SFloat, Array<Float>]
    # @param frame_length [Integer]
    # @param hop_length [Integer]
    # @return [Numo::SFloat] shape: [1, frames]
    def zero_crossing_rate(y, frame_length: 2048, hop_length: 512)
      signal = y.is_a?(Numo::NArray) ? y.to_a : Array(y)
      frames = frame_signal(signal, frame_length, hop_length)
      values = frames.map do |frame|
        crossings = 0
        (1...frame.length).each { |idx| crossings += 1 if (frame[idx - 1] >= 0) != (frame[idx] >= 0) }
        crossings.to_f / frame_length
      end

      Numo::SFloat[values]
    end

    # @param y [Numo::SFloat, Array<Float>, nil]
    # @param s [Numo::SFloat, nil]
    # @param frame_length [Integer]
    # @param hop_length [Integer]
    # @return [Numo::SFloat] shape: [1, frames]
    def rms(y: nil, s: nil, frame_length: 2048, hop_length: 512)
      if s
        matrix = Numo::SFloat.cast(s)
        matrix = matrix.expand_dims(1) if matrix.ndim == 1
        _, frames = matrix.shape
        values = Array.new(frames) do |frame_index|
          frame = matrix[true, frame_index]
          Math.sqrt((frame**2).sum / frame.size)
        end

        return Numo::SFloat[values]
      end

      signal = y.is_a?(Numo::NArray) ? y.to_a : Array(y)
      frames = frame_signal(signal, frame_length, hop_length)
      values = frames.map do |frame|
        Math.sqrt(frame.sum { |value| value * value } / frame.length)
      end

      Numo::SFloat[values]
    end

    # @param y [Numo::SFloat, Array<Float>, nil]
    # @param onset_envelope [Numo::SFloat, Array<Float>, nil]
    # @param sr [Integer]
    # @param hop_length [Integer]
    # @param win_length [Integer]
    # @return [Numo::SFloat]
    def tempogram(y: nil, onset_envelope: nil, sr: 22_050, hop_length: 512, win_length: 384)
      envelope = if onset_envelope
                   onset_envelope.is_a?(Numo::NArray) ? onset_envelope.to_a : Array(onset_envelope)
                 else
                   onset_env_from_signal(y, sr:, hop_length:)
                 end

      frames = envelope.length
      tempogram = Numo::SFloat.zeros(win_length, frames)

      frames.times do |frame_index|
        window_start = [0, frame_index - win_length + 1].max
        segment = envelope[window_start..frame_index]
        win_length.times do |lag|
          break if lag >= segment.length

          value = 0.0
          (lag...segment.length).each do |offset|
            value += segment[offset] * segment[offset - lag]
          end
          tempogram[lag, frame_index] = value
        end
      end

      tempogram
    end

    def prepare_magnitude(y:, s:, sr:, n_fft:, hop_length:)
      spectrum = if s
                   Numo::SFloat.cast(s)
                 else
                   stft_matrix = Muze.stft(y, n_fft:, hop_length:)
                   magnitude, = Muze.magphase(stft_matrix)
                   magnitude
                 end

      spectrum = spectrum.expand_dims(1) if spectrum.ndim == 1
      bins, = spectrum.shape
      fft_size = n_fft || ((bins - 1) * 2)
      frequencies = Array.new(bins) { |index| index * sr.to_f / fft_size }
      [spectrum, frequencies]
    end
    private_class_method :prepare_magnitude

    def frame_signal(signal, frame_length, hop_length)
      return [signal + Array.new(frame_length - signal.length, 0.0)] if signal.length <= frame_length

      frame_count = ((signal.length - frame_length) / hop_length) + 1
      Array.new(frame_count) do |index|
        start = index * hop_length
        signal[start, frame_length]
      end
    end
    private_class_method :frame_signal

    def onset_env_from_signal(y, sr:, hop_length:)
      mel_spec = melspectrogram(y:, sr:, n_fft: 1024, hop_length:, n_mels: 40)
      _, frames = mel_spec.shape
      onset = Array.new(frames, 0.0)
      frames.times do |frame_index|
        next if frame_index.zero?

        diff = mel_spec[true, frame_index] - mel_spec[true, frame_index - 1]
        onset[frame_index] = diff.clip(0.0, Float::INFINITY).sum
      end
      onset
    end
    private_class_method :onset_env_from_signal
  end
end
