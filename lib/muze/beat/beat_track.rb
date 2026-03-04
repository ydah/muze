# frozen_string_literal: true

module Muze
  # Beat tracking functions.
  module Beat
    module_function

    # @param y [Numo::SFloat, Array<Float>, nil]
    # @param sr [Integer]
    # @param onset_envelope [Numo::SFloat, Array<Float>, nil]
    # @param hop_length [Integer]
    # @param start_bpm [Float]
    # @param tightness [Integer]
    # @return [Array(Float, Array<Integer>)] estimated tempo and beat frames
    def beat_track(y: nil, sr: 22_050, onset_envelope: nil, hop_length: 512, start_bpm: 120.0, tightness: 100)
      envelope = if onset_envelope
                   onset_envelope.is_a?(Numo::NArray) ? onset_envelope.to_a : Array(onset_envelope)
                 else
                   Muze::Onset.onset_strength(y:, sr:, hop_length:).to_a
                 end

      tempo = estimate_tempo(envelope, sr:, hop_length:, start_bpm:)
      beats = track_beats(envelope, tempo:, sr:, hop_length:, tightness:)
      [tempo, beats]
    end

    # @param y [Numo::SFloat, Array<Float>, nil]
    # @param onset_envelope [Numo::SFloat, Array<Float>, nil]
    # @param sr [Integer]
    # @param hop_length [Integer]
    # @param win_length [Integer]
    # @return [Numo::SFloat]
    def tempogram(y: nil, onset_envelope: nil, sr: 22_050, hop_length: 512, win_length: 384)
      Muze::Feature.tempogram(y:, onset_envelope:, sr:, hop_length:, win_length:)
    end

    def estimate_tempo(envelope, sr:, hop_length:, start_bpm:)
      return start_bpm if envelope.length < 4

      min_bpm = 30.0
      max_bpm = 240.0
      min_lag = [(sr * 60.0 / (hop_length * max_bpm)).round, 1].max
      max_lag = [(sr * 60.0 / (hop_length * min_bpm)).round, envelope.length - 1].min
      return start_bpm if min_lag >= max_lag

      best_lag = min_lag
      best_score = -Float::INFINITY

      (min_lag..max_lag).each do |lag|
        score = 0.0
        (lag...envelope.length).each { |index| score += envelope[index] * envelope[index - lag] }
        next unless score > best_score

        best_score = score
        best_lag = lag
      end

      60.0 * sr / (hop_length * best_lag)
    end
    private_class_method :estimate_tempo

    def track_beats(envelope, tempo:, sr:, hop_length:, tightness:)
      _ = tightness
      interval = [(60.0 * sr / (tempo * hop_length)).round, 1].max
      peaks = Muze::Onset.onset_detect(onset_envelope: envelope, backtrack: false)
      return [] if peaks.empty?

      beats = [peaks.first]
      target = peaks.first + interval

      while target < envelope.length
        candidates = peaks.select { |peak| (peak - target).abs <= (interval / 2.0) }
        beats << (candidates.min_by { |peak| (peak - target).abs } || target)
        target += interval
      end

      beats.uniq
    end
    private_class_method :track_beats
  end
end
