module Fusebox
  # Immutable configuration for a single circuit.
  struct Config
    getter key : String
    getter failures : Int32
    getter within : Time::Span?
    getter cooldown : Time::Span

    def initialize(
      @key : String,
      @failures : Int32 = 5,
      @within : Time::Span? = nil,
      @cooldown : Time::Span = 30.seconds,
    )
      raise ArgumentError.new("circuit key must be a non-empty string") if @key.strip.empty?
      raise ArgumentError.new("failures must be at least 1") if @failures < 1

      if within = @within
        raise ArgumentError.new("within must be positive") if within <= Time::Span.zero
      end

      raise ArgumentError.new("cooldown must be non-negative") if @cooldown < Time::Span.zero
    end
  end
end
