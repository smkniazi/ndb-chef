require File.expand_path(File.dirname(__FILE__) + '/get_ndbapi_addrs')

ndb_connectstring()

directory node[:ndb][:mgm_dir] do
  owner node[:ndb][:user]
  group node[:ndb][:user]
  mode "755"
  recursive true
end

found_id=-1
id=node[:mgm][:id]
my_ip = my_private_ip()

for mgm in node[:ndb][:mgmd][:private_ips]
  if my_ip.eql? mgm
    Chef::Log.info "Found matching IP address in the list of mgmd nodes: #{mgm}. ID= #{id}"
    found_id = id
  end
  id += 1
end 
Chef::Log.info "Found ID IS: #{found_id}"
if found_id == -1
  raise "Could not find matching IP address #{my_ip} in the list of mgmd nodes: " + node[:ndb][:mgmd][:private_ips].join(",")
end

for script in node[:mgm][:scripts] do
  template "#{node[:ndb][:scripts_dir]}/#{script}" do
    source "#{script}.erb"
    owner "root"
    group "root"
    mode 0655
    variables({ :node_id => found_id })
  end
end 

service_name = "ndb_mgmd"

service "#{service_name}" do
  case node[:ndb][:use_systemd]
    when "true"
    provider Chef::Provider::Service::Systemd
  end
  supports :restart => true, :stop => true, :start => true, :status => true
  action :nothing
end

template "/etc/init.d/#{service_name}" do
  only_if { node[:ndb][:use_systemd] != "true" }
  source "#{service_name}.erb"
  owner node[:ndb][:user]
  group node[:ndb][:user]
  mode 0754
  variables({ :node_id => found_id })
  notifies :enable, "service[#{service_name}]"
end


case node[:platform_family]
  when "debian"
systemd_script = "/lib/systemd/system/#{service_name}.service"
  when "rhel"
systemd_script = "/usr/lib/systemd/system/#{service_name}.service" 
end

template systemd_script do
  only_if { node[:ndb][:use_systemd] == "true" }
    source "#{service_name}.service.erb"
    owner node[:ndb][:user]
    group node[:ndb][:user]
    mode 0754
    cookbook 'ndb'
    variables({ :node_id => found_id })
    notifies :enable, "service[#{service_name}]"
end




# Need to call get_ndbapi_addrs to set them before instantiating config.ini
get_ndbapi_addrs()

template "#{node[:ndb][:root_dir]}/config.ini" do
  source "config.ini.erb"
  owner node[:ndb][:user]
  group node[:ndb][:user]
  mode 0644
  variables({
              :num_client_slots => node[:ndb][:num_ndb_slots_per_client].to_i
            })
  notifies :restart, "service[ndb_mgmd]", :immediately
end


  if node[:kagent][:enabled] == "true"
   mgm_id = found_id + (node[:mgm][:id]-1)

    kagent_config "mgmserver" do
      service "NDB"
      start_script "#{node[:ndb][:scripts_dir]}/mgm-server-start.sh"
      stop_script  "#{node[:ndb][:scripts_dir]}/mgm-server-stop.sh"
      log_file "#{node[:ndb][:log_dir]}/ndb_#{mgm_id}_out.log"
      pid_file "#{node[:ndb][:log_dir]}/ndb_#{mgm_id}.pid"
      config_file "#{node[:ndb][:root_dir]}/config.ini"
      command "ndb_mgm"
      command_user "root"
      command_script "#{node[:ndb][:scripts_dir]}/mgm-client.sh"
    end
  end

ndb_start "ndb_mgmd" do
end


# Put public key of this mgmd-host in .ssh/authorized_keys of all ndbd and mysqld nodes
homedir = node[:ndb][:user].eql?("root") ? "/root" : "/home/#{node[:ndb][:user]}"
Chef::Log.info "Home dir is #{homedir}. Generating ssh keys..."

# bash "generate-ssh-keypair-for-mgmd" do
#  user node[:ndb][:user]
#   code <<-EOF
#      ssh-keygen -b 2048 -f #{homedir}/.ssh/id_rsa -t rsa -q -N ''
#   EOF
#  not_if { ::File.exists?( "#{homedir}/.ssh/id_rsa" ) }
# end


# # IO.read() reads the contents of the entire file in, and then closes the file.
# ndb_mgmd_publickey "#{homedir}" do
# end
# template "#{homedir}/.ssh/config" do
#   source "ssh_config.erb"
#   owner node[:ndb][:user]
#   group node[:ndb][:user]
#   mode 0664
# end

kagent_keys "#{homedir}" do
  cb_user node[:ndb][:user]
  cb_group node[:ndb][:group]
  action :generate  
end  

kagent_keys "#{homedir}" do
  cb_user node[:ndb][:user]
  cb_group node[:ndb][:group]
  cb_name "ndb"
  cb_recipe "mgmd"  
  action :return_publickey
end  
