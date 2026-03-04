# frozen_string_literal: true

module Muze
  # Filterbank generation utilities.
  module Filters
    module_function

    # @param sr [Integer]
    # @param n_fft [Integer]
    # @param n_mels [Integer]
    # @param fmin [Float]
    # @param fmax [Float, nil]
    # @param htk [Boolean]
    # @return [Numo::SFloat] shape: [n_mels, 1 + n_fft/2]
    def mel(sr: 22_050, n_fft: 2048, n_mels: 128, fmin: 0.0, fmax: nil, htk: false)
      raise Muze::ParameterError, "sr must be positive" unless sr.positive?
      raise Muze::ParameterError, "n_fft must be positive" unless n_fft.positive?
      raise Muze::ParameterError, "n_mels must be positive" unless n_mels.positive?

      fmax ||= sr / 2.0
      mel_min = hz_to_mel(fmin, htk:)
      mel_max = hz_to_mel(fmax, htk:)

      mel_points = Array.new(n_mels + 2) do |idx|
        mel_min + ((mel_max - mel_min) * idx / (n_mels + 1).to_f)
      end
      hz_points = mel_points.map { |mel_value| mel_to_hz(mel_value, htk:) }
      fft_bins = hz_points.map { |hz| ((n_fft + 1) * hz / sr).floor }

      matrix = Numo::SFloat.zeros(n_mels, (n_fft / 2) + 1)

      n_mels.times do |mel_index|
        left = fft_bins[mel_index]
        center = fft_bins[mel_index + 1]
        right = fft_bins[mel_index + 2]

        next if center <= left || right <= center

        (left...center).each do |bin|
          next unless bin.between?(0, (n_fft / 2))

          matrix[mel_index, bin] = (bin - left).to_f / (center - left)
        end

        (center...right).each do |bin|
          next unless bin.between?(0, (n_fft / 2))

          matrix[mel_index, bin] = (right - bin).to_f / (right - center)
        end
      end

      matrix
    end

    # @param hz [Float]
    # @param htk [Boolean]
    # @return [Float]
    def hz_to_mel(hz, htk: false)
      return 2595.0 * Math.log10(1.0 + (hz / 700.0)) if htk

      f_sp = 200.0 / 3.0
      min_log_hz = 1000.0
      min_log_mel = min_log_hz / f_sp
      log_step = Math.log(6.4) / 27.0

      if hz < min_log_hz
        hz / f_sp
      else
        min_log_mel + (Math.log(hz / min_log_hz) / log_step)
      end
    end

    # @param mel_value [Float]
    # @param htk [Boolean]
    # @return [Float]
    def mel_to_hz(mel_value, htk: false)
      return 700.0 * ((10.0**(mel_value / 2595.0)) - 1.0) if htk

      f_sp = 200.0 / 3.0
      min_log_hz = 1000.0
      min_log_mel = min_log_hz / f_sp
      log_step = Math.log(6.4) / 27.0

      if mel_value < min_log_mel
        mel_value * f_sp
      else
        min_log_hz * Math.exp(log_step * (mel_value - min_log_mel))
      end
    end
  end
end
