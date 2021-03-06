#!/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'open3'
require 'fileutils'
Bundler.require

repo ='vcjp/packages'
branch ="#{ENV['GIT_BRANCH']}"
svnconf='/var/lib/jenkins/workspace/build-vc-packages/.subversion/'
pullrequest_url = ''
pullrequest_num = ENV['ghprbPullId']

ENV['HOME'] = "#{ENV['WORKSPACE']}/#{pullrequest_num}"
ENV['JAVA_HOME'] = '/usr/local/java'
ENV['ANT_HOME'] = '/usr/local/apache-ant-1.7.0'
ENV['PATH'] = "#{ENV['PATH']}:#{ENV['ANT_HOME']}/bin"
ENV['GITHUB_ACCESS_TOKEN'] = 'c20711b4bd10140aa38a04b771855b536f567c0c'
ENV['SLACK_INCOMING_WEBHOOK'] = 'https://hooks.slack.com/services/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'

if branch.match(/(deploy\/[a-z0-9.]*)\.([0-9a-z]*)\.([0-9a-z]*)$/)[2] then
  environment = branch.match(/(deploy\/[a-z0-9.]*)\.([0-9a-z]*)\.([0-9a-z]*)$/)[2]
else
  puts "branch name does not match /deploy/"
  exit (1)
end

def post(text)
  data = {
    "channel"  => '#infra',
    "username" => 'vcbot',
    "icon_url" => 'https://avatars3.githubusercontent.com/u/13045145?v=3&s=400',
    "text" => text
  }
  request_url = ENV['SLACK_INCOMING_WEBHOOK']
  uri = URI.parse(request_url)
  http = Net::HTTP.post_form(uri, {"payload" => data.to_json})
end

client = Octokit::Client.new(access_token: ENV['GITHUB_ACCESS_TOKEN'])
pull = client.pull_requests(repo, :state => 'open')
pull.each do |p|
  pullrequest_url = p.html_url.gsub(/api.github.com\/repos/, 'github.com').gsub(/pulls/, 'pull')
  head = p.head.ref
  if !head.eql?(branch)
    puts "branch name does not mutch git head"
    exit (1)
  end

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

pull_files = client.pull_request_files(repo, pullrequest_num)
files = []
pull_files.each do |p|
  if p.filename.match(/.*spec$/) then
    files.push(p.filename)
  end
end

files.each do |f|
  #Open3.popen3("rpmbuild --clean -ba `ls -t *.spec |head -1`") do |stdin, stdout, stderr, wait_thr|
  Open3.popen3("rpmbuild --clean -ba #{f}") do |stdin, stdout, stderr, wait_thr|
    while output = stdout.gets
      output.chomp!
      puts output
    end
    unless wait_thr.value.success?
      puts stderr.read
      exit (1)
    end
  end
end

body = <<-"EOC"
Pull Request: master -> #{ENV['GIT_BRANCH']} build successfully finished
continue manual merge #{pullrequest_url} to deploy
just close pull request to cancel
EOC

post(body)
