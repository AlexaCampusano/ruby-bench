# frozen_string_literal: true

# Static runtime API for Workflow C boot-time patches.
#
# Generated patch files call:
#
#   Transpiled.register(owner:, singleton:, mod:, methods:)
#
# The generator may change which patch modules call this API, but the API and
# method-level guard live here as a checked-in reference file.

require "json"
require "digest"
require "fileutils"
require "prism"

module Transpiled
  PATCH_DIR = File.expand_path(__dir__)
  MANIFEST = JSON.parse(File.read(File.join(PATCH_DIR, "manifest.json")))
  REPO_ROOT = ENV["RUBY_TRANSPILE_REPO_ROOT"] || MANIFEST["repo_root"] || Dir.pwd

  module Patches
  end

  @applied = []
  @declined = []
  @registered = []

  class << self
    attr_reader :applied, :declined, :registered

    def enabled?
      ENV["TRANSPILE"] != "0"
    end

    def register(owner:, singleton:, mod:, methods:)
      @registered << { owner: owner, singleton: singleton, methods: methods.map { |m| m["display"] } }
      return unless enabled?

      if constant_defined?(owner)
        apply(owner, singleton, mod, methods)
      elsif rails_autoloader?
        Rails.autoloaders.main.on_load(owner) { apply(owner, singleton, mod, methods) }
      else
        decline_many(methods, "missing_owner")
      end
    end

    def apply(owner, singleton, mod, methods)
      target = constant_get(owner)
      patch_target = singleton ? target.singleton_class : target
      accepted = methods.select { |m| current?(m) }
      decline_many(methods - accepted, "fingerprint_mismatch")
      return if accepted.empty?

      bind_constants(target, mod, accepted)
      accepted.each do |method|
        install_replacement(patch_target, mod, method)
      end
    rescue StandardError => e
      decline_many(methods, "apply_error: #{e.class}: #{e.message}")
    end

    LOCATION_KEYS = %i[
      location name_loc save_location save_name_loc def_keyword_loc operator_loc
      lparen_loc rparen_loc equal_loc end_keyword_loc opening_loc closing_loc
      class_keyword_loc module_keyword_loc constant_path call_operator_loc
    ].freeze

    def install_replacement(patch_target, mod, method)
      name = method.fetch("name").to_sym
      active = patch_target.instance_method(name)
      unless active.owner == patch_target
        decline_many([method], "shadowed_by_existing_ancestor: #{active.owner}")
        return
      end

      patch_target.send(:define_method, name, mod.instance_method(name))
      case method["visibility"]
      when "private"
        patch_target.send(:private, name)
      when "protected"
        patch_target.send(:protected, name)
      else
        patch_target.send(:public, name)
      end
      @applied << method.merge("owner" => method["owner"], "singleton" => method["singleton"])
    rescue NameError => e
      decline_many([method], "missing_method: #{e.message}")
    rescue StandardError => e
      decline_many([method], "replace_error: #{e.class}: #{e.message}")
    end

    def bind_constants(target, mod, methods)
      Array(methods).flat_map { |method| Array(method["constants"]) }.uniq.each do |name|
        const_name = name.to_sym
        next if mod.const_defined?(const_name, false)
        next unless target.const_defined?(const_name, true)

        mod.const_set(const_name, target.const_get(const_name, true))
      end
    end

    def current?(method)
      path = absolute_path(method.fetch("path"))
      return false unless File.exist?(path)
      return true if method["file_sha"] && Digest::SHA256.file(path).hexdigest == method["file_sha"]

      current = current_fingerprint(method, path)
      current && current == method["fingerprint"]
    rescue StandardError
      false
    end

    def absolute_path(path)
      File.absolute_path(path, REPO_ROOT)
    end

    def current_fingerprint(method, path)
      found = find_method(path, method.fetch("owner"), method.fetch("singleton"), method.fetch("name"))
      return nil unless found

      Digest::SHA256.hexdigest([
        method.fetch("owner"), method.fetch("singleton"), method.fetch("name"), JSON.generate(canonical(found))
      ].join("\0"))
    end

    def find_method(path, wanted_owner, wanted_singleton, wanted_name)
      result = Prism.parse_file(path)
      return nil unless result.success?

      found = nil
      walk = lambda do |node, owners, singleton_context|
        return if node.nil? || found

        case node
        when Prism::ClassNode, Prism::ModuleNode
          name = const_name(node.constant_path, owners.last)
          walk.call(node.body, owners + [name].compact, false)
          return
        when Prism::SingletonClassNode
          walk.call(node.body, owners, true)
          return
        when Prism::DefNode
          receiver = node.receiver
          singleton = singleton_context || !receiver.nil?
          owner = receiver ? const_name(receiver, owners.last) : owners.last
          owner ||= "Object"
          if owner == wanted_owner && singleton == wanted_singleton && node.name.to_s == wanted_name
            found = node
            return
          end
        end

        node.child_nodes.compact.each { |child| walk.call(child, owners, singleton_context) if child.is_a?(Prism::Node) }
      end
      walk.call(result.value, [], false)
      found
    end

    def const_name(node, current_owner)
      return current_owner if node.nil?
      return current_owner if node.is_a?(Prism::SelfNode)
      return node.name.to_s if node.respond_to?(:name) && node.class.name.end_with?("ConstantReadNode")
      if node.class.name.end_with?("ConstantPathNode")
        parent = const_name(node.parent, current_owner)
        return [parent, node.name.to_s].compact.reject(&:empty?).join("::")
      end
      nil
    end

    def canonical(value)
      case value
      when Prism::Node
        h = value.deconstruct_keys(nil).reject do |k, _|
          LOCATION_KEYS.include?(k) || k.to_s.end_with?("_loc") || k == :node_id
        end
        [value.class.name, h.sort_by { |k, _| k.to_s }.map { |k, v| [k, canonical(v)] }]
      when Array
        value.map { |v| canonical(v) }
      when Symbol, String, Integer, Float, NilClass, TrueClass, FalseClass
        value
      else
        value.to_s
      end
    end

    def decline_many(methods, reason)
      methods.each { |m| @declined << m.merge("reason" => reason) }
    end

    def constant_defined?(name)
      name.split("::").inject(Object) do |scope, part|
        return false unless scope.const_defined?(part, false)
        scope.const_get(part, false)
      end
      true
    end

    def constant_get(name)
      name.split("::").inject(Object) { |scope, part| scope.const_get(part, false) }
    end

    def rails_autoloader?
      defined?(Rails) && Rails.respond_to?(:autoloaders) && Rails.autoloaders.respond_to?(:main)
    end

    def report!
      path = ENV["RUBY_TRANSPILE_REPORT"]
      return if path.nil? || path.empty?
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate({
        "registered" => @registered,
        "applied" => @applied,
        "declined" => @declined,
        "applied_count" => @applied.length,
        "declined_count" => @declined.length,
      }))
    end
  end
end

at_exit { Transpiled.report! }
