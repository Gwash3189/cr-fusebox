module Fusebox
  enum State
    Closed
    Open
    HalfOpen
  end

  enum Admission
    Closed
    HalfOpenProbe
    Rejected
  end

  # The result of attempting to enter a circuit.
  struct Ticket
    getter admission : Admission
    getter remaining : Time::Span

    def initialize(@admission : Admission, @remaining : Time::Span = Time::Span.zero)
    end

    def rejected? : Bool
      admission.rejected?
    end

    def half_open? : Bool
      admission.half_open_probe?
    end
  end

  # Thread-safe circuit state machine.
  #
  # The optional `now` parameters exist so state transitions can be tested
  # deterministically without sleeping.
  class Circuit
    getter config : Config

    @opened_at : Time::Instant?

    def initialize(@config : Config)
      @mutex = Mutex.new
      @state = State::Closed
      @failure_times = [] of Time::Instant
      @opened_at = nil
      @half_open_in_flight = false
    end

    def state(now : Time::Instant = Time.instant) : State
      @mutex.synchronize do
        if @state.open? && (opened_at = @opened_at)
          return State::HalfOpen if now - opened_at >= @config.cooldown
        end

        @state
      end
    end

    def acquire(now : Time::Instant = Time.instant) : Ticket
      @mutex.synchronize do
        case @state
        when .open?
          admit_open(now)
        when .half_open?
          admit_half_open
        else
          Ticket.new(Admission::Closed)
        end
      end
    end

    # Returns `:closed` when a half-open probe successfully closes the circuit,
    # `:none` otherwise.
    def record_success(ticket : Ticket) : Symbol
      @mutex.synchronize do
        if ticket.half_open? && @state.half_open?
          close_circuit
          :closed
        else
          @failure_times.clear if @state.closed? && @config.within.nil?
          :none
        end
      end
    end

    # Returns `:opened` when this failure opened the circuit, `:none` otherwise.
    def record_failure(ticket : Ticket, now : Time::Instant = Time.instant) : Symbol
      @mutex.synchronize do
        if ticket.half_open? || @state.half_open?
          open_circuit(now)
          :opened
        elsif @state.closed?
          record_closed_failure(now)
        else
          :none
        end
      end
    end

    private def admit_open(now : Time::Instant) : Ticket
      if (opened_at = @opened_at) && now - opened_at >= @config.cooldown
        @state = State::HalfOpen
        @half_open_in_flight = true
        Ticket.new(Admission::HalfOpenProbe)
      else
        elapsed = @opened_at ? now - @opened_at.not_nil! : @config.cooldown
        remaining = @config.cooldown - elapsed
        remaining = Time::Span.zero if remaining < Time::Span.zero
        Ticket.new(Admission::Rejected, remaining)
      end
    end

    private def admit_half_open : Ticket
      if @half_open_in_flight
        Ticket.new(Admission::Rejected)
      else
        @half_open_in_flight = true
        Ticket.new(Admission::HalfOpenProbe)
      end
    end

    private def record_closed_failure(now : Time::Instant) : Symbol
      if within = @config.within
        cutoff = now - within
        @failure_times.reject! { |failure_time| failure_time < cutoff }
      end

      @failure_times << now

      if @failure_times.size >= @config.failures
        open_circuit(now)
        :opened
      else
        :none
      end
    end

    private def open_circuit(now : Time::Instant) : Nil
      @state = State::Open
      @opened_at = now
      @half_open_in_flight = false
      @failure_times = [now]
    end

    private def close_circuit : Nil
      @state = State::Closed
      @failure_times.clear
      @opened_at = nil
      @half_open_in_flight = false
    end
  end
end
