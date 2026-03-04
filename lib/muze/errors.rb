# frozen_string_literal: true

module Muze
  # Base error for all Muze failures.
  class Error < StandardError; end

  # Raised when audio file loading fails.
  class AudioLoadError < Error; end

  # Raised when unsupported audio format is used.
  class UnsupportedFormatError < Error; end

  # Raised when method parameters are invalid.
  class ParameterError < Error; end

  # Raised when optional runtime dependency is unavailable.
  class DependencyError < Error; end
end
