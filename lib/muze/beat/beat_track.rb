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
    def beat_track(y: nil, sr: 22_050, onset_envelope: nil, hop_length: 512, start_bpm: 120.0, tightness: 100, min_bpm: 30.0, max_bpm: 240.0, bpm: nil, fill_missing: true, return_metadata: false)
      envelope = if onset_envelope
                   onset_envelope.is_a?(Numo::NArray) ? onset_envelope.to_a : Array(onset_envelope)
                 else
                   Muze::Onset.onset_strength(y:, sr:, hop_length:).to_a
                 end

      if envelope.empty? || envelope.max.to_f <= 1.0e-12
        result = { tempo: nil, beats: [], confidence: 0.0 }
        return return_metadata ? result : [nil, []]
      end

      tempo = bpm || estimate_tempo(envelope, sr:, hop_length:, start_bpm:, min_bpm:, max_bpm:, tightness:)
      beats = track_beats(envelope, tempo:, sr:, hop_length:, tightness:, fill_missing:)
      confidence = beat_confidence(envelope, beats)
      return { tempo:, beats:, confidence: } if return_metadata

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

    def tempo_frequencies(sr: 22_050, hop_length: 512, win_length: 384)
      raise Muze::ParameterError, "win_length must be positive" unless win_length.positive?

      Numo::SFloat.cast(Array.new(win_length) do |lag|
        lag.zero? ? 0.0 : 60.0 * sr / (hop_length * lag)
      end)
    end

    def estimate_tempo(envelope, sr:, hop_length:, start_bpm:, min_bpm:, max_bpm:, tightness:)
      return start_bpm if envelope.length < 4

      raise Muze::ParameterError, "min_bpm must be positive" unless min_bpm.positive?
      raise Muze::ParameterError, "max_bpm must be greater than min_bpm" unless max_bpm > min_bpm

      min_lag = [(sr * 60.0 / (hop_length * max_bpm)).round, 1].max
      max_lag = [(sr * 60.0 / (hop_length * min_bpm)).round, envelope.length - 1].min
      return start_bpm if min_lag >= max_lag

      prior_lag = sr * 60.0 / (hop_length * start_bpm)
      best_lag = min_lag
      best_score = -Float::INFINITY

      (min_lag..max_lag).each do |lag|
        score = 0.0
        (lag...envelope.length).each { |index| score += envelope[index] * envelope[index - lag] }
        score -= normalized_tightness(tightness) * ((lag - prior_lag).abs / prior_lag) * score.abs
        next unless score > best_score

        best_score = score
        best_lag = lag
      end

      60.0 * sr / (hop_length * best_lag)
    end
    private_class_method :estimate_tempo

    def track_beats(envelope, tempo:, sr:, hop_length:, tightness:, fill_missing:)
      interval = [(60.0 * sr / (tempo * hop_length)).round, 1].max
      peaks = Muze::Onset.onset_detect(onset_envelope: envelope, backtrack: false)
      return [] if peaks.empty?

      beats = [peaks.first]
      target = peaks.first + interval

      while target < envelope.length
        candidates = peaks.select { |peak| (peak - target).abs <= search_radius(interval, tightness) }
        candidate = select_beat_candidate(candidates, target:, interval:, envelope:, tightness:)
        beats << (candidate || target) if fill_missing || candidate
        target += interval
      end

      beats.uniq
    end
    private_class_method :track_beats

    def search_radius(interval, tightness)
      normalized = normalized_tightness(tightness)
      radius_scale = 1.0 - (0.4 * normalized)
      [(interval * radius_scale).round, 1].max
    end
    private_class_method :search_radius

    def select_beat_candidate(candidates, target:, interval:, envelope:, tightness:)
      return nil unless candidates.any?

      penalty_weight = 1.0 + (4.0 * normalized_tightness(tightness))
      candidates.max_by do |candidate|
        strength = envelope[candidate] || 0.0
        normalized_distance = (candidate - target).abs / interval.to_f
        strength - (penalty_weight * normalized_distance)
      end
    end
    private_class_method :select_beat_candidate

    def beat_confidence(envelope, beats)
      return 0.0 if beats.empty?

      peak = envelope.max.to_f
      return 0.0 if peak <= 0.0

      beats.sum { |beat| envelope[beat].to_f } / (beats.length * peak)
    end
    private_class_method :beat_confidence

    def normalized_tightness(tightness)
      value = tightness.to_f
      return 0.0 if value <= 0.0

      [value / 100.0, 4.0].min / 4.0
    end
    private_class_method :normalized_tightness
  end
end
