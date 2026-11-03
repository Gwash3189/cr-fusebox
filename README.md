# cr-fusebox

[![CI](https://github.com/Gwash3189/cr-fusebox/actions/workflows/ci.yml/badge.svg)](https://github.com/Gwash3189/cr-fusebox/actions/workflows/ci.yml)

A declarative circuit breaker shard for Crystal. Wrap instance methods with
failure thresholds, sliding windows, cooldown recovery, fallbacks, and lifecycle
hooks.

## Installation

Add it to your `shard.yml`:

```yaml
dependencies:
  cr-fusebox:
    github: Gwash3189/cr-fusebox
    version: ~> 0.1.0
```

Then run:

```bash
shards install
```

And require it:

```crystal
require "cr-fusebox"
```

## Usage

```crystal
class Payments
  include Fusebox

  breaker :charge,
    failures: 5,
    within: 10.seconds,
    cooldown: 30.seconds,
    fallback: :charge_fallback,
    on_open: :circuit_opened,
    on_half_open: :circuit_half_opened,
    on_close: :circuit_closed

  def charge(amount : Int32) : String
    # call the downstream payment service
  end

  def charge_fallback(error : Exception) : String
    "cached"
  end

  def circuit_opened(error : Exception)
    # alert, log, or emit a metric
  end

  def circuit_half_opened
    # a probe is about to run
  end

  def circuit_closed
    # the downstream service recovered
  end
end
```

The `breaker` declaration may appear before or after the method definition.

## Options

| Option | Default | Description |
| --- | --- | --- |
| `failures` | `5` | Number of failures required to open the circuit. Must be at least 1. |
| `within` | `nil` | Optional `Time::Span` sliding window. When omitted, failures must be consecutive. |
| `cooldown` | `30.seconds` | How long the circuit stays open before allowing a half-open probe. |
| `fallback` | none | Method called when the work fails or the circuit is open. |
| `on_open` | none | Called when the circuit transitions to open. |
| `on_half_open` | none | Called when a half-open probe starts. |
| `on_close` | none | Called when a successful probe closes the circuit. |
| `on_failure` | none | Called for every failed protected call. |
| `on_reject` | none | Called when a call is rejected because the circuit is open. |
| `key` | `"ClassName#method_name"` | Circuit registry key. |

## Circuit states

1. **Closed** — calls pass through. Failures are tracked within `within`, or
   consecutively when `within` is omitted.
2. **Open** — calls fail fast with `Fusebox::CircuitOpenError` without invoking
   the wrapped method. If a `fallback` is configured, its value is returned
   instead.
3. **Half-open** — after `cooldown` elapses, exactly one probe call is allowed.
   A successful probe closes the circuit. A failed probe immediately reopens it.
   Concurrent calls while the probe is in flight are rejected.

## Handlers and fallbacks

Error-oriented handlers (`on_open`, `on_failure`, `on_reject`) may be defined
with zero arguments or with one `Exception` argument:

```crystal
def circuit_opened(error : Exception)
end

# or

def circuit_opened
end
```

`on_half_open` and `on_close` may be defined with zero arguments or with the
circuit key:

```crystal
def circuit_closed(key : String)
end

# or

def circuit_closed
end
```

A fallback may receive the error or take no arguments:

```crystal
def charge_fallback(error : Exception)
  "cached"
end

# or

def charge_fallback
  "cached"
end
```

Handler exceptions are rescued so lifecycle hooks cannot break the protected
call path. Fallback exceptions are not rescued.

## Sharing and custom keys

By default, one circuit is shared by every instance of a class for a given
method, keyed by `"ClassName#method_name"`:

```crystal
Fusebox.state("Payments#charge")
```

Use `key:` when a different scope is needed:

```crystal
breaker :charge, key: "stripe-api", failures: 5

# Per-tenant circuits are also possible because key is evaluated per call:
breaker :charge, key: "tenant-#{@tenant_id}", failures: 5
```

## Inspecting and resetting circuits

```crystal
state = Fusebox.state("Payments#charge")
state.closed?
state.open?
state.half_open?

Fusebox.reset("Payments#charge")
Fusebox.reset_all
```

## Supported method shapes

The wrapper preserves the original method signature and forwards calls through
`previous_def`, including:

- overloaded methods
- default and named arguments
- splat and double-splat arguments
- `yield`-based blocks
- typed captured blocks
- private and protected methods
- method names such as `valid?`

## Limitations

- Only instance methods can be wrapped.
- The wrapped method must be declared on the same type that calls `breaker`.
- Abstract methods are rejected at compile time.
- A captured block parameter must have a type restriction. Use an anonymous
  `&` block or `yield` when the block is not captured.
- `break` and `next` inside a typed captured block follow Crystal's normal
  captured-block rules. Prefer `yield`-based methods when those semantics matter.

## Development

```bash
shards install
crystal spec
crystal tool format --check
```

To generate a coverage report on Linux, install [kcov](https://github.com/SimonKagstrom/kcov)
and run:

```bash
./bin/coverage
```

## License

MIT
