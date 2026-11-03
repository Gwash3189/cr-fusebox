require "spec"
require "../src/cr-fusebox"

# Every example starts with a clean registry so specs cannot leak circuit state.
Spec.before_each do
  Fusebox.reset_all
end
