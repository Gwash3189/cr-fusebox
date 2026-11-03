require "../spec_helper"

class BasicService
  include Fusebox

  getter calls = 0

  breaker :perform, failures: 2, cooldown: 1.second

  def perform(value : Int32) : Int32
    @calls += 1
    value * 2
  end
end

class OpenService
  include Fusebox

  getter calls = 0

  breaker :perform, failures: 1, cooldown: 1.second

  def perform(value : Int32) : Int32
    @calls += 1
    raise ArgumentError.new("boom") if value < 0

    value
  end
end

class FallbackService
  include Fusebox

  getter calls = 0
  getter events = [] of Symbol

  breaker :perform,
    failures: 1,
    cooldown: 1.second,
    fallback: :fallback,
    on_open: :opened,
    on_half_open: :half_opened,
    on_close: :closed_event,
    on_failure: :failed,
    on_reject: :rejected

  def perform(value : Int32) : Int32
    @calls += 1
    raise ArgumentError.new("boom") if value < 0

    value
  end

  def fallback(error : Exception) : Int32
    -1
  end

  def opened(error : Exception)
    @events << :open
  end

  def half_opened(key : String)
    @events << :half_open
  end

  def closed_event
    @events << :close
  end

  def failed(error : Exception)
    @events << :failure
  end

  def rejected(error : Fusebox::CircuitOpenError)
    @events << :reject
  end
end

class RecoveryService
  include Fusebox

  getter events = [] of Symbol

  breaker :perform,
    failures: 1,
    cooldown: 0.seconds,
    on_open: :opened_event,
    on_half_open: :half_opened,
    on_close: :closed_event

  def perform(value : Int32) : Int32
    raise ArgumentError.new("boom") if value < 0

    value
  end

  def opened_event(error : Exception)
    @events << :open
  end

  def half_opened
    @events << :half_open
  end

  def closed_event
    @events << :close
  end
end

class ZeroFallbackService
  include Fusebox

  breaker :perform, failures: 1, cooldown: 1.second, fallback: :fallback

  def perform
    raise ArgumentError.new("boom")
  end

  def fallback
    :fallback
  end
end

class ForwardingService
  include Fusebox

  breaker :basic, failures: 3, cooldown: 1.second
  breaker :with_default, failures: 3, cooldown: 1.second
  breaker :with_splat, failures: 3, cooldown: 1.second
  breaker :with_options, failures: 3, cooldown: 1.second
  breaker :with_named, failures: 3, cooldown: 1.second
  breaker :with_external_name, failures: 3, cooldown: 1.second
  breaker :with_yield, failures: 3, cooldown: 1.second
  breaker :with_block, failures: 3, cooldown: 1.second
  breaker :question?, failures: 3, cooldown: 1.second
  breaker :secret, failures: 3, cooldown: 1.second

  def basic(value : Int32) : Int32
    value + 1
  end

  def with_default(value : Int32, prefix : String = "v") : String
    "#{prefix}#{value}"
  end

  def with_splat(value : Int32, *rest : String) : String
    "#{value}:#{rest.join(",")}"
  end

  def with_options(value : Int32, **options) : String
    "#{value}:#{options.size}"
  end

  def with_named(value : Int32, *, flag : Bool = false) : String
    "#{value}:#{flag}"
  end

  def with_external_name(to value : Int32) : String
    "#{value}:#{value}"
  end

  def with_yield(value : Int32, &) : String
    yield value
  end

  def with_block(value : Int32, &block : Int32 -> String) : String
    block.call(value)
  end

  def question?(value : Int32) : Bool
    value > 0
  end

  private def secret : String
    "secret"
  end

  def call_secret : String
    secret
  end
end

class CustomKeyService
  include Fusebox

  breaker :perform, key: "custom-key", failures: 1, cooldown: 1.second

  def perform(value : Int32) : Int32
    raise ArgumentError.new("boom") if value < 0

    value
  end
end

class HandlerFailureService
  include Fusebox

  breaker :perform, failures: 1, cooldown: 1.second, on_open: :on_open

  def perform(value : Int32) : Int32
    raise ArgumentError.new("work failure") if value < 0

    value
  end

  def on_open(error : Exception)
    raise "handler failure"
  end
end

class ConcurrentService
  include Fusebox

  property gate : Channel(Nil)?
  property entered : Channel(Nil)?

  breaker :perform, failures: 1, cooldown: 0.seconds

  def perform(value : Int32) : Symbol
    raise ArgumentError.new("trip") if value < 0

    @entered.try &.send(nil)
    @gate.try &.receive
    :ok
  end
end

describe "breaker macro" do
  describe "#perform" do
    context "when the circuit is closed" do
      it "returns the wrapped method result" do
        service = BasicService.new

        service.perform(2).should eq(4)
      end

      it "invokes the wrapped method" do
        service = BasicService.new

        service.perform(2)

        service.calls.should eq(1)
      end

      it "keeps the circuit closed" do
        service = BasicService.new

        service.perform(2)

        Fusebox.state("BasicService#perform").should eq(Fusebox::State::Closed)
      end
    end

    context "when failures reach the threshold" do
      it "opens the circuit" do
        service = OpenService.new

        expect_raises(ArgumentError) { service.perform(-1) }

        Fusebox.state("OpenService#perform").should eq(Fusebox::State::Open)
      end

      it "fails fast without invoking the wrapped method" do
        service = OpenService.new
        expect_raises(ArgumentError) { service.perform(-1) }

        expect_raises(Fusebox::CircuitOpenError) { service.perform(1) }

        service.calls.should eq(1)
      end

      it "raises a circuit open error" do
        service = OpenService.new
        expect_raises(ArgumentError) { service.perform(-1) }

        expect_raises(Fusebox::CircuitOpenError) { service.perform(1) }
      end
    end

    context "when a fallback is configured" do
      it "returns the fallback value when the work fails" do
        service = FallbackService.new

        service.perform(-1).should eq(-1)
      end

      it "returns the fallback value when the circuit is open" do
        service = FallbackService.new
        service.perform(-1)

        service.perform(1).should eq(-1)
      end

      it "does not invoke the wrapped method while open" do
        service = FallbackService.new
        service.perform(-1)

        service.perform(1)

        service.calls.should eq(1)
      end

      it "supports a fallback without arguments" do
        service = ZeroFallbackService.new

        service.perform.should eq(:fallback)
      end
    end

    context "when lifecycle handlers are configured" do
      it "invokes the failure handler before opening" do
        service = FallbackService.new

        service.perform(-1)

        service.events.should eq([:failure, :open])
      end

      it "invokes the reject handler when the circuit is open" do
        service = FallbackService.new
        service.perform(-1)

        service.perform(1)

        service.events.should eq([:failure, :open, :reject])
      end

      it "invokes open, half-open, and close handlers after recovery" do
        service = RecoveryService.new
        expect_raises(ArgumentError) { service.perform(-1) }

        service.perform(1)

        service.events.should eq([:open, :half_open, :close])
      end
    end

    context "when the cooldown has elapsed" do
      it "allows one probe and closes on success" do
        service = RecoveryService.new
        expect_raises(ArgumentError) { service.perform(-1) }

        service.perform(1).should eq(1)
      end

      it "reopens when the probe fails" do
        service = RecoveryService.new
        expect_raises(ArgumentError) { service.perform(-1) }

        expect_raises(ArgumentError) { service.perform(-1) }

        service.events.count(:open).should eq(2)
      end
    end
  end

  describe "method forwarding" do
    it "forwards a basic argument" do
      ForwardingService.new.basic(1).should eq(2)
    end

    it "forwards default arguments" do
      ForwardingService.new.with_default(2).should eq("v2")
    end

    it "forwards named arguments" do
      ForwardingService.new.with_default(2, prefix: "n").should eq("n2")
    end

    it "forwards splat arguments" do
      ForwardingService.new.with_splat(1, "a", "b").should eq("1:a,b")
    end

    it "forwards double splat arguments" do
      ForwardingService.new.with_options(1, a: 1, b: 2).should eq("1:2")
    end

    it "forwards named-only arguments" do
      ForwardingService.new.with_named(1, flag: true).should eq("1:true")
    end

    it "forwards external argument names" do
      ForwardingService.new.with_external_name(to: 3).should eq("3:3")
    end

    it "forwards yield-based blocks" do
      ForwardingService.new.with_yield(3) { |value| (value * 2).to_s }.should eq("6")
    end

    it "forwards typed blocks" do
      ForwardingService.new.with_block(3) { |value| "<#{value}>" }.should eq("<3>")
    end

    it "forwards predicate method names" do
      ForwardingService.new.question?(1).should be_true
    end

    it "preserves private visibility" do
      ForwardingService.new.call_secret.should eq("secret")
    end
  end

  describe "custom circuit keys" do
    it "uses the configured key" do
      service = CustomKeyService.new
      expect_raises(ArgumentError) { service.perform(-1) }

      Fusebox.state("custom-key").should eq(Fusebox::State::Open)
    end
  end

  describe "handler failures" do
    it "does not replace the original error" do
      service = HandlerFailureService.new

      expect_raises(ArgumentError, "work failure") { service.perform(-1) }
    end

    it "still opens the circuit" do
      service = HandlerFailureService.new
      expect_raises(ArgumentError, "work failure") { service.perform(-1) }

      Fusebox.state("HandlerFailureService#perform").should eq(Fusebox::State::Open)
    end
  end

  describe "concurrent half-open probes" do
    it "rejects the second call while a probe is in flight" do
      service = ConcurrentService.new
      expect_raises(ArgumentError) { service.perform(-1) }

      gate = Channel(Nil).new
      entered = Channel(Nil).new
      done = Channel(Symbol).new
      service.gate = gate
      service.entered = entered

      spawn do
        service.perform(1)
        done.send(:ok)
      end

      entered.receive

      expect_raises(Fusebox::CircuitOpenError) { service.perform(1) }

      gate.send(nil)
      done.receive.should eq(:ok)
    end

    it "closes the circuit when the probe succeeds" do
      service = ConcurrentService.new
      expect_raises(ArgumentError) { service.perform(-1) }

      gate = Channel(Nil).new
      entered = Channel(Nil).new
      done = Channel(Symbol).new
      service.gate = gate
      service.entered = entered

      spawn do
        service.perform(1)
        done.send(:ok)
      end

      entered.receive
      gate.send(nil)
      done.receive

      Fusebox.state("ConcurrentService#perform").should eq(Fusebox::State::Closed)
    end
  end
end

describe "Fusebox.reset" do
  it "restores a specific circuit to closed" do
    service = OpenService.new
    expect_raises(ArgumentError) { service.perform(-1) }

    Fusebox.reset("OpenService#perform")

    Fusebox.state("OpenService#perform").should eq(Fusebox::State::Closed)
  end

  it "allows the wrapped method after a reset" do
    service = OpenService.new
    expect_raises(ArgumentError) { service.perform(-1) }
    Fusebox.reset("OpenService#perform")

    service.perform(5).should eq(5)
  end
end
