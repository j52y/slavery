require 'slavery/version'
require 'slavery/railtie'
require 'active_record'
require 'active_support/core_ext/module/attribute_accessors'

module Slavery
  extend ActiveSupport::Concern

  included do
    class << self
      alias_method_chain :connection, :slavery
    end
  end

  class Error < StandardError; end

  mattr_accessor :disabled

  module ModuleFunctions
    def on_slave(&block)
      ActiveRecord::Base.on_slave(&block)
    end

    def on_master(&block)
      ActiveRecord::Base.on_master(&block)
    end

    def env
      self.env = defined?(Rails) ? Rails.env.to_s : 'development' unless @env
      @env
    end

    def env=(string)
      @env = ActiveSupport::StringInquirer.new(string)
    end
  end
  extend ModuleFunctions

  module ClassMethods
    def on_slave(&block)
      with_slavery true, &block
    end

    def on_master(&block)
      with_slavery false, &block
    end

    def with_slavery(new_value)
      old_value = Thread.current[:on_slave] # Save for recursive nested calls
      Thread.current[:on_slave] = new_value
      yield
    ensure
      Thread.current[:on_slave] = old_value
    end

    def connection_with_slavery
      if Thread.current[:on_slave] and slaveryable?
        slave_connection
      else
        master_connection
      end
    end

    def slaveryable?
      inside_transaction = master_connection.open_transactions > 0
      raise Error.new('on_slave cannot be used inside transaction block!') if inside_transaction

      !Slavery.disabled
    end

    def master_connection
      connection_without_slavery
    end

    def slave_connection
      slave_connection_holder.connection_without_slavery
    end

    # Create an anonymous AR class to hold slave connection
    def slave_connection_holder
      @slave_connection_holder ||= Class.new(ActiveRecord::Base) {
        self.abstract_class = true
        establish_connection("#{Slavery.env}_slave")
      }
    rescue ActiveRecord::AdapterNotSpecified
      raise Error.new("#{Slavery.env}_slave does not exist!")
    end
  end
end
