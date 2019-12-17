# Slack chat plugin for Redmine

Fork from https://github.com/sciyoshi/redmine-slack.git, but instead of post
messages to channel, the plugin would send direct messages to the issue
assignee and all watchers.

The plugin would use email to find the corresponding Slack account, so users
must use the same email address for Redmine and Slack accounts.

## Screenshot

![screenshot](https://raw.github.com/sciyoshi/redmine-slack/gh-pages/screenshot.png)

## Installation

From your Redmine plugins directory, clone this repository as `redmine_slack_dm` (note
the underscore!):

    git clone https://github.com/JonesChi/redmine-slack.git redmine_slack_dm

You will also need the `httpclient` dependency, which can be installed by running

    bundle install

from the plugin directory.

Restart Redmine, and you should see the plugin show up in the Plugins page.
Under the configuration options, set the Slack bot token with your Slack bot OAuth
Access Token.

Required bot token scopes: `im:write`, `chat:write`, `users:read.email`
