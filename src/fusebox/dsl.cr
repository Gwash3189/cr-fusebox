module Fusebox
  # Internal annotation used to carry a breaker declaration from the `breaker`
  # macro to the `finished` hook that emits the method wrappers.
  annotation Declaration
  end

  # Invokes an optional lifecycle handler.
  #
  # The handler may be defined with zero arguments or with one argument:
  # the error for failure/open/reject events, or the circuit key for
  # close/half-open events. Handler exceptions are deliberately swallowed so
  # observability hooks can never alter the protected call path.
  macro fusebox_invoke_handler(handler, argument)
    {% handler_methods = @type.methods.select { |method| method.name == handler.id } %}
    {% takes_argument = handler_methods.empty? || handler_methods.any? { |method| method.args.size > 0 || method.splat_index || method.double_splat } %}
    begin
      {% if takes_argument %}
        {{handler.id}}({{argument}})
      {% else %}
        {{handler.id}}
      {% end %}
    rescue
    end
  end

  # Invokes a configured fallback. The fallback may take the error as its only
  # argument, or take no arguments at all.
  macro fusebox_fallback(fallback, error)
    {% fallback_methods = @type.methods.select { |method| method.name == fallback.id } %}
    {% takes_argument = fallback_methods.empty? || fallback_methods.any? { |method| method.args.size > 0 || method.splat_index || method.double_splat } %}
    {% if takes_argument %}
      return {{fallback.id}}({{error}})
    {% else %}
      return {{fallback.id}}
    {% end %}
  end

  # Declares a circuit breaker around an instance method.
  #
  # ```
  # class Payments
  #   include Fusebox
  #
  #   breaker :charge,
  #     failures: 5,
  #     within: 10.seconds,
  #     cooldown: 30.seconds,
  #     fallback: :charge_fallback,
  #     on_open: :circuit_opened
  #
  #   def charge(amount : Int32) : String
  #     # ...
  #   end
  # end
  # ```
  macro breaker(method_name, **options)
    {% unless method_name.is_a?(SymbolLiteral) %}
      {% raise "breaker expects a symbol method name, e.g. `breaker :perform`" %}
    {% end %}

    {% allowed_names = ["failures", "within", "cooldown", "fallback", "on_open", "on_half_open", "on_close", "on_failure", "on_reject", "key"] %}
    {% for option_name in options.keys %}
      {% unless allowed_names.includes?(option_name.stringify) %}
        {% raise "unknown breaker option `#{option_name.stringify}` for #{@type}##{method_name.id}" %}
      {% end %}
    {% end %}

    {% suffix = method_name.id.stringify.gsub(/[^A-Za-z0-9_]/, "_") %}
    {% default_key = "#{@type.name}##{method_name.id}" %}
    {% key_expression = options[:key] ? options[:key] : default_key %}

    @[::Fusebox::Declaration(
      target: {{method_name}},
      fallback: {{options[:fallback] || nil}},
      on_open: {{options[:on_open] || nil}},
      on_half_open: {{options[:on_half_open] || nil}},
      on_close: {{options[:on_close] || nil}},
      on_failure: {{options[:on_failure] || nil}},
      on_reject: {{options[:on_reject] || nil}},
    )]
    private def __fusebox_config_{{suffix.id}}
      ::Fusebox::Config.new(
        key: ({{key_expression}}).to_s,
        failures: {{options[:failures] || 5}},
        {% if options[:within] %}within: {{options[:within]}},{% end %}
        cooldown: {{options[:cooldown] || 30.seconds}},
      )
    end
  end

  macro included
    {% verbatim do %}
      macro finished
        {% for config_method in @type.methods %}
          {% if config_method.name.stringify.starts_with?("__fusebox_config_") %}
            {% declaration = config_method.annotation(::Fusebox::Declaration) %}
            {% if declaration %}
              {% target = declaration[:target] %}
              {% target_methods = @type.methods.select { |method| method.name == target.id } %}

              {% if target_methods.empty? %}
                {% raise "breaker target `#{target.id}` was not found as an instance method on #{@type}" %}
              {% end %}

              {% for method in target_methods %}
                {% if method.abstract? %}
                  {% raise "cannot wrap abstract method #{@type}##{method.name}" %}
                {% end %}

                {% captured_block = method.block_arg && method.block_arg.internal_name.stringify != "" %}
                {% if captured_block && !method.block_arg.restriction %}
                  {% raise "cannot wrap #{@type}##{method.name}: give the captured block parameter a type or use an anonymous `&` block" %}
                {% end %}

                {% if method.visibility == :private %}private{% elsif method.visibility == :protected %}protected{% end %} def {{method.name}}(
                  {% for argument, index in method.args %}
                    {% if method.splat_index && index == method.splat_index %}
                      *{{argument.internal_name}}{% if argument.restriction %} : {{argument.restriction}}{% end %},
                    {% else %}
                      {% if argument.name.stringify != argument.internal_name.stringify %}{{argument.name}} {% end %}{{argument.internal_name}}{% if argument.restriction %} : {{argument.restriction}}{% end %}{% if argument.default_value %} = {{argument.default_value}}{% end %},
                    {% end %}
                  {% end %}
                  {% if method.double_splat %}**{{method.double_splat.internal_name}},{% end %}
                  {% if captured_block %}&__fusebox_block : {{method.block_arg.restriction}}{% elsif method.accepts_block? %}&{% end %}
                )
                  __fusebox_config = __fusebox_config_{{config_method.name.stringify.gsub(/__fusebox_config_/, "").id}}
                  __fusebox_circuit = ::Fusebox.circuit_for(__fusebox_config)
                  __fusebox_ticket = __fusebox_circuit.acquire

                  if __fusebox_ticket.rejected?
                    __fusebox_error = ::Fusebox::CircuitOpenError.new(__fusebox_config.key, __fusebox_ticket.remaining)

                    {% if declaration[:on_reject] %}
                      fusebox_invoke_handler({{declaration[:on_reject]}}, __fusebox_error)
                    {% end %}

                    {% if declaration[:fallback] %}
                      fusebox_fallback({{declaration[:fallback]}}, __fusebox_error)
                    {% else %}
                      raise __fusebox_error
                    {% end %}
                  end

                  {% if declaration[:on_half_open] %}
                    if __fusebox_ticket.half_open?
                      fusebox_invoke_handler({{declaration[:on_half_open]}}, __fusebox_config.key)
                    end
                  {% end %}

                  begin
                    __fusebox_result = previous_def(
                      {% for argument, index in method.args %}
                        {% if method.splat_index && index == method.splat_index %}
                          {% if argument.internal_name.stringify != "" %}*{{argument.internal_name}},{% end %}
                        {% elsif method.splat_index && index > method.splat_index %}
                          {{argument.name}}: {{argument.internal_name}},
                        {% else %}
                          {{argument.internal_name}},
                        {% end %}
                      {% end %}
                      {% if method.double_splat %}**{{method.double_splat.internal_name}},{% end %}
                      {% if captured_block %}&__fusebox_block{% end %}
                    ){% if method.accepts_block? && !captured_block %} { |*__fusebox_block_args| yield *__fusebox_block_args }{% end %}
                  rescue __fusebox_error : Exception
                    {% if declaration[:on_failure] %}
                      fusebox_invoke_handler({{declaration[:on_failure]}}, __fusebox_error)
                    {% end %}

                    __fusebox_transition = __fusebox_circuit.record_failure(__fusebox_ticket)
                    if __fusebox_transition == :opened
                      {% if declaration[:on_open] %}
                        fusebox_invoke_handler({{declaration[:on_open]}}, __fusebox_error)
                      {% end %}
                    end

                    {% if declaration[:fallback] %}
                      fusebox_fallback({{declaration[:fallback]}}, __fusebox_error)
                    {% else %}
                      raise __fusebox_error
                    {% end %}
                  else
                    __fusebox_transition = __fusebox_circuit.record_success(__fusebox_ticket)
                    if __fusebox_transition == :closed
                      {% if declaration[:on_close] %}
                        fusebox_invoke_handler({{declaration[:on_close]}}, __fusebox_config.key)
                      {% end %}
                    end

                    __fusebox_result
                  end
                end
              {% end %}
            {% end %}
          {% end %}
        {% end %}
      end
    {% end %}
  end
end
