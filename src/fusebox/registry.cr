module Fusebox
  @@registry = {} of String => Circuit
  @@registry_mutex = Mutex.new

  # Returns the existing circuit for the configured key, creating it on first use.
  def self.circuit_for(config : Config) : Circuit
    @@registry_mutex.synchronize do
      @@registry[config.key] ||= Circuit.new(config)
    end
  end

  # Returns the current state for `key`. Unknown keys are reported as closed.
  def self.state(key : String) : State
    circuit = @@registry_mutex.synchronize { @@registry[key]? }
    circuit ? circuit.state : State::Closed
  end

  # Removes a single circuit. The next call creates a fresh, closed circuit.
  def self.reset(key : String) : Nil
    @@registry_mutex.synchronize { @@registry.delete(key) }
  end

  # Removes every circuit.
  def self.reset_all : Nil
    @@registry_mutex.synchronize { @@registry.clear }
  end
end
