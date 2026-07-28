# frozen_string_literal: true

module Split
  # Simplifies the interface to Redis.
  class RedisInterface
    def initialize
      self.redis = Split.redis
    end

    def persist_list(list_name, list_values)
      if list_values.length > 0
        redis.multi do |multi|
          tmp_list = "#{list_name}_tmp"
          tmp_list += redis_namespace_used? ? "{#{Split.redis.namespace}:#{list_name}}" : "{#{list_name}}"
          multi.rpush(tmp_list, list_values)
          multi.rename(tmp_list, list_name)
        end
      end

      list_values
    end

    def add_to_set(set_name, value)
      # `sadd?` is not a command redis-namespace (< 2.0) knows how to namespace: it
      # falls through as a blind passthrough and drops the namespace prefix, so members
      # end up in an un-namespaced key. `sadd` is namespaced correctly, so always use it.
      redis.sadd(set_name, value)
    end

    private
      attr_accessor :redis

      def redis_namespace_used?
        Redis.const_defined?("Namespace") && Split.redis.is_a?(Redis::Namespace)
      end
  end
end
