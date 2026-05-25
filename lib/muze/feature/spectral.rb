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
    def spectral_centroid(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, center: true, pad_mode: :reflect)
      magnitude, frequencies = prepare_magnitude(y:, s:, sr:, n_fft:, hop_length:, center:, pad_mode:)
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
    def spectral_bandwidth(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, p: 2, center: true, pad_mode: :reflect)
      raise Muze::ParameterError, "p must be positive" unless p.positive?

      magnitude, frequencies = prepare_magnitude(y:, s:, sr:, n_fft:, hop_length:, center:, pad_mode:)
      centroids = spectral_centroid(y:, s: magnitude, sr:, n_fft:, hop_length:, center:, pad_mode:)
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
    def spectral_rolloff(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, roll_percent: 0.85, center: true, pad_mode: :reflect)
      raise Muze::ParameterError, "roll_percent must satisfy 0 < roll_percent < 1" unless roll_percent.positive? && roll_percent < 1.0

      magnitude, frequencies = prepare_magnitude(y:, s:, sr:, n_fft:, hop_length:, center:, pad_mode:)
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
    def spectral_flatness(y: nil, s: nil, n_fft: 2048, hop_length: 512, amin: 1.0e-10, center: true, pad_mode: :reflect)
      raise Muze::ParameterError, "amin must be positive" unless amin.positive?

      magnitude, = prepare_magnitude(y:, s:, sr: 22_050, n_fft:, hop_length:, center:, pad_mode:)
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
    def spectral_contrast(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, n_bands: 6, quantile: 0.02, fmin: 200.0, center: true, pad_mode: :reflect)
      raise Muze::ParameterError, "n_bands must be positive" unless n_bands.positive?
      raise Muze::ParameterError, "quantile must satisfy 0 < quantile < 0.5" unless quantile.positive? && quantile < 0.5
      raise Muze::ParameterError, "fmin must be positive" unless fmin.positive?

      magnitude, frequencies = prepare_magnitude(y:, s:, sr:, n_fft:, hop_length:, center:, pad_mode:)
      bins, frames = magnitude.shape
      edges = spectral_contrast_edges(frequencies, n_bands:, fmin:, sr:)
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

    # @return [Array<Integer>]
    def spectral_contrast_edges(frequencies, n_bands:, fmin:, sr:)
      nyquist = sr / 2.0
      hz_edges = [0.0, fmin]
      n_bands.times { |band| hz_edges << [fmin * (2.0**(band + 1)), nyquist].min }
      hz_edges << nyquist
      hz_edges.map do |hz|
        index = frequencies.each_index.min_by { |idx| (frequencies[idx] - hz).abs }
        [[index, 0].max, frequencies.length - 1].min
      end.each_cons(2).with_object([0]) do |(left, right), edges|
        edges << [right, left + 1].max
      end
    end

    # @return [Numo::SFloat] shape: [1, frames]
    def spectral_flux(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, center: true, pad_mode: :reflect)
      magnitude, = prepare_magnitude(y:, s:, sr:, n_fft:, hop_length:, center:, pad_mode:)
      _, frames = magnitude.shape
      output = Numo::SFloat.zeros(1, frames)

      (1...frames).each do |frame_index|
        diff = magnitude[true, frame_index] - magnitude[true, frame_index - 1]
        output[0, frame_index] = Math.sqrt((diff * diff).sum)
      end
      output
    end

    # @return [Numo::SFloat] shape: [1, frames]
    def spectral_entropy(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, center: true, pad_mode: :reflect)
      magnitude, = prepare_magnitude(y:, s:, sr:, n_fft:, hop_length:, center:, pad_mode:)
      _, frames = magnitude.shape
      output = Numo::SFloat.zeros(1, frames)

      frames.times do |frame_index|
        spectrum = magnitude[true, frame_index]
        total = spectrum.sum
        next if total <= 0.0

        probs = spectrum / total
        entropy = probs.to_a.sum { |value| value.positive? ? -(value * Math.log2(value)) : 0.0 }
        output[0, frame_index] = entropy / Math.log2([spectrum.size, 2].max)
      end
      output
    end

    # @return [Numo::SFloat] shape: [1, frames]
    def spectral_crest(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, center: true, pad_mode: :reflect)
      magnitude, = prepare_magnitude(y:, s:, sr:, n_fft:, hop_length:, center:, pad_mode:)
      _, frames = magnitude.shape
      output = Numo::SFloat.zeros(1, frames)

      frames.times do |frame_index|
        spectrum = magnitude[true, frame_index]
        mean = spectrum.mean
        output[0, frame_index] = mean <= 0.0 ? 0.0 : spectrum.max / mean
      end
      output
    end

    # @return [Numo::SFloat] shape: [1, frames]
    def spectral_slope(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, center: true, pad_mode: :reflect)
      magnitude, frequencies = prepare_magnitude(y:, s:, sr:, n_fft:, hop_length:, center:, pad_mode:)
      mean_frequency = frequencies.sum / frequencies.length.to_f
      frequency_variance = frequencies.sum { |frequency| (frequency - mean_frequency)**2 }
      _, frames = magnitude.shape
      output = Numo::SFloat.zeros(1, frames)

      frames.times do |frame_index|
        spectrum = magnitude[true, frame_index].to_a
        mean_spectrum = spectrum.sum / spectrum.length.to_f
        covariance = frequencies.each_with_index.sum { |frequency, idx| (frequency - mean_frequency) * (spectrum[idx] - mean_spectrum) }
        output[0, frame_index] = frequency_variance.zero? ? 0.0 : covariance / frequency_variance
      end
      output
    end

    # @return [Numo::SFloat] shape: [1, frames]
    def spectral_decrease(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, center: true, pad_mode: :reflect)
      magnitude, = prepare_magnitude(y:, s:, sr:, n_fft:, hop_length:, center:, pad_mode:)
      bins, frames = magnitude.shape
      output = Numo::SFloat.zeros(1, frames)

      frames.times do |frame_index|
        first = magnitude[0, frame_index]
        denominator = 0.0
        numerator = 0.0
        (1...bins).each do |bin|
          value = magnitude[bin, frame_index]
          numerator += (value - first) / bin
          denominator += value
        end
        output[0, frame_index] = denominator <= 0.0 ? 0.0 : numerator / denominator
      end
      output
    end

    # @param y [Numo::SFloat, Array<Float>]
    # @param frame_length [Integer]
    # @param hop_length [Integer]
    # @return [Numo::SFloat] shape: [1, frames]
    def zero_crossing_rate(y, frame_length: 2048, hop_length: 512, threshold: 0.0, center: false)
      raise Muze::ParameterError, "threshold must be >= 0" if threshold.negative?

      signal = y.is_a?(Numo::NArray) ? y.to_a : Array(y)
      signal = Array.new(frame_length / 2, 0.0) + signal + Array.new(frame_length / 2, 0.0) if center
      frames = frame_signal(signal, frame_length, hop_length)
      values = frames.map do |frame|
        crossings = 0
        signs = frame.map { |value| value.abs <= threshold ? 0.0 : value }
        (1...signs.length).each { |idx| crossings += 1 if (signs[idx - 1] >= 0) != (signs[idx] >= 0) }
        crossings.to_f / frame_length
      end

      Numo::SFloat[values].reshape(1, values.length)
    end

    # @param y [Numo::SFloat, Array<Float>, nil]
    # @param s [Numo::SFloat, nil]
    # @param frame_length [Integer]
    # @param hop_length [Integer]
    # @return [Numo::SFloat] shape: [1, frames]
    def rms(y: nil, s: nil, frame_length: 2048, hop_length: 512, center: false)
      if s
        matrix = Numo::SFloat.cast(s)
        matrix = matrix.expand_dims(1) if matrix.ndim == 1
        _, frames = matrix.shape
        values = Array.new(frames) do |frame_index|
          frame = matrix[true, frame_index]
          Math.sqrt((frame**2).sum / frame.size)
        end

        return Numo::SFloat[values].reshape(1, values.length)
      end

      signal = y.is_a?(Numo::NArray) ? y.to_a : Array(y)
      signal = Array.new(frame_length / 2, 0.0) + signal + Array.new(frame_length / 2, 0.0) if center
      frames = frame_signal(signal, frame_length, hop_length)
      values = frames.map do |frame|
        Math.sqrt(frame.sum { |value| value * value } / frame.length)
      end

      Numo::SFloat[values].reshape(1, values.length)
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

    def prepare_magnitude(y:, s:, sr:, n_fft:, hop_length:, center: true, pad_mode: :reflect)
      spectrum = if s
                   Numo::SFloat.cast(s)
                 else
                   stft_matrix = Muze.stft(y, n_fft:, hop_length:, center:, pad_mode:)
                   magnitude, = Muze.magphase(stft_matrix)
                   magnitude
                 end

      spectrum = spectrum.expand_dims(1) if spectrum.ndim == 1
      bins, = spectrum.shape
      fft_size = n_fft || ((bins - 1) * 2)
      frequencies = Muze.fft_frequencies(sr:, n_fft: fft_size).to_a[0...bins]
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
