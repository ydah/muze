# frozen_string_literal: true

module Muze
  # Onset detection routines.
  module Onset
    module_function

    # @param y [Numo::SFloat, Array<Float>, nil]
    # @param sr [Integer]
    # @param s [Numo::SFloat, nil]
    # @param hop_length [Integer]
    # @param n_fft [Integer]
    # @return [Numo::SFloat] onset envelope per frame
    def onset_strength(y: nil, sr: 22_050, s: nil, hop_length: 512, n_fft: 2048, lag: 1, log: false, max_size: 1, normalize: false)
      raise Muze::ParameterError, "lag must be positive" unless lag.positive?
      raise Muze::ParameterError, "max_size must be positive" unless max_size.positive?

      spectrum = if s
                   Numo::SFloat.cast(s)
                 else
                   Muze::Feature.melspectrogram(y:, sr:, n_fft:, hop_length:, n_mels: 40)
                 end

      spectrum = spectrum.expand_dims(1) if spectrum.ndim == 1
      spectrum = Muze.power_to_db(spectrum, ref: :max) if log
      spectrum = local_max_filter(spectrum, max_size:) if max_size > 1
      _, frames = spectrum.shape
      envelope = Numo::SFloat.zeros(frames)

      frames.times do |frame_index|
        next if frame_index < lag

        delta = spectrum[true, frame_index] - spectrum[true, frame_index - lag]
        envelope[frame_index] = delta.clip(0.0, Float::INFINITY).sum
      end

      peak = envelope.max
      envelope = envelope / peak if normalize && peak.positive?
      envelope
    end

    # @param y [Numo::SFloat, Array<Float>, nil]
    # @param sr [Integer]
    # @param onset_envelope [Numo::SFloat, Array<Float>, nil]
    # @param hop_length [Integer]
    # @param backtrack [Boolean]
    # @param units [Symbol] :frames, :samples, or :time
    # @return [Array<Integer, Float>]
    def onset_detect(y: nil, sr: 22_050, onset_envelope: nil, hop_length: 512, backtrack: false, units: :frames, pre_max: 1, post_max: 1, pre_avg: 1, post_avg: 1, delta: nil, wait: 0, adaptive: false, energy: nil)
      envelope = if onset_envelope
                   onset_envelope.is_a?(Numo::NArray) ? onset_envelope.to_a : Array(onset_envelope)
                 else
                  onset_strength(y:, sr:, hop_length:).to_a
                 end

      return [] if envelope.length < 3

      threshold = delta || detection_threshold(envelope)
      peaks = detect_peaks(envelope, threshold, pre_max:, post_max:, pre_avg:, post_avg:, wait:, adaptive:)
      peaks = backtrack_onsets(energy ? Array(energy) : envelope, peaks) if backtrack

      convert_units(peaks, units:, sr:, hop_length:)
    end

    def detection_threshold(envelope)
      mean = envelope.sum(0.0) / envelope.length
      variance = envelope.sum { |value| (value - mean)**2 } / envelope.length
      mean + (0.5 * Math.sqrt(variance))
    end
    private_class_method :detection_threshold

    def detect_peaks(envelope, threshold, pre_max:, post_max:, pre_avg:, post_avg:, wait:, adaptive:)
      peaks = []
      last_peak = -Float::INFINITY
      (1...(envelope.length - 1)).each do |index|
        local_max_start = [index - pre_max, 0].max
        local_max_end = [index + post_max, envelope.length - 1].min
        local_avg_start = [index - pre_avg, 0].max
        local_avg_end = [index + post_avg, envelope.length - 1].min
        local_threshold = adaptive ? average(envelope[local_avg_start..local_avg_end]) + threshold : threshold

        next unless envelope[index] >= local_threshold
        next unless envelope[index] >= envelope[local_max_start..local_max_end].max
        next if index <= last_peak + wait

        peaks << index
        last_peak = index
      end
      peaks
    end
    private_class_method :detect_peaks

    def backtrack_onsets(envelope, peaks)
      peaks.map do |peak|
        start = [peak - 3, 0].max
        window = envelope[start..peak]
        min_index = window.each_with_index.min_by { |value, idx| [value, idx] }[1]
        start + min_index
      end.uniq
    end
    private_class_method :backtrack_onsets

    def convert_units(peaks, units:, sr:, hop_length:)
      case units
      when :frames
        peaks
      when :samples
        peaks.map { |frame| frame * hop_length }
      when :time
        peaks.map { |frame| frame * hop_length.to_f / sr }
      else
        raise Muze::ParameterError, "units must be :frames, :samples, or :time"
      end
    end
    private_class_method :convert_units

    def local_max_filter(spectrum, max_size:)
      rows, cols = spectrum.shape
      half = max_size / 2
      output = Numo::SFloat.zeros(rows, cols)

      rows.times do |row|
        cols.times do |col|
          start_col = [col - half, 0].max
          end_col = [col + half, cols - 1].min
          output[row, col] = spectrum[row, start_col..end_col].max
        end
      end
      output
    end
    private_class_method :local_max_filter

    def average(values)
      values.sum(0.0) / values.length
    end
    private_class_method :average
  end
end
