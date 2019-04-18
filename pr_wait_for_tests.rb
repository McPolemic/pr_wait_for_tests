#!/usr/bin/env ruby
require 'octokit'
require 'logger'

class LogWrapper
  attr_reader :log

  def initialize
    @log = Logger.new(STDOUT)
    @log.formatter = ->(_, datetime, _, msg) { "#{datetime} #{msg}\n" }
  end

  def info(msg)
    log.info(msg)
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
  def pull_request_from_url(url)
    /https:\/\/github.com\/(?<github_org>[^\/]+)\/(?<github_repo>[^\/]+)\/pull\/(?<github_number>[^\/]+)/ =~ url
    repo = "#{github_org}/#{github_repo}"

    client.pull_request(repo, github_number.to_i)
  end

  def status(pull_request)
    sha = pull_request.head.sha
    repo_name = pull_request.head.repo.full_name

    client.status(repo_name, sha)
  end

  def client
    return @client if @client

    github_credentials = `echo "protocol=https\nhost=github.com" | git credential fill`
    /username=(?<login>.+)/ =~ github_credentials
    /password=(?<password>.+)/ =~ github_credentials

    @client = Octokit::Client.new(login: login, password: password)
  end
end

unless ARGV.count == 1
  puts <<~EOF
    Usage: $0 "https://github.com/my/project/123415"

    Watches a PR and notifies once the tests have passed
  EOF
  exit
end
PR_URL = ARGV.first

logger = LogWrapper.new
client = GitHub.new
pull_request = client.pull_request_from_url(PR_URL)
status = client.status(pull_request)

logger.info %(Watching "#{pull_request.title}" - #{PR_URL}...)

until status.state == "success"
  logger.log_debounced_status(status)

  sleep 10

  pull_request = client.pull_request_from_url(PR_URL)
  status = client.status(pull_request)
end

`osascript -e 'display notification "PR #{number} tests have passed!" with title "Pull Request Watcher"'`
puts "Status is successful. Open in browser? [y/n]"
answer = STDIN.gets.chomp[0].downcase

if answer == 'y'
  `open "#{PR_URL}"`
end

