#!/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'json'
Bundler.require

payload = ENV['payload']
#payload = File.read('payload.json')
#obj = JSON.parse(payload)
obj = JSON.parse(ENV['payload'])

pullrequest_num = obj['number']
pullrequest_url = obj['pull_request']['html_url']
branch =  obj['pull_request']['head']['ref']

repo ='vcjp/packages'
svnconf='/var/lib/jenkins/workspace/build-rpm-packages/.subversion/'

ENV['HOME'] = "#{ENV['WORKSPACE']}/#{pullrequest_num}"
ENV['JAVA_HOME'] = '/usr/local/java'
ENV['ANT_HOME'] = '/usr/local/apache-ant-1.7.0'
ENV['PATH'] = "#{ENV['PATH']}:#{ENV['ANT_HOME']}/bin"
ENV['GITHUB_ACCESS_TOKEN'] = ''
ENV['SLACK_INCOMING_WEBHOOK'] = ''

unless branch.match(/(deploy\/[a-z0-9.]*)\.([0-9a-z]*)\.([0-9a-z]*)$/)[2] then
  puts "branch name does not match /deploy/"
  exit (1)
end

def post(text)
  data = {
    "channel"  => '#infra',
    "username" => '',
    "icon_url" => '',
    "text" => text
  }
  request_url = ENV['SLACK_INCOMING_WEBHOOK']
  uri = URI.parse(request_url)
  Net::HTTP.post_form(uri, {"payload" => data.to_json})
end

client = Octokit::Client.new(access_token: ENV['GITHUB_ACCESS_TOKEN'])
pull = client.pull_requests(repo, :state => 'open')
pull.each do |p|
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
  puts f
  Open3.popen3("rpmbuild --clean -ba #{f}") do |stdin, stdout, stderr, wait_thr|
    while output = stdout.gets
      output.chomp!
      puts output
    end
    unless wait_thr.value.success?
      exit (1)
    end
  end
end

success = <<-"EOC"
Pull Request: master -> #{branch} build successfully finished
continue manual merge #{pullrequest_url} to deploy
just close pull request to cancel
EOC

post(success)
