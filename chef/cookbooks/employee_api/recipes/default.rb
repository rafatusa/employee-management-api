#
# employee_api::default
#
# Configures Ubuntu 22.04 to run the Employee Management API:
#   Java 21 (for operator tooling), Podman, Nginx reverse proxy,
#   CloudWatch agent, log rotation and the systemd application service.
#
# Ordering matters: packages -> user/dirs -> registry login -> image pull ->
# systemd unit -> nginx -> cloudwatch. Each resource is idempotent so repeated
# chef-solo runs converge without churn.
#

require 'shellwords'

api = node['employee_api']

# ---------------------------------------------------------------------------
# Base packages
#
# NOTE: apt_update runs for real on every converge — no cache validity window.
# Cloud images ship a prebuilt apt index that is new enough to look fresh and
# old enough to name superseded package versions, which produces 404s on
# install. The host is new on each provision, so a real refresh costs little.
# ---------------------------------------------------------------------------
apt_update 'refresh apt index' do
  action :update
end

# Java 21 is in Ubuntu 22.04's universe repository as openjdk-21-jre-headless.
# (Java 17 is jammy's default-jre; 21 is present but must be named explicitly.)
package %w(
  openjdk-21-jre-headless
  podman
  nginx
  curl
  ca-certificates
  unzip
  logrotate
) do
  action :install
end

# ---------------------------------------------------------------------------
# Service account and directories
# ---------------------------------------------------------------------------
user api['app_user'] do
  system true
  manage_home true
  home api['app_dir']
  shell '/usr/sbin/nologin'
  comment 'Employee Management API service account'
  action :create
end

[api['app_dir'], api['log_dir'], "#{api['app_dir']}/config"].each do |dir|
  directory dir do
    owner api['app_user']
    group api['app_user']
    mode '0750'
    recursive true
    action :create
  end
end

# ---------------------------------------------------------------------------
# Application environment file
#
# Mode 0640, owned by the service account: it carries the database and admin
# credentials and must not be world-readable.
# ---------------------------------------------------------------------------
template "#{api['app_dir']}/config/app.env" do
  source 'app.env.erb'
  owner api['app_user']
  group api['app_user']
  mode '0640'
  sensitive true
  variables(
    db_host: api['database']['host'],
    db_port: api['database']['port'],
    db_name: api['database']['name'],
    db_user: api['database']['user'],
    db_password: api['database']['password'],
    admin_username: api['admin']['username'],
    admin_password: api['admin']['password'],
    app_port: api['app_port']
  )
  notifies :restart, 'service[employee-api]', :delayed
end

# ---------------------------------------------------------------------------
# Container registry authentication and image pull
#
# execute rather than a docker_* resource: chef-solo runs here with no
# third-party cookbooks, and podman has no core Chef resource. The token is
# passed via the environment and read by podman from stdin, so it never appears
# in the process table or in a shell history.
# ---------------------------------------------------------------------------
execute 'podman registry login' do
  command "printf '%s' \"$REGISTRY_TOKEN\" | podman login #{Shellwords.escape(api['registry']['host'])} " \
          "-u #{Shellwords.escape(api['registry']['username'])} --password-stdin"
  environment('REGISTRY_TOKEN' => api['registry']['token'].to_s)
  sensitive true
  live_stream false
  not_if { api['registry']['token'].to_s.empty? }
end

execute 'pull application image' do
  command "podman pull #{Shellwords.escape(api['image'])}"
  retries 3
  retry_delay 10
  notifies :restart, 'service[employee-api]', :delayed
end

# ---------------------------------------------------------------------------
# systemd unit
# ---------------------------------------------------------------------------
template '/etc/systemd/system/employee-api.service' do
  source 'employee-api.service.erb'
  owner 'root'
  group 'root'
  mode '0644'
  variables(
    app_dir: api['app_dir'],
    image: api['image'],
    app_port: api['app_port'],
    container_name: 'employee-api'
  )
  notifies :run, 'execute[systemctl daemon-reload]', :immediately
  notifies :restart, 'service[employee-api]', :delayed
end

execute 'systemctl daemon-reload' do
  command 'systemctl daemon-reload'
  action :nothing
end

service 'employee-api' do
  supports status: true, restart: true
  action [:enable, :start]
end

# ---------------------------------------------------------------------------
# Nginx reverse proxy — public :80 in front of the container on :8080
# ---------------------------------------------------------------------------
template '/etc/nginx/sites-available/employee-api' do
  source 'nginx-site.erb'
  owner 'root'
  group 'root'
  mode '0644'
  variables(
    app_port: api['app_port'],
    nginx_port: api['nginx_port']
  )
  notifies :reload, 'service[nginx]', :delayed
end

link '/etc/nginx/sites-enabled/employee-api' do
  to '/etc/nginx/sites-available/employee-api'
  notifies :reload, 'service[nginx]', :delayed
end

# The stock default vhost also binds :80 and would shadow ours.
file '/etc/nginx/sites-enabled/default' do
  action :delete
  notifies :reload, 'service[nginx]', :delayed
end

service 'nginx' do
  supports status: true, restart: true, reload: true
  action [:enable, :start]
end

# ---------------------------------------------------------------------------
# Log rotation
# ---------------------------------------------------------------------------
template '/etc/logrotate.d/employee-api' do
  source 'logrotate.erb'
  owner 'root'
  group 'root'
  mode '0644'
  variables(log_dir: api['log_dir'])
end

# ---------------------------------------------------------------------------
# CloudWatch agent
#
# Installed from Amazon's official .deb; the instance profile carries
# CloudWatchAgentServerPolicy so no credentials are placed on the host.
# ---------------------------------------------------------------------------
remote_file '/tmp/amazon-cloudwatch-agent.deb' do
  source 'https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb'
  mode '0644'
  retries 3
  retry_delay 10
  not_if { ::File.exist?('/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl') }
end

dpkg_package 'amazon-cloudwatch-agent' do
  source '/tmp/amazon-cloudwatch-agent.deb'
  action :install
  not_if { ::File.exist?('/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl') }
end

directory '/opt/aws/amazon-cloudwatch-agent/etc' do
  owner 'root'
  group 'root'
  mode '0755'
  recursive true
end

template '/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json' do
  source 'cloudwatch-agent.json.erb'
  owner 'root'
  group 'root'
  mode '0644'
  variables(
    project: api['project'],
    log_dir: api['log_dir']
  )
  notifies :run, 'execute[restart cloudwatch agent]', :delayed
end

execute 'restart cloudwatch agent' do
  command '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl ' \
          '-a fetch-config -m ec2 -s ' \
          '-c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json'
  action :nothing
end
