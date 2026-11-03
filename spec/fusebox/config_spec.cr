require "../spec_helper"

describe Fusebox::Config do
  describe "#initialize" do
    context "when only a key is provided" do
      it "uses a threshold of five failures" do
        config = Fusebox::Config.new(key: "payments")

        config.failures.should eq(5)
      end

      it "tracks consecutive failures" do
        config = Fusebox::Config.new(key: "payments")

        config.within.should be_nil
      end

      it "uses a thirty second cooldown" do
        config = Fusebox::Config.new(key: "payments")

        config.cooldown.should eq(30.seconds)
      end
    end

    context "when custom values are provided" do
      it "stores the failure window" do
        config = Fusebox::Config.new(key: "payments", within: 10.seconds)

        config.within.should eq(10.seconds)
      end

      it "stores the cooldown" do
        config = Fusebox::Config.new(key: "payments", cooldown: 45.seconds)

        config.cooldown.should eq(45.seconds)
      end
    end

    context "when the key is blank" do
      it "raises an argument error" do
        expect_raises(ArgumentError) do
          Fusebox::Config.new(key: "   ")
        end
      end
    end

    context "when the failure threshold is less than one" do
      it "raises an argument error" do
        expect_raises(ArgumentError) do
          Fusebox::Config.new(key: "payments", failures: 0)
        end
      end
    end

    context "when the failure window is not positive" do
      it "raises an argument error" do
        expect_raises(ArgumentError) do
          Fusebox::Config.new(key: "payments", within: Time::Span.zero)
        end
      end
    end

    context "when the cooldown is negative" do
      it "raises an argument error" do
        expect_raises(ArgumentError) do
          Fusebox::Config.new(key: "payments", cooldown: -1.second)
        end
      end
    end
  end
end
