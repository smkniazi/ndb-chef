benchmarks_dir = "#{node['ndb']['user-home']}/benchmarks"

directory benchmarks_dir do
  owner node['ndb']['user']
  group node['ndb']['group']
  mode "750"
  action :create
end

sysbench_single_dir = "#{benchmarks_dir}/sysbench_single"
directory sysbench_single_dir do
  owner node['ndb']['user']
  group node['ndb']['group']
  mode "750"
  action :create
end

mysqld_host = ""
mysqld_hosts = ""
number_of_mysqld = 0
if node['ndb'].attribute?('mysqld')
  number_of_mysqld = node['ndb']['mysqld']['private_ips'].length()
  mysqld_hosts = node['ndb']['mysqld']['private_ips'].join(',')
  mysqld_host = node['ndb']['mysqld']['private_ips'][0]
end

template "#{sysbench_single_dir}/autobench.conf" do
  source "autobench_sysbench.conf.erb"
  owner node['ndb']['user']
  group node['ndb']['group']
  mode 0750
  variables({
    :sysbench_instances => "1",
    :mysqld_hosts => mysqld_host,
  })
end

sysbench_multi_dir = "#{benchmarks_dir}/sysbench_multi"
directory sysbench_multi_dir do
  owner node['ndb']['user']
  group node['ndb']['group']
  mode "750"
  action :create
end

template "#{sysbench_multi_dir}/autobench.conf" do
  source "autobench_sysbench.conf.erb"
  owner node['ndb']['user']
  group node['ndb']['group']
  mode 0750
  variables({
    :sysbench_instances => number_of_mysqld,
    :mysqld_hosts => mysqld_hosts,
  })
end

dbt2_single_dir = "#{benchmarks_dir}/dbt2_single"
directory dbt2_single_dir do
  owner node['ndb']['user']
  group node['ndb']['group']
  mode "750"
  action :create
end

template "#{dbt2_single_dir}/autobench.conf" do
  source "autobench_dbt2.conf.erb"
  owner node['ndb']['user']
  group node['ndb']['group']
  mode 0750
  variables({
    :mysqld_hosts => mysqld_host,
  })
end

cookbook_file "#{dbt2_single_dir}/dbt2_run_1.conf" do
  source "dbt2_run_1.conf.single"
  owner node['ndb']['user']
  group node['ndb']['group']
  mode 0750
end

dbt2_multi_dir = "#{benchmarks_dir}/dbt2_multi"
directory dbt2_multi_dir do
  owner node['ndb']['user']
  group node['ndb']['group']
  mode "750"
  action :create
end

template "#{dbt2_multi_dir}/autobench.conf" do
  source "autobench_dbt2.conf.erb"
  owner node['ndb']['user']
  group node['ndb']['group']
  mode 0750
  variables({
    :mysqld_hosts => mysqld_hosts,
  })
end

cookbook_file "#{dbt2_multi_dir}/dbt2_run_1.conf" do
  source "dbt2_run_1.conf.multi"
  owner node['ndb']['user']
  group node['ndb']['group']
  mode 0750
end


exec = "#{node['ndb']['scripts_dir']}/mysql-client.sh"
bash 'create-bench-db-and-user' do
  user "root"
  code <<-EOF
      set -e
      #{exec} -e \"CREATE DATABASE IF NOT EXISTS ycsb\"
      #{exec} -e \"CREATE USER IF NOT EXISTS \'#{node['mysql']['benchmark_user']}\'@\'%\' IDENTIFIED BY \'#{node['mysql']['benchmark_user_password']}\';\"
      #{exec} -e \"GRANT NDB_STORED_USER ON *.* TO \'#{node['mysql']['benchmark_user']}\'@\'%\';\"
      #{exec} -e \"GRANT ALL PRIVILEGES ON ycsb.* TO \'#{node['mysql']['benchmark_user']}\'@\'%\';\"
      #{exec} ycsb -e \"CREATE TABLE IF NOT EXISTS usertable (YCSB_KEY VARCHAR(255) PRIMARY KEY, FIELD0 varchar(100), FIELD1 varchar(100), FIELD2 varchar(100), FIELD3 varchar(100), FIELD4 varchar(100), FIELD5 varchar(100), FIELD6 varchar(100), FIELD7 varchar(100), FIELD8 varchar(100), FIELD9 varchar(100));\"
    EOF
end

include_recipe "java"

package 'git'

package 'maven'

bash 'clone-and-build-ycsb' do
    user node['ndb']['user']
    cwd "#{benchmarks_dir}"
    code <<-EOF
      rm -rf YCSB
      #git clone https://github.com/logicalclocks/YCSB 
      git clone https://github.com/smkniazi/YCSB 
      cd YCSB
      mvn -pl site.ycsb:rondb-binding -am clean package
      mvn -pl site.ycsb:jdbc-binding -am clean package
      mkdir lib
      cd lib
      wget #{node['download_url']}/#{node['mysql']['mysql_connector']}

      if [ -d #{node['mysql']['version_dir']} ]; then
        ln -s #{node['mysql']['version_dir']}/lib/libndbclient.so.6.1.0 libndbclient.so
      else 
          wget #{node['ndb']['url']}
          tar -xvzf rondb-#{node['ndb']['version']}-linux-glibc#{node['ndb']['glib_version']}-x86_64.tar.gz rondb-#{node['ndb']['version']}-linux-glibc#{node['ndb']['glib_version']}-x86_64/lib/libndbclient.so.6.1.0
          mv rondb-#{node['ndb']['version']}-linux-glibc#{node['ndb']['glib_version']}-x86_64/lib/libndbclient.so.6.1.0 libndbclient.so
          rm -f rondb-#{node['ndb']['version']}-linux-glibc#{node['ndb']['glib_version']}-x86_64.*
      fi
EOF
end

template "#{benchmarks_dir}/YCSB/db.properties" do
  source "ycsb/db.properties.erb"
  owner node['ndb']['user']
  group node['ndb']['group']
  mode 0750
  variables({
    :mysqld_host => mysqld_host,
  })
end


template "#{benchmarks_dir}/YCSB/create-table.sh" do
  source "ycsb/create-table.sh.erb"
  owner node['ndb']['user']
  group node['ndb']['group']
  mode 0750
  variables({
    :mysqld_host => mysqld_host,
  })
end

template "#{benchmarks_dir}/YCSB/jdbc-load.sh" do
  source "ycsb/jdbc-load.sh.erb"
  owner node['ndb']['user']
  group node['ndb']['group']
  mode 0750
end

template "#{benchmarks_dir}/YCSB/jdbc-run.sh" do
  source "ycsb/jdbc-run.sh.erb"
  owner node['ndb']['user']
  group node['ndb']['group']
  mode 0750
end


template "#{benchmarks_dir}/YCSB/clusterj-load.sh" do
  source "ycsb/clusterj-load.sh.erb"
  owner node['ndb']['user']
  group node['ndb']['group']
  mode 0750
end

template "#{benchmarks_dir}/YCSB/clusterj-run.sh" do
  source "ycsb/clusterj-run.sh.erb"
  owner node['ndb']['user']
  group node['ndb']['group']
  mode 0750
end

