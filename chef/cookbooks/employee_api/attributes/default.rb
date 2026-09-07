#
# Defaults. Every value here is overridden by the node JSON that the configure
# stage renders from terraform outputs and repository secrets.
#

default['employee_api']['project']     = 'employee-management-api'
default['employee_api']['app_port']    = 8080
default['employee_api']['nginx_port']  = 80
default['employee_api']['image']       = ''
default['employee_api']['app_user']    = 'appsvc'
default['employee_api']['app_dir']     = '/opt/employee-api'
default['employee_api']['log_dir']     = '/var/log/employee-api'
default['employee_api']['aws_region']  = 'us-east-1'

default['employee_api']['registry']['host']     = 'ghcr.io'
default['employee_api']['registry']['username'] = ''
default['employee_api']['registry']['token']    = ''

default['employee_api']['database']['host']     = ''
default['employee_api']['database']['port']     = 5432
default['employee_api']['database']['name']     = 'employees'
default['employee_api']['database']['user']     = 'employees'
default['employee_api']['database']['password'] = ''

default['employee_api']['admin']['username'] = 'admin'
default['employee_api']['admin']['password'] = ''
