module Split
  module Services
    module TimeBasedConversions

      def self.within_conversion_time_frame?(user_id, experiment_id)

        window_of_time_for_conversion = Split.configuration.experiments[experiment_id]["window_of_time_for_conversion"]
        time_of_assignment = Split.redis.get(user_id.to_s + "-" + experiment_id)

        (Time.now - time_of_assignment)/60 <= window_of_time_for_conversion
      end

      def self.save_time_that_user_is_assigned(user_id, experiment_name)
        Split.redis.set(user_id.to_s + "-" + experiment_name, Time.now.to_s)
      end
    end
  end
end
