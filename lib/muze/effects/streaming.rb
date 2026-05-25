# frozen_string_literal: true

module Muze
  module Effects
    module_function

    def time_stretch_stream(chunks, rate: 1.0, n_fft: nil, hop_length: nil, method: :phase_vocoder, phase_lock: false, force_phase_vocoder: false, overlap: 2048)
      return enum_for(__method__, chunks, rate:, n_fft:, hop_length:, method:, phase_lock:, force_phase_vocoder:, overlap:) unless block_given?

      validate_positive_number!(rate, "rate")
      validate_stream_overlap!(overlap)
      stream_effect_chunks(chunks, overlap:) do |working, prefix_frames|
        stretched = time_stretch(working, rate:, n_fft:, hop_length:, method:, phase_lock:, force_phase_vocoder:)
        drop = [(prefix_frames / rate).round, audio_frame_count(stretched)].min
        yield drop_audio_frames(stretched, drop)
      end
      nil
    end

    def pitch_shift_stream(chunks, sr: 22_050, n_steps: 0, bins_per_octave: 12, res_type: :auto, normalize: false, clip: nil, overlap: 2048)
      return enum_for(__method__, chunks, sr:, n_steps:, bins_per_octave:, res_type:, normalize:, clip:, overlap:) unless block_given?

      validate_stream_overlap!(overlap)
      stream_effect_chunks(chunks, overlap:) do |working, prefix_frames|
        shifted = pitch_shift(working, sr:, n_steps:, bins_per_octave:, res_type:, normalize:, clip:)
        yield drop_audio_frames(shifted, prefix_frames)
      end
      nil
    end

    def hpss_stream(chunks, kernel_size: 31, power: 2.0, margin: 1.0, n_fft: 2048, hop_length: 512, overlap: n_fft)
      return enum_for(__method__, chunks, kernel_size:, power:, margin:, n_fft:, hop_length:, overlap:) unless block_given?

      validate_stream_overlap!(overlap)
      stream_effect_chunks(chunks, overlap:) do |working, prefix_frames|
        harmonic, percussive = hpss(working, kernel_size:, power:, margin:, n_fft:, hop_length:)
        yield drop_audio_frames(harmonic, prefix_frames), drop_audio_frames(percussive, prefix_frames)
      end
      nil
    end

    def stream_effect_chunks(chunks, overlap:)
      tail = nil
      chunks.each do |chunk|
        signal = Muze::Core::Audio.validate_audio!(chunk, allow_empty: true)
        next if signal.empty?

        working = tail ? concat_audio(tail, signal) : signal
        prefix_frames = tail ? audio_frame_count(tail) : 0
        yield working, prefix_frames
        tail = overlap.positive? ? take_audio_tail(working, overlap) : nil
      end
    end
    private_class_method :stream_effect_chunks

    def audio_frame_count(signal)
      signal.ndim == 2 ? signal.shape[0] : signal.size
    end
    private_class_method :audio_frame_count

    def concat_audio(left, right)
      return right if left.nil? || left.empty?
      return left if right.empty?

      if left.ndim == 2 || right.ndim == 2
        raise Muze::ParameterError, "chunk channel counts must match" unless left.ndim == 2 && right.ndim == 2 && left.shape[1] == right.shape[1]

        output = Numo::SFloat.zeros(left.shape[0] + right.shape[0], left.shape[1])
        output[0...left.shape[0], true] = left
        output[left.shape[0]...(left.shape[0] + right.shape[0]), true] = right
        return output
      end

      Numo::SFloat.cast(left.to_a + right.to_a)
    end
    private_class_method :concat_audio

    def take_audio_tail(signal, count)
      frames = audio_frame_count(signal)
      start = [frames - count, 0].max
      drop_audio_frames(signal, start)
    end
    private_class_method :take_audio_tail

    def drop_audio_frames(signal, count)
      frames = audio_frame_count(signal)
      start = [[count, 0].max, frames].min
      return signal[start...frames, true] if signal.ndim == 2

      signal[start...frames]
    end
    private_class_method :drop_audio_frames

    def validate_stream_overlap!(overlap)
      return if overlap.is_a?(Integer) && overlap >= 0

      raise Muze::ParameterError, "overlap must be a non-negative integer"
    end
    private_class_method :validate_stream_overlap!
  end
end
