require 'sidekiq'
require 'sidekiq/cron'
require 'sidekiq/scheduled'
require 'sidekiq/options'

module Sidekiq
  module Cron
    POLL_INTERVAL = 30

    # The Poller checks Redis every N seconds for sheduled cron jobs.
    class Poller < Sidekiq::Scheduled::Poller
      def initialize(options = {})
        if Gem::Version.new(Sidekiq::VERSION) >= Gem::Version.new('6.5.0')
          super
        else
          # Old version of Sidekiq does not accept a config argument.
          @config = options
          super()
        end
      end

      def enqueue
        time = Time.now.utc
        Sidekiq::Cron::Job.all.each do |job|
          enqueue_job(job, time)
        end
      rescue => ex
        # Most likely a problem with redis networking.
        # Punt and try again at the next interval.
        Sidekiq.logger.error ex.message
        Sidekiq.logger.error ex.backtrace.first
        handle_exception(ex) if respond_to?(:handle_exception)
      end

      private

      def enqueue_job(job, time = Time.now.utc)
        job.test_and_enque_for_time! time if job && job.valid?
      rescue => ex
        # Problem somewhere in one job.
        Sidekiq.logger.error "CRON JOB: #{ex.message}"
        Sidekiq.logger.error "CRON JOB: #{ex.backtrace.first}"
        handle_exception(ex) if respond_to?(:handle_exception)
      end

      def poll_interval_average
        @config[:cron_poll_interval] || POLL_INTERVAL
      end
    end
  end
end
