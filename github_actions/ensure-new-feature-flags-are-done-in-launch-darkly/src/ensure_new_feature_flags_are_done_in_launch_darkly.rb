require 'json'
require 'platform-api'
require 'colorize'

heroku_app_id = ENV.fetch("HEROKU_APP_ID")
heroku_app_name = ENV.fetch("HEROKU_APP_NAME")
heroku_release_id = ENV.fetch("HEROKU_RELEASE_ID")
heroku_release_version = ENV.fetch("HEROKU_RELEASE_VERSION")
for_heroku_pipelines = JSON.parse(ENV.fetch("FOR_HEROKU_PIPELINES"))
heroku_client = PlatformAPI.connect_oauth(ENV.fetch("HEROKU_API_KEY"))

app_pipeline = heroku_client.pipeline_coupling.info_by_app(heroku_app_id)

app_pipeline_name = app_pipeline.dig("pipeline", "name")

if ! for_heroku_pipelines.include?(app_pipeline_name)
  puts "App #{heroku_app_name} is not part of included pipelines [#{for_heroku_pipelines.join(",")}]. Skipping check.".green
  exit 0
end

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


app_releases = heroku_client.pipeline_release.list(app_pipeline.dig("pipeline", "id"))
current_release = app_releases.find { |app_release_json| 
  app_release_json.dig("app", "id") == heroku_app_id
}

if current_release.nil?
  puts "App #{heroku_app_name} has no releases found under pipeline #{app_pipeline_name}. Skipping check.".green
  exit 0
end

# We only care to guard the latest release, so ensure this is still the latest.
# Check as close to update as possible so we can avoid spam.
if current_release["version"]&.to_s != heroku_release_version.to_s
  puts "Release #{heroku_release_version} in app #{heroku_app_name} is not the current release version #{current_release["version"]}. Skipping check.".green
  exit 0 
end

heroku_client.config_var.update(heroku_app_id, body = config_vars_without_non_whitelisted_flags)

puts "Use Launch Darkly for feature flags. Found feature flag(s) [#{nonwhitelisted_feature_flags.join(",")}] that are not whitelisted. Pushed release which removes non whitelisted flags.".red
exit 1
