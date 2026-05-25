# frozen_string_literal: true

module Muze
  module Core
    # Tiny bounded LRU cache for generated DSP lookup tables.
    class BoundedCache
      def initialize(max_size:)
        raise Muze::ParameterError, "max_size must be positive" unless max_size.is_a?(Integer) && max_size.positive?

        @max_size = max_size
        @entries = {}
        @mutex = Mutex.new
      end

      def fetch(key)
        @mutex.synchronize do
          if @entries.key?(key)
            value = @entries.delete(key)
            @entries[key] = value
            return value
          end

          value = yield
          @entries.shift while @entries.size >= @max_size
          @entries[key] = value
        end
      end

      def clear
        @mutex.synchronize { @entries.clear }
      end

      def size
        @mutex.synchronize { @entries.size }
      end
    end
  end
end
