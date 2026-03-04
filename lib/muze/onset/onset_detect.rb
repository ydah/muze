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
    def onset_strength(y: nil, sr: 22_050, s: nil, hop_length: 512, n_fft: 2048)
      spectrum = if s
                   Numo::SFloat.cast(s)
                 else
                   Muze::Feature.melspectrogram(y:, sr:, n_fft:, hop_length:, n_mels: 40)
                 end

      spectrum = spectrum.expand_dims(1) if spectrum.ndim == 1
      _, frames = spectrum.shape
      envelope = Numo::SFloat.zeros(frames)

      frames.times do |frame_index|
        next if frame_index.zero?

        delta = spectrum[true, frame_index] - spectrum[true, frame_index - 1]
        envelope[frame_index] = delta.clip(0.0, Float::INFINITY).sum
      end

      envelope
    end

    # @param y [Numo::SFloat, Array<Float>, nil]
    # @param sr [Integer]
    # @param onset_envelope [Numo::SFloat, Array<Float>, nil]
    # @param hop_length [Integer]
    # @param backtrack [Boolean]
    # @param units [Symbol] :frames or :time
    # @return [Array<Integer, Float>]
    def onset_detect(y: nil, sr: 22_050, onset_envelope: nil, hop_length: 512, backtrack: false, units: :frames)
      envelope = if onset_envelope
                   onset_envelope.is_a?(Numo::NArray) ? onset_envelope.to_a : Array(onset_envelope)
                 else
                   onset_strength(y:, sr:, hop_length:).to_a
                 end

      return [] if envelope.length < 3

      threshold = detection_threshold(envelope)
      peaks = detect_peaks(envelope, threshold)
      peaks = backtrack_onsets(envelope, peaks) if backtrack

      case units
      when :frames
        peaks
      when :time
        peaks.map { |frame| frame * hop_length.to_f / sr }
      else
        raise Muze::ParameterError, "units must be :frames or :time"
      end
    end

    def detection_threshold(envelope)
      mean = envelope.sum(0.0) / envelope.length
      variance = envelope.sum { |value| (value - mean)**2 } / envelope.length
      mean + (0.5 * Math.sqrt(variance))
    end
    private_class_method :detection_threshold

    def detect_peaks(envelope, threshold)
      peaks = []
      (1...(envelope.length - 1)).each do |index|
        next unless envelope[index] >= threshold
        next unless envelope[index] > envelope[index - 1]
        next unless envelope[index] >= envelope[index + 1]

        peaks << index
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
  end
end
