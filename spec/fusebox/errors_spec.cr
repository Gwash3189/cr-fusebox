require "../spec_helper"

describe Fusebox::CircuitOpenError do
  describe "#initialize" do
    it "stores the circuit key" do
      error = Fusebox::CircuitOpenError.new("payments", 1.5.seconds)

      error.key.should eq("payments")
    end

    it "stores the remaining cooldown" do
      error = Fusebox::CircuitOpenError.new("payments", 1.5.seconds)

      error.remaining.should eq(1.5.seconds)
    end

    it "describes the circuit and remaining cooldown" do
      error = Fusebox::CircuitOpenError.new("payments", 1.5.seconds)

      error.message.to_s.should contain("payments")
    end

    it "clamps a negative remaining cooldown to zero" do
      error = Fusebox::CircuitOpenError.new("payments", -1.second)

      error.remaining.should eq(Time::Span.zero)
    end

    it "is a Fusebox error" do
      error = Fusebox::CircuitOpenError.new("payments")

      error.should be_a(Fusebox::Error)
    end
  end
end
