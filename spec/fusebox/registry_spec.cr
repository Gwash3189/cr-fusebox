require "../spec_helper"

private def config(key : String) : Fusebox::Config
  Fusebox::Config.new(key: key, failures: 1, cooldown: 1.second)
end

describe Fusebox do
  describe ".circuit_for" do
    it "returns the same circuit for the same key" do
      first = Fusebox.circuit_for(config("payments"))
      second = Fusebox.circuit_for(config("payments"))

      second.should be(first)
    end

    it "returns distinct circuits for different keys" do
      payments = Fusebox.circuit_for(config("payments"))
      shipping = Fusebox.circuit_for(config("shipping"))

      shipping.should_not be(payments)
    end
  end

  describe ".state" do
    it "reports an unknown circuit as closed" do
      Fusebox.state("unknown").should eq(Fusebox::State::Closed)
    end

    it "reports the state of a registered circuit" do
      circuit = Fusebox.circuit_for(config("payments"))
      circuit.record_failure(circuit.acquire)

      Fusebox.state("payments").should eq(Fusebox::State::Open)
    end
  end

  describe ".reset" do
    it "removes a single circuit" do
      circuit = Fusebox.circuit_for(config("payments"))
      circuit.record_failure(circuit.acquire)

      Fusebox.reset("payments")

      Fusebox.state("payments").should eq(Fusebox::State::Closed)
    end
  end

  describe ".reset_all" do
    it "removes every circuit" do
      payments = Fusebox.circuit_for(config("payments"))
      shipping = Fusebox.circuit_for(config("shipping"))
      payments.record_failure(payments.acquire)
      shipping.record_failure(shipping.acquire)

      Fusebox.reset_all

      Fusebox.state("payments").should eq(Fusebox::State::Closed)
      Fusebox.state("shipping").should eq(Fusebox::State::Closed)
    end
  end
end
