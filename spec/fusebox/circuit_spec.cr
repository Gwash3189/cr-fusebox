require "../spec_helper"

private CIRCUIT_SPEC_BASE = Time.instant

private def instant_at(offset : Time::Span) : Time::Instant
  CIRCUIT_SPEC_BASE + offset
end

private def build_circuit(
  failures : Int32 = 2,
  within : Time::Span? = nil,
  cooldown : Time::Span = 1.second,
) : Fusebox::Circuit
  Fusebox::Circuit.new(
    Fusebox::Config.new(
      key: "spec",
      failures: failures,
      within: within,
      cooldown: cooldown,
    )
  )
end

private def trip(circuit : Fusebox::Circuit, now : Time::Instant = CIRCUIT_SPEC_BASE) : Nil
  ticket = circuit.acquire(now)
  circuit.record_failure(ticket, now)
end

private def open_circuit(
  failures : Int32 = 2,
  cooldown : Time::Span = 1.second,
) : Fusebox::Circuit
  circuit = build_circuit(failures: failures, cooldown: cooldown)
  failures.times { |index| trip(circuit, instant_at(index.seconds)) }
  circuit
end

describe Fusebox::Circuit do
  describe "#acquire" do
    context "when the circuit is closed" do
      it "admits the call" do
        circuit = build_circuit

        circuit.acquire.admission.should eq(Fusebox::Admission::Closed)
      end
    end

    context "when the circuit is open" do
      it "rejects the call" do
        circuit = open_circuit(cooldown: 5.seconds)

        circuit.acquire(instant_at(2.seconds)).admission.should eq(Fusebox::Admission::Rejected)
      end

      it "reports the remaining cooldown" do
        circuit = open_circuit(failures: 1, cooldown: 5.seconds)

        ticket = circuit.acquire(instant_at(2.seconds))

        ticket.remaining.should eq(3.seconds)
      end

      it "admits a half-open probe after the cooldown elapses" do
        circuit = open_circuit(failures: 1, cooldown: 1.second)

        circuit.acquire(instant_at(1.second)).admission.should eq(Fusebox::Admission::HalfOpenProbe)
      end

      it "rejects concurrent calls while a half-open probe is in flight" do
        circuit = open_circuit(failures: 1, cooldown: 1.second)
        circuit.acquire(instant_at(1.second))

        circuit.acquire(instant_at(1.second)).admission.should eq(Fusebox::Admission::Rejected)
      end
    end
  end

  describe "#record_failure" do
    context "when failures stay below the threshold" do
      it "keeps the circuit closed" do
        circuit = build_circuit(failures: 2)

        trip(circuit)

        circuit.state.should eq(Fusebox::State::Closed)
      end
    end

    context "when failures reach the threshold" do
      it "opens the circuit" do
        circuit = build_circuit(failures: 2)

        trip(circuit, instant_at(Time::Span.zero))
        trip(circuit, instant_at(1.second))

        circuit.state(instant_at(1.second)).should eq(Fusebox::State::Open)
      end
    end

    context "when failures fall outside the sliding window" do
      it "ignores the expired failures" do
        circuit = build_circuit(failures: 2, within: 1.second)

        trip(circuit, instant_at(Time::Span.zero))
        trip(circuit, instant_at(2.seconds))

        circuit.state(instant_at(2.seconds)).should eq(Fusebox::State::Closed)
      end

      it "opens when enough failures fall inside the window" do
        circuit = build_circuit(failures: 2, within: 1.second)

        trip(circuit, instant_at(Time::Span.zero))
        trip(circuit, instant_at(2.seconds))
        trip(circuit, instant_at(2.5.seconds))

        circuit.state(instant_at(2.5.seconds)).should eq(Fusebox::State::Open)
      end
    end

    context "when a success resets consecutive failures" do
      it "does not open on a later isolated failure" do
        circuit = build_circuit(failures: 2)
        ticket = circuit.acquire(instant_at(Time::Span.zero))

        circuit.record_failure(ticket, instant_at(Time::Span.zero))
        circuit.record_success(ticket)
        circuit.record_failure(ticket, instant_at(1.second))

        circuit.state(instant_at(1.second)).should eq(Fusebox::State::Closed)
      end
    end

    context "when a half-open probe fails" do
      it "reopens the circuit immediately" do
        circuit = open_circuit(failures: 1, cooldown: 1.second)
        probe = circuit.acquire(instant_at(1.second))

        circuit.record_failure(probe, instant_at(1.second)).should eq(:opened)
      end
    end
  end

  describe "#record_success" do
    context "when a half-open probe succeeds" do
      it "closes the circuit" do
        circuit = open_circuit(failures: 1, cooldown: 1.second)
        probe = circuit.acquire(instant_at(1.second))

        circuit.record_success(probe).should eq(:closed)
      end

      it "clears the failure history" do
        circuit = open_circuit(failures: 2, cooldown: 1.second)
        probe = circuit.acquire(instant_at(2.seconds))
        circuit.record_success(probe)
        ticket = circuit.acquire(instant_at(2.seconds))

        circuit.record_failure(ticket, instant_at(2.seconds)).should eq(:none)
      end
    end
  end

  describe "#state" do
    context "when the cooldown has elapsed" do
      it "reports half-open" do
        circuit = open_circuit(failures: 1, cooldown: 1.second)

        circuit.state(instant_at(1.second)).should eq(Fusebox::State::HalfOpen)
      end
    end

    context "when the cooldown has not elapsed" do
      it "reports open" do
        circuit = open_circuit(failures: 1, cooldown: 1.second)

        circuit.state(instant_at(0.5.seconds)).should eq(Fusebox::State::Open)
      end
    end
  end
end
