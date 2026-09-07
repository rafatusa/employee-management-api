#
# chef-solo / chef-client --local-mode configuration.
# Paths are relative to /opt/chef-run, where the configure stage unpacks the
# cookbook bundle on the target host.
#

cookbook_path   File.join(File.dirname(__FILE__), 'cookbooks')
node_path       File.join(File.dirname(__FILE__), 'nodes')
file_cache_path '/var/chef/cache'
log_level       :info
log_location    STDOUT
ssl_verify_mode :verify_peer
