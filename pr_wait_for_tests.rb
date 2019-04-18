#!/usr/bin/env ruby
require 'octokit'
require 'logger'

def usage_and_exit!
  puts <<~EOF
    Usage: $0 "https://github.com/my/project/123415"

    Watches a PR and notifies once the tests have passed
  EOF
end

def credential_helper(command, input)
  IO.popen(["git", "credential", "fill"], "w+") do |io|
    io.puts input
    io.close_write
    io.read
  end
end

def get_credentials
  github_credentials = credential_helper :fill, "protocol=https\nhost=github.com"
  /username=(?<github_username>.+)/ =~ github_credentials
  /password=(?<github_password>.+)/ =~ github_credentials
  [github_username, github_password]
end

def repo(url)
  /https:\/\/github.com\/(?<github_org>[^\/]+)\/(?<github_repo>[^\/]+)\/pull\/(?<github_number>[^\/]+)/ =~ url
  repo = "#{github_org}/#{github_repo}"
  [repo, github_number.to_i]
end

class Output
  attr_reader :log

  def initialize
    @log = Logger.new(STDOUT)
    @log.formatter = ->(_, datetime, _, msg) { "#{datetime} #{msg}\n" }
  end

  def log_for_status(status)
    if status.state == "pending"
      in_progress = status.statuses.select{|status| status.state == "success"}.count
      total = status.statuses.count

      "Status is #{status.state}. #{in_progress}/#{total} succeeded..."
    else
      "Status is #{status.state}..."
    end
  end

  def log_debounced_status(status)
    log_line = log_for_status(status)

    if log_line != @last_log_line
      log.info(log_line)
      @last_log_line = log_line
    end
  end
end

class GitHub
  attr_reader :client

  def initialize(login:, password:)
    @client = Octokit::Client.new(login: login, password: password)
  end

  def pull_request(repo_name, pr_number)
    client.pull_request(repo_name, pr_number)
  end

  def status(pull_request)
    sha = pull_request.head.sha
    repo_name = pull_request.head.repo.full_name

    client.status(repo_name, sha)
  end
end

usage_and_exit! unless ARGV.count == 1
PR_URL = ARGV[0].inspect

username, password = get_credentials
client = GitHub.new(login: username, password: password)
repo_name, number = repo(PR_URL)
pull_request = client.pull_request(repo_name, number)
output = Output.new

output.log.info %(Watching "#{pull_request.title}" - #{PR_URL}...)
status = client.status(pull_request)

until status.state == "success"
  output.log_debounced_status(status)

  sleep 10

  pr_sha =  pull_request.head.sha
  status = client.status(pull_request)
end

`osascript -e 'display notification "PR #{number} tests have passed!" with title "Pull Request Watcher"'`
puts "Status is successful. Open in browser? [y/n]"
answer = STDIN.gets.chomp[0].downcase

if answer == 'y'
  `open "#{PR_URL}"`
end

