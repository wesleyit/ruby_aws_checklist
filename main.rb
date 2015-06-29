#!/usr/bin/ruby
#coding: UTF-8
## Using bundler to manage dependencies
require 'rubygems'
require 'bundler/setup'
require 'aws-sdk'
require 'colorize'
require 'yaml'


## Lets define a standard to print messages
def show_message(kind, message)
	case kind
	when :fail
		puts "#{message}\r\t\t\t\t\t\t\t\t[fail]".red
	when :warn
		puts "#{message}\r\t\t\t\t\t\t\t\t[warn]".yellow
	when :good
		puts "#{message}\r\t\t\t\t\t\t\t\t[good]".green
	else
		puts message
	end
end


## Reads the file config.yml to parse the config values.
# An exception is thrown if the file is not found.
def parse_config
	@config_file = './config.yml'
	unless File.exists? @config_file
		raise 'Config file not found. Please, create a valid config.yml.'
	end
	@config = YAML.load_file(@config_file)
end


## Creates the handlers for all services managed by this program.
def connect_to_aws_and_create_handlers
	@access_key = @config['access_key']
	@secret_access_key = @config['secret_access_key']
	@creds = Aws::Credentials.new(@access_key, @secret_access_key)
	Aws.config.update(region: 'us-east-1', credentials: @creds,)
	@root_account = Aws::IAM::CurrentUser.new
	@iam_client = Aws::IAM::Client.new
#	@cloudtrail_client = Aws::CloudTrail::Client.new
#	@s3_client = Aws::S3::Client.new
#	@sns_client = Aws::SNS::Client.new
#	@ses_client = Aws::SES::Client.new
end


## Prepare: Invoking the methods to create the handlers after read the config file 
parse_config
connect_to_aws_and_create_handlers


## Step 1: Master account must have MFA enabled. I will warn if not.
if @root_account.mfa_devices.any? then
	show_message(:good, 'You have a MFA device on root account.')
else
	show_message(:fail, 'I am unable to find a MFA device on root account.')
end


## Step 2: There must be an admin group with the necessary users
# to manage the account.
@iam_client.create_group(group_name: 'cs-admins')
@iam_client.attach_group_policy(
	group_name: 'cs-admins',
	policy_arn: 'arn:aws:iam::aws:policy/AdministratorAccess'
)
@config['logins'].each do |user|
  @iam_client.create_user(user_name: user)
  @iam_client.add_user_to_group(
		group_name: 'cs-admins', 
		user_name: user
	)
  @iam_client.create_login_profile(
		user_name: user, 
		password: 'Concrete2015', 
		password_reset_required: true
	)
  show_message(:good, "Login #{user} created as admin." )
end


## Step 3: The account must have an simple login alias.
# Set 3 possible alternatives (just in case of the first is already taken)
@config['account_aliases'].each do |alias_name|
  if @iam_client.create_account_alias(account_alias: alias_name) then
		show_message(:good, "Alias #{alias_name} successfuly created.")
    puts "Login URL: https://#{alias_name}.signin.aws.amazon.com/console"
    break
  else
		show_message(:fail, "Impossible to define alias #{alias_name}.")
  end
end


## Step 4: The passwords must follow a complexity rule.
# It should contain at least 8 chars, 1 Upper Case, 1 lower case and 1 number.
@iam_client.update_account_password_policy(
	minimum_password_length: 8,
  require_symbols: false,
  require_numbers: true,
  require_uppercase_characters: true,
  require_lowercase_characters: true,
  allow_users_to_change_password: true
)
show_message(:good, "Password enforcement policy defined.")


## Step 5: All API calls must be logged. Use cloudtrail.
# ************* Not ready, Still in development!!! *************
=begin

s3 = Aws::S3::Client.new
s3.create_bucket(
  acl: 'private',
  bucket: 'CS-Trail'
)

sns = Aws::SNS::Client.new
sns.create_topic(name: "CS-Trail")

# i am having an error during the creation 
# of this CloudTrail I need to verify.
cloudtrail.create_trail(
  # required
  name: "CS-Trail",
  # required
  s3_bucket_name: "CS-Trail",
  s3_key_prefix: "CS-Trail",
  sns_topic_name: "CS-Trail",
  include_global_service_events: true,
 )

=end

