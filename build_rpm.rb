#!/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'open3'
require 'fileutils'
Bundler.require

repo ='vcjp/packages'
branch ="#{ENV['GIT_BRANCH']}"
svnconf='/var/lib/jenkins/workspace/build-vc-packages/.subversion/'
pullrequesturl = ''

client = Octokit::Client.new(access_token: ENV['GITHUB_ACCESS_TOKEN'])
pull = client.pull_requests(repo, :state => 'open')
pull.each do |p|
  pullrequesturl = p.html_url.gsub(/api.github.com\/repos/, 'github.com').gsub(/pulls/, 'pull')
  pullrequestnum = p.number
  head = p.head.ref
  if !head.eql?(branch)
    puts "branch name does not mutch git head"
    exit (1)
  end
end

#ENV['HOME'] = "#{ENV['WORKSPACE']}/#{ENV['BUILD_NUMBER']}"
ENV['HOME'] = "#{ENV['WORKSPACE']}/#{pullrequestnum}"
ENV['JAVA_HOME'] = '/usr/local/java'
ENV['ANT_HOME'] = '/usr/local/apache-ant-1.7.0'
ENV['PATH'] = "#{ENV['PATH']}:#{ENV['ANT_HOME']}/bin"
ENV['GITHUB_ACCESS_TOKEN'] = ''
ENV['SLACK_INCOMING_WEBHOOK'] = ''

if branch.match(/(deploy\/[a-z0-9.]*)\.([0-9a-z]*)\.([0-9a-z]*)$/)[2] then
  environment = branch.match(/(deploy\/[a-z0-9.]*)\.([0-9a-z]*)\.([0-9a-z]*)$/)[2]
else
  puts "branch name does not match /deploy/"
  exit (1)
end

def post(text)
  data = {
    "channel"  => '#infra',
    "username" => 'hubot',
    "icon_url" => 'https://avatars3.githubusercontent.com',
    "text" => text
  }
  request_url = ENV['SLACK_INCOMING_WEBHOOK']
  uri = URI.parse(request_url)
  http = Net::HTTP.post_form(uri, {"payload" => data.to_json})
end

FileUtils.mkdir_p("#{ENV['HOME']}") unless FileTest.exist?("#{ENV['HOME']}")
FileUtils.mkdir_p("#{ENV['HOME']}/.subversion") unless FileTest.exist?("#{ENV['HOME']}/.subversion")

FileUtils.cp_r( svnconf, "#{ENV['HOME']}" , preserve: true )

Open3.popen3("rpmdev-setuptree") do |stdin, stdout, stderr, wait_thr|
  unless stderr.read.empty?
    puts "ERROR: Can\'t create build environment"
    exit (1)
  end
end

Open3.popen3("rpmbuild --clean -ba `ls -t *.spec |head -1`") do |stdin, stdout, stderr, wait_thr|
  while output = stdout.gets
    output.chomp!
    puts output
  end
  unless wait_thr.value.success?
    exit (1)
  end
end

body = <<-"EOC"
Pull Request: master -> #{ENV['GIT_BRANCH']} build successfully finished
continue manual merge #{pullrequesturl} to deploy
just close pull request to cancel
EOC

post(body)
