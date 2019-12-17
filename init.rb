require 'redmine'

require_dependency 'redmine_slack_dm/listener'

Redmine::Plugin.register :redmine_slack_dm do
	name 'Redmine Slack Direct Message'
	author 'Jones Chi, Samuel Cormier-Iijima'
	url 'https://github.com/JonesChi/redmine-slack'
	description 'Slack direct message integration'
	version '0.2'

	requires_redmine :version_or_higher => '0.8.0'

	settings \
		:default => {
			'bot_token' => nil,
			'icon' => 'https://raw.github.com/sciyoshi/redmine-slack/gh-pages/icon.png',
			'username' => 'redmine',
			'display_watchers' => 'no'
		},
		:partial => 'settings/slack_settings'
end

((Rails.version > "5")? ActiveSupport::Reloader : ActionDispatch::Callbacks).to_prepare do
	require_dependency 'issue'
	unless Issue.included_modules.include? RedmineSlackDm::IssuePatch
		Issue.send(:include, RedmineSlackDm::IssuePatch)
	end
end
