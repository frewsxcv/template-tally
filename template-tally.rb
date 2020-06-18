# frozen_string_literal: true

class TemplateTally
  @seen = Set.new
  @redis_client = nil
  @subscribers = []

  REDIS_KEY_PREFIX = 'template-tally:'

  class << self
    def configure(redis_client:)
      @redis_client = redis_client
      setup_event_subscribers
    end

    def unconfigure
      @seen = Set.new
      @subscribers.slice!(0..-1).each do |subscriber|
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
    end

    def rendered_templates
      all_templates_with_rendered_status
        .select { |path, is_rendered| is_rendered }
        .map(&:first)
    end

    def unrendered_templates
      all_templates_with_rendered_status
        .select { |path, is_rendered| !is_rendered }
        .map(&:first)
    end

    private def all_templates_with_rendered_status
      templates = all_templates

      templates.zip(
        @redis_client.mget(
          templates.map{|t| REDIS_KEY_PREFIX + t}
        ).map(&:present?)
      )
    end

    private def all_templates
      Dir
        .glob('**/*.{haml,erb,mustache,builder}')
        .map{|t| '/' + t} # Paths in keys start with ‘/’
        .select{|t| !t.include?('mailer')}
    end

    private def rails_root_length
      @rails_root_length ||= Rails.root.to_s.length
    end

    private def setup_event_subscribers
      [
        'render_template.action_view',
        'render_partial.action_view'
      ].each(&method(:setup_event_subscriber))
    end

    private def setup_event_subscriber(event_name)
      @subscribers <<
        ActiveSupport::Notifications.subscribe(event_name) do |*event_args|
          ActiveSupport::Notifications::Event.new(*event_args)
            .yield_self(&method(:handle_event))
        end
    end

    private def handle_event(event)
      template_path =
        event
          .payload[:identifier] # Retrieve the absolute path to the template
          .slice(rails_root_length..-1) # Strip off the Rails root, leaving the relative path

      return if @seen.include?(template_path)

      @seen.add(template_path)

      begin
        @redis_client.set(
          "#{REDIS_KEY_PREFIX}#{template_path}",
          '1',
          ex: 2.weeks.seconds.to_i
        )
      rescue ::Redis::BaseConnectionError => e
        Honeybadger.notify(e)
        return
      end
    end
  end
end
