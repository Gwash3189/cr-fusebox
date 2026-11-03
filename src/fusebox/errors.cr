module Fusebox
  # Base error type for all Fusebox failures.
  class Error < Exception
  end

  # Raised when a call is rejected because the circuit is open.
  class CircuitOpenError < Error
    getter key : String
    getter remaining : Time::Span

    def initialize(@key : String, remaining : Time::Span = Time::Span.zero)
      @remaining = remaining < Time::Span.zero ? Time::Span.zero : remaining
      super(
        "Circuit breaker \"#{@key}\" is open. " \
        "Cooldown remaining: #{@remaining.total_milliseconds.round.to_i}ms"
      )
    end
  end
end
