module Split
  module Services
    module TimeBasedConversions

      def self.within_conversion_time_frame?(user, experiment_key)
        window_of_time_for_conversion = Split.configuration.experiments[experiment_key]["window_of_time_for_conversion"]

        return true if window_of_time_for_conversion.nil?

        time_of_assignment = user["time_of_assignment_" + experiment_key]

        (Time.now - time_of_assignment)/60 <= window_of_time_for_conversion
      end

      def self.save_time_that_user_is_assigned(user, experiment_key)
        user["time_of_assignment_" + experiment_key] = Time.now.to_s
      end
    end
  end
end
