require 'json'
require 'platform-api'
require 'colorize'

# grab all FEATURE_* env vars from release for heroku app
# filter out whitelisted flags
# if any remain, update config with null to remove them in a new release
# fail this job so slack alert is sent (verify it doesn't rerun the webhook?)
# Should point out end and env var in alert

# Do forge-services-pipeline too
# Do fcs-pipeline too

# --- main ---

heroku_app_id = ENV.fetch("HEROKU_APP_ID")
heroku_app_name = ENV.fetch("HEROKU_APP_NAME")
heroku_release_id = ENV.fetch("HEROKU_RELEASE_ID")
heroku_release_version = ENV.fetch("HEROKU_RELEASE_VERSION")
heroku_client = PlatformAPI.connect_oauth(ENV.fetch("HEROKU_API_KEY"))

release_config_vars=heroku_client.config_var.info_for_app_release(heroku_app_id, heroku_release_id)

feature_flag_whitelist = JSON.parse(ENV.fetch("FEATURE_FLAG_WHITELIST"))

nonwhitelisted_feature_flags = release_config_vars.keys.select { |config_var| config_var.start_with?("FEATURE_") && !feature_flag_whitelist.include?(config_var) }

if nonwhitelisted_feature_flags.empty?
  puts "No feature flags found outside of whitelist for release #{heroku_release_version} in app #{heroku_app_name}. No action taken.".green
  exit 0 
end

config_vars_without_non_whitelisted_flags = release_config_vars.map { |config_key, config_value| 
  if nonwhitelisted_feature_flags.include?(config_key) 
    [config_key, nil] # This removes the config var from the release
  else
    [config_key, config_value]
  end
}.to_h


maybe_latest_release=heroku_client.release.info(heroku_app_id, heroku_release_version)
# A release is generated for each item invoked in procfile, so it can get spammy.
# We only care to guard the latest release, so ensure this is still the latest.
# Check as close to update as possible so we can avoid spam.
if maybe_latest_release["current"] != true
  puts "Release #{heroku_release_version} in app #{heroku_app_name} is not current. Skipping check.".green
  exit 0 
end

heroku_client.config_var.update(heroku_app_id, body = config_vars_without_non_whitelisted_flags)

puts "Use Launch Darkly for feature flags. Found feature flag(s) [#{nonwhitelisted_feature_flags.join(",")}] that are not whitelisted. Pushed release which removes non whitelisted flags.".red
exit 1
