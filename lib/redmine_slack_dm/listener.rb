require 'httpclient'

class SlackListener < Redmine::Hook::Listener
	def redmine_slack_issues_new_after_save(context={})
		issue = context[:issue]

		channel = channel_for_user issue.assigned_to.try(:mail)

		return unless channel
		return if issue.is_private?

		msg = "[#{escape issue.project}] #{escape issue.author} created <#{object_url issue}|#{escape issue}>#{mentions issue.description}"

		attachment = {}
		attachment[:text] = escape issue.description if issue.description
		attachment[:fields] = [{
			:title => I18n.t("field_status"),
			:value => escape(issue.status.to_s),
			:short => true
		}, {
			:title => I18n.t("field_priority"),
			:value => escape(issue.priority.to_s),
			:short => true
		}, {
			:title => I18n.t("field_assigned_to"),
			:value => escape(issue.assigned_to.to_s),
			:short => true
		}]

		attachment[:fields] << {
			:title => I18n.t("field_watcher"),
			:value => escape(issue.watcher_users.join(', ')),
			:short => true
		} if Setting.plugin_redmine_slack_dm['display_watchers'] == 'yes'

		if Setting.plugin_redmine_slack_dm['skip_author'] != '1' or issue.author != issue.assigned_to
			speak msg, channel, attachment
		end

		return unless Setting.plugin_redmine_slack_dm['post_watchers'] == '1'
		for user in issue.watcher_users
			next if user == issue.assigned_to
			channel = channel_for_user user.try(:mail)
			speak msg, channel, attachment if channel
		end
	end

	def redmine_slack_issues_edit_after_save(context={})
		issue = context[:issue]
		journal = context[:journal]

		channel = channel_for_user issue.assigned_to.try(:mail)

		return unless channel and Setting.plugin_redmine_slack_dm['post_updates'] == '1'
		return if issue.is_private?
		return if journal.private_notes?

		msg = "[#{escape issue.project}] #{escape journal.user.to_s} updated <#{object_url issue}|#{escape issue}>#{mentions journal.notes}"

		attachment = {}
		attachment[:text] = escape journal.notes if journal.notes
		attachment[:fields] = journal.details.map { |d| detail_to_field d }

		if Setting.plugin_redmine_slack_dm['skip_author'] != '1' or journal.user != issue.assigned_to
			speak msg, channel, attachment
		end

		return unless Setting.plugin_redmine_slack_dm['post_watchers'] == '1'
		for user in issue.watcher_users
			next if user == issue.assigned_to
			channel = channel_for_user user.try(:mail)
			speak msg, channel, attachment if channel
		end
	end

	def model_changeset_scan_commit_for_issue_ids_pre_issue_update(context={})
		issue = context[:issue]
		journal = issue.current_journal
		changeset = context[:changeset]

		channel = channel_for_user issue.assigned_to.try(:mail)

		return unless channel and issue.save
		return if issue.is_private?

		msg = "[#{escape issue.project}] #{escape journal.user.to_s} updated <#{object_url issue}|#{escape issue}>"

		repository = changeset.repository

		if Setting.host_name.to_s =~ /\A(https?\:\/\/)?(.+?)(\:(\d+))?(\/.+)?\z/i
			host, port, prefix = $2, $4, $5
			revision_url = Rails.application.routes.url_for(
				:controller => 'repositories',
				:action => 'revision',
				:id => repository.project,
				:repository_id => repository.identifier_param,
				:rev => changeset.revision,
				:host => host,
				:protocol => Setting.protocol,
				:port => port,
				:script_name => prefix
			)
		else
			revision_url = Rails.application.routes.url_for(
				:controller => 'repositories',
				:action => 'revision',
				:id => repository.project,
				:repository_id => repository.identifier_param,
				:rev => changeset.revision,
				:host => Setting.host_name,
				:protocol => Setting.protocol
			)
		end

		attachment = {}
		attachment[:text] = ll(Setting.default_language, :text_status_changed_by_changeset, "<#{revision_url}|#{escape changeset.comments}>")
		attachment[:fields] = journal.details.map { |d| detail_to_field d }

		if Setting.plugin_redmine_slack_dm['skip_author'] != '1' or journal.user != issue.assigned_to
			speak msg, channel, attachment
		end

		return unless Setting.plugin_redmine_slack_dm['post_watchers'] == '1'
		for user in issue.watcher_users
			next if user == issue.assigned_to
			channel = channel_for_user user.try(:mail)
			speak msg, channel, attachment if channel
		end
	end

	def controller_wiki_edit_after_save(context = { })
		return unless Setting.plugin_redmine_slack_dm['post_wiki_updates'] == '1'

		project = context[:project]
		page = context[:page]

		user = page.content.author
		project_url = "<#{object_url project}|#{escape project}>"
		page_url = "<#{object_url page}|#{page.title}>"
		comment = "[#{project_url}] #{page_url} updated by *#{user}*"
		if page.content.version > 1
			comment << " [<#{object_url page}/diff?version=#{page.content.version}|difference>]"
		end

		channel = channel_for_user user.try(:mail)
		return unless channel

		attachment = nil
		if not page.content.comments.empty?
			attachment = {}
			attachment[:text] = "#{escape page.content.comments}"
		end

		if Setting.plugin_redmine_slack_dm['skip_author'] != '1'
			speak comment, channel, attachment
		end

		return unless Setting.plugin_redmine_slack_dm['post_wiki_watchers'] == '1'
		for user in page.watcher_users
			next if user == page.content.author
			channel = channel_for_user user.try(:mail)
			speak comment, channel, attachment if channel
		end
	end

	def speak(msg, channel, attachment=nil)
		bot_token = Setting.plugin_redmine_slack_dm['bot_token']
		return nil if bot_token.blank?

		username = Setting.plugin_redmine_slack_dm['username']
		icon = Setting.plugin_redmine_slack_dm['icon']

		params = {
			:text => msg,
			:link_names => 1,
		}

		params[:username] = username if username
		params[:channel] = channel if channel

		params[:attachments] = [attachment] if attachment

		if icon and not icon.empty?
			if icon.start_with? ':'
				params[:icon_emoji] = icon
			else
				params[:icon_url] = icon
			end
		end

		begin
			client = HTTPClient.new
			client.ssl_config.cert_store.set_default_paths
			client.ssl_config.ssl_version = :auto
			client.post_async "https://slack.com/api/chat.postMessage",
				params.to_json,
				{"Authorization": "Bearer #{bot_token}", "Content-Type": "application/json; charset=utf-8"}
		rescue Exception => e
			Rails.logger.warn("cannot connect to #{url}")
			Rails.logger.warn(e)
		end
	end

private
	def escape(msg)
		msg.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
	end

	def object_url(obj)
		if Setting.host_name.to_s =~ /\A(https?\:\/\/)?(.+?)(\:(\d+))?(\/.+)?\z/i
			host, port, prefix = $2, $4, $5
			Rails.application.routes.url_for(obj.event_url({
				:host => host,
				:protocol => Setting.protocol,
				:port => port,
				:script_name => prefix
			}))
		else
			Rails.application.routes.url_for(obj.event_url({
				:host => Setting.host_name,
				:protocol => Setting.protocol
			}))
		end
	end

	def url_for_project(proj)
		return nil if proj.blank?

		cf = ProjectCustomField.find_by_name("Slack URL")

		return [
			(proj.custom_value_for(cf).value rescue nil),
			(url_for_project proj.parent),
			Setting.plugin_redmine_slack_dm['slack_url'],
		].find{|v| v.present?}
	end

	def channel_for_user(email)
		return nil if email.blank?

		if Setting.plugin_redmine_slack_dm['user_channels'].nil?
			Setting.plugin_redmine_slack_dm['user_channels'] = {}
		end
		channel = Setting.plugin_redmine_slack_dm['user_channels'][email]
		return channel if channel.present?

		bot_token = Setting.plugin_redmine_slack_dm['bot_token']
		return nil if bot_token.blank?
		begin
			client = HTTPClient.new
			client.ssl_config.cert_store.set_default_paths
			client.ssl_config.ssl_version = :auto

			resp = client.get "https://slack.com/api/users.lookupByEmail", {"token"=>bot_token, "email"=>email}
			user_id = JSON.parse(resp.content)["user"]["id"]

			resp = client.post "https://slack.com/api/im.open", {"token"=>bot_token, "user"=>user_id}
			channel = JSON.parse(resp.content)["channel"]["id"]
			Setting.plugin_redmine_slack_dm['user_channels'][email] = channel
			return channel
		rescue Exception => e
			Rails.logger.warn("cannot get channel for user with email #{email}")
			Rails.logger.warn(e)
		end
	end

	def detail_to_field(detail)
		case detail.property
		when "cf"
			custom_field = detail.custom_field
			key = custom_field.name
			title = key
			value = (detail.value)? IssuesController.helpers.format_value(detail.value, custom_field) : ""
		when "attachment"
			key = "attachment"
			title = I18n.t :label_attachment
			value = escape detail.value.to_s
		else
			key = detail.prop_key.to_s.sub("_id", "")
			if key == "parent"
				title = I18n.t "field_#{key}_issue"
			else
				title = I18n.t "field_#{key}"
			end
			value = escape detail.value.to_s
		end

		short = true

		case key
		when "title", "subject", "description"
			short = false
		when "tracker"
			tracker = Tracker.find(detail.value) rescue nil
			value = escape tracker.to_s
		when "project"
			project = Project.find(detail.value) rescue nil
			value = escape project.to_s
		when "status"
			status = IssueStatus.find(detail.value) rescue nil
			value = escape status.to_s
		when "priority"
			priority = IssuePriority.find(detail.value) rescue nil
			value = escape priority.to_s
		when "category"
			category = IssueCategory.find(detail.value) rescue nil
			value = escape category.to_s
		when "assigned_to"
			user = User.find(detail.value) rescue nil
			value = escape user.to_s
		when "fixed_version"
			version = Version.find(detail.value) rescue nil
			value = escape version.to_s
		when "attachment"
			attachment = Attachment.find(detail.prop_key) rescue nil
			value = "<#{object_url attachment}|#{escape attachment.filename}>" if attachment
		when "parent"
			issue = Issue.find(detail.value) rescue nil
			value = "<#{object_url issue}|#{escape issue}>" if issue
		end

		value = "-" if value.empty?

		result = { :title => title, :value => value }
		result[:short] = true if short
		result
	end

	def mentions text
		return nil if text.nil?
		names = extract_usernames text
		names.present? ? "\nTo: " + names.join(', ') : nil
	end

	def extract_usernames text = ''
		if text.nil?
			text = ''
		end

		# slack usernames may only contain lowercase letters, numbers,
		# dashes and underscores and must start with a letter or number.
		text.scan(/@[a-z0-9][a-z0-9_\-]*/).uniq
	end
end
