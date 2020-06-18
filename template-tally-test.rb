# frozen_string_literal: true

require_relative '../test_helper'

class TemplateTallyTest < ActiveSupport::TestCase
  teardown do
    # Teardown subscriber so it doesn’t run on other tests
    TemplateTally.unconfigure
  end

  context '#configure' do
    context 'when multiple notifications are sent' do
      should 'call set redis key once' do
        redis_client = mock.tap do |r|
          r.expects(:set).once.with(
            'template-tally:/app/views/home.haml', '1', {ex: 1209600}
          )
        end

        TemplateTally.configure(redis_client: redis_client)

        5.times.each do
          ActiveSupport::Notifications.publish(
            'render_template.action_view', 1.second.ago, Time.now, "123", {
              identifier: Rails.root.join('app/views/home.haml').to_s,
            }
          )
        end
      end
    end

    context 'when redis hits a timeout' do
      should 'be handled gracefully and not raise an error and log to honeybadger' do
        redis_client = mock.tap do |r|
          r.expects(:set).raises(::Redis::CannotConnectError.new)
        end
        Honeybadger.expects(:notify).returns(nil)
        TemplateTally.configure(redis_client: redis_client)

        ActiveSupport::Notifications.publish(
          'render_template.action_view', 1.second.ago, Time.now, "123", {
            identifier: Rails.root.join('app/views/home.haml').to_s,
          }
        )
      end
    end
  end

  context '#rendered_templates' do
    should 'should return templates we marked in redis' do
      Dir.expects(:glob).at_least_once.returns(['a.haml', 'b.haml'])
      redis_client = mock.tap do |r|
        r.expects(:mget).returns(['1', nil])
      end
      TemplateTally.configure(redis_client: redis_client)

      templates = TemplateTally.rendered_templates

      assert_equal(['/a.haml'], templates)
    end
  end

  context '#unrendered_templates' do
    should 'should return templates we marked in redis' do
      Dir.expects(:glob).at_least_once.returns(['a.haml', 'b.haml'])
      redis_client = mock.tap do |r|
        r.expects(:mget).returns(['1', nil])
      end
      TemplateTally.configure(redis_client: redis_client)

      templates = TemplateTally.unrendered_templates

      assert_equal(['/b.haml'], templates)
    end
  end
end
