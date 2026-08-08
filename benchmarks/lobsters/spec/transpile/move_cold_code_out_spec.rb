require "rails_helper"

# Behavioural lock for the `move_cold_code_out` transpile run.
#
# The run rewrote Keystore.validate_input_key so that the
# ActiveRecord::ValueTooLong instance is built only on the failing branch
# instead of on every call. These examples pin the observable behaviour of
# that method, and of the four public callers that reach it, to what HEAD
# produced before the rewrite.
describe "Keystore.validate_input_key (move_cold_code_out)" do
  let(:max) { Keystore::MAX_KEY_LENGTH }
  let(:too_long_message) { "#{Keystore::MAX_KEY_LENGTH} characters is the maximum allowed for key" }

  it "has MAX_KEY_LENGTH == 50" do
    expect(max).to eq(50)
  end

  describe "signature" do
    it "takes exactly one required positional argument" do
      m = Keystore.method(:validate_input_key)
      expect(m.arity).to eq(1)
      expect(m.parameters).to eq([[:req, :key]])
    end

    it "raises ArgumentError with no argument" do
      expect { Keystore.validate_input_key }
        .to raise_error(ArgumentError, "wrong number of arguments (given 0, expected 1)")
    end

    it "raises ArgumentError with two arguments" do
      expect { Keystore.validate_input_key("a", "b") }
        .to raise_error(ArgumentError, "wrong number of arguments (given 2, expected 1)")
    end

    it "treats a keyword argument as a second positional argument" do
      expect { Keystore.validate_input_key("a", foo: 1) }
        .to raise_error(ArgumentError, "wrong number of arguments (given 2, expected 1)")
    end
  end

  describe "keys at or below the limit" do
    it "returns nil for an empty string" do
      expect(Keystore.validate_input_key("")).to be_nil
    end

    it "returns nil for a one character key" do
      expect(Keystore.validate_input_key("a")).to be_nil
    end

    it "returns nil one character below the limit" do
      expect(Keystore.validate_input_key("a" * (max - 1))).to be_nil
    end

    it "returns nil exactly at the limit" do
      expect(Keystore.validate_input_key("a" * max)).to be_nil
    end

    it "returns nil for a frozen key at the limit" do
      expect(Keystore.validate_input_key(("a" * max).freeze)).to be_nil
    end

    it "counts characters, not bytes, for a multibyte key at the limit" do
      key = "é" * max
      expect(key.bytesize).to be > max
      expect(Keystore.validate_input_key(key)).to be_nil
    end

    it "returns the identical nil object on repeated calls" do
      first = Keystore.validate_input_key("a")
      second = Keystore.validate_input_key("bb")
      expect(first).to be_nil
      expect(first).to equal(second)
    end

    it "does not mutate the key" do
      key = +("a" * max)
      Keystore.validate_input_key(key)
      expect(key).to eq("a" * max)
      expect(key).not_to be_frozen
    end

    it "ignores a block" do
      ran = false
      expect(Keystore.validate_input_key("a") { ran = true }).to be_nil
      expect(ran).to be(false)
    end
  end

  describe "keys above the limit" do
    it "raises ActiveRecord::ValueTooLong one character above the limit" do
      expect { Keystore.validate_input_key("a" * (max + 1)) }
        .to raise_error(ActiveRecord::ValueTooLong, too_long_message)
    end

    it "raises ActiveRecord::ValueTooLong for a very long key" do
      expect { Keystore.validate_input_key("a" * 5000) }
        .to raise_error(ActiveRecord::ValueTooLong, too_long_message)
    end

    it "raises for a frozen key above the limit" do
      expect { Keystore.validate_input_key(("a" * (max + 1)).freeze) }
        .to raise_error(ActiveRecord::ValueTooLong, too_long_message)
    end

    it "raises for a multibyte key above the limit" do
      expect { Keystore.validate_input_key("é" * (max + 1)) }
        .to raise_error(ActiveRecord::ValueTooLong, too_long_message)
    end

    it "raises even when a block is given" do
      ran = false
      expect { Keystore.validate_input_key("a" * (max + 1)) { ran = true } }
        .to raise_error(ActiveRecord::ValueTooLong, too_long_message)
      expect(ran).to be(false)
    end

    it "raises an exception that is a StatementInvalid, with no cause and a backtrace" do
      error = nil
      begin
        Keystore.validate_input_key("a" * (max + 1))
      rescue ActiveRecord::ValueTooLong => e
        error = e
      end

      expect(error).to be_a(ActiveRecord::ValueTooLong)
      expect(error).to be_a(ActiveRecord::StatementInvalid)
      expect(error).to be_a(ActiveRecord::ActiveRecordError)
      expect(error.message).to eq(too_long_message)
      expect(error.cause).to be_nil
      expect(error.backtrace).not_to be_nil
    end

    it "builds a distinct exception instance per raise" do
      errors = 2.times.map do
        begin
          Keystore.validate_input_key("a" * (max + 1))
          nil
        rescue ActiveRecord::ValueTooLong => e
          e
        end
      end

      expect(errors[0]).not_to equal(errors[1])
    end
  end

  describe "receivers that do not answer #length" do
    it "raises NoMethodError for nil" do
      expect { Keystore.validate_input_key(nil) }
        .to raise_error(NoMethodError, /undefined method .length. for nil/)
    end

    it "raises NoMethodError for false" do
      expect { Keystore.validate_input_key(false) }
        .to raise_error(NoMethodError, /undefined method .length. for false/)
    end

    it "raises NoMethodError for an Integer" do
      expect { Keystore.validate_input_key(42) }
        .to raise_error(NoMethodError, /undefined method .length./)
    end
  end

  describe "collections, which also answer #length" do
    it "returns nil for an empty array" do
      expect(Keystore.validate_input_key([])).to be_nil
    end

    it "returns nil for a one element array" do
      expect(Keystore.validate_input_key([nil])).to be_nil
    end

    it "returns nil for an empty hash" do
      expect(Keystore.validate_input_key({})).to be_nil
    end

    it "raises for an oversized array of duplicates" do
      expect { Keystore.validate_input_key(Array.new(max + 1, :x)) }
        .to raise_error(ActiveRecord::ValueTooLong, too_long_message)
    end

    it "raises for an oversized array holding nils" do
      expect { Keystore.validate_input_key(Array.new(max + 1)) }
        .to raise_error(ActiveRecord::ValueTooLong, too_long_message)
    end

    it "returns nil for a short symbol" do
      expect(Keystore.validate_input_key(:abc)).to be_nil
    end

    it "raises for an oversized symbol" do
      expect { Keystore.validate_input_key(("a" * (max + 1)).to_sym) }
        .to raise_error(ActiveRecord::ValueTooLong, too_long_message)
    end
  end

  describe "evaluation of #length" do
    it "calls #length exactly once on the accepted path" do
      key = "a" * max
      allow(key).to receive(:length).and_call_original
      Keystore.validate_input_key(key)
      expect(key).to have_received(:length).once
    end

    it "calls #length exactly once on the rejected path" do
      key = "a" * (max + 1)
      allow(key).to receive(:length).and_call_original
      expect { Keystore.validate_input_key(key) }
        .to raise_error(ActiveRecord::ValueTooLong, too_long_message)
      expect(key).to have_received(:length).once
    end

    it "propagates an error raised by #length unchanged" do
      key = "a" * max
      allow(key).to receive(:length).and_raise(ArgumentError, "boom from length")
      expect { Keystore.validate_input_key(key) }
        .to raise_error(ArgumentError, "boom from length")
    end
  end

  describe "public callers that reach validate_input_key" do
    let(:long_key) { "a" * (max + 1) }

    it "Keystore.put rejects a long key" do
      expect { Keystore.put(long_key, 1) }
        .to raise_error(ActiveRecord::ValueTooLong, too_long_message)
    end

    it "Keystore.put rejects a nil key" do
      expect { Keystore.put(nil, 1) }
        .to raise_error(NoMethodError, /undefined method .length. for nil/)
    end

    it "Keystore.put accepts a key at the limit and returns true" do
      key = "a" * max
      expect(Keystore.put(key, 7)).to be(true)
      expect(Keystore.value_for(key)).to eq(7)
    end

    it "Keystore.incremented_value_for rejects a long key" do
      expect { Keystore.incremented_value_for(long_key, 1) }
        .to raise_error(ActiveRecord::ValueTooLong, too_long_message)
    end

    it "Keystore.incremented_value_for rejects a nil key" do
      expect { Keystore.incremented_value_for(nil, 1) }
        .to raise_error(NoMethodError, /undefined method .length. for nil/)
    end

    it "Keystore.incremented_value_for accepts a key at the limit" do
      key = "b" * max
      expect(Keystore.incremented_value_for(key, 3)).to eq(3)
      expect(Keystore.incremented_value_for(key, 4)).to eq(7)
    end

    it "Keystore.increment_value_for rejects a long key" do
      expect { Keystore.increment_value_for(long_key) }
        .to raise_error(ActiveRecord::ValueTooLong, too_long_message)
    end

    it "Keystore.decrement_value_for rejects a long key" do
      expect { Keystore.decrement_value_for(long_key) }
        .to raise_error(ActiveRecord::ValueTooLong, too_long_message)
    end

    it "Keystore.decremented_value_for rejects a long key" do
      expect { Keystore.decremented_value_for(long_key) }
        .to raise_error(ActiveRecord::ValueTooLong, too_long_message)
    end

    it "Keystore.readthrough_cache runs the block once, then fails on the long key" do
      runs = 0
      expect do
        Keystore.readthrough_cache(long_key) do
          runs += 1
          5
        end
      end.to raise_error(ActiveRecord::ValueTooLong, too_long_message)
      expect(runs).to eq(1)
    end

    it "Keystore.readthrough_cache stores and returns the block value for a valid key" do
      key = "c" * max
      runs = 0
      value = Keystore.readthrough_cache(key) do
        runs += 1
        11
      end
      expect(value).to eq(11)
      expect(runs).to eq(1)
      expect(Keystore.readthrough_cache(key) { runs += 1 }).to eq(11)
      expect(runs).to eq(1)
    end
  end
end
