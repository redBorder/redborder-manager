Name: redborder-manager
Version: %{__version}
Release: %{__release}%{?dist}
BuildArch: noarch
Summary: Package for redborder containing common functions and scripts.

License: AGPL 3.0
URL: https://github.com/redBorder/redborder-common
Source0: %{name}-%{version}.tar.gz

Requires: bash ntp dialog rvm s3cmd postgresql-pgpool-II chef-server-core redborder-common redborder-chef

%description
%{summary}

%prep
%setup -qn %{name}-%{version}

%build

%install
mkdir -p %{buildroot}/usr/lib/redborder/bin
mkdir -p %{buildroot}/etc/profile.d
mkdir -p %{buildroot}/var/chef/cookbooks
mkdir -p %{buildroot}/var/chef/data/role
mkdir -p %{buildroot}/var/chef/data/data_bag/passwords
mkdir -p %{buildroot}/var/chef/data/data_bag/rBglobal
install -D -m 0644 resources/redborder-manager.sh %{buildroot}/etc/profile.d
install -D -m 0644 resources/systemd/postgresql.service %{buildroot}/usr/lib/systemd/system/postgresql.service
install -D -m 0644 resources/systemd/kafka.service %{buildroot}/usr/lib/systemd/system/kafka.service
install -D -m 0644 resources/systemd/kafka.sysconfig %{buildroot}/etc/sysconfig/kafka.sysconfig
cp resources/bin/* %{buildroot}/usr/lib/redborder/bin
chmod 0755 %{buildroot}/usr/lib/redborder/bin/*
chmod 0644 %{buildroot}/usr/lib/redborder/bin/rb_manager_functions.sh
chmod 0644 %{buildroot}/usr/lib/redborder/bin/rb_manager_functions.rb
cp -r resources/chef/* %{buildroot}/var/chef/data
chmod -R 0644 %{buildroot}/var/chef/data

%pre
getent group opscode-pgsql >/dev/null || groupadd -r opscode.pgsql
getent passwd opscode-pgsql >/dev/null || \
    useradd -r -g opscode-pgsql -d /opt/opscode/embedded/postgresql -s /bin/bash \
    -c "PostgreSQL" opscode-pgsql
exit 0


%files
%defattr(0755,root,root)
/usr/lib/redborder/bin
%defattr(0644,root,root)
/usr/lib/systemd/system/postgresql.service
/usr/lib/systemd/system/kafka.service
/etc/sysconfig/kafka.sysconfig
/etc/profile.d/redborder-manager.sh
/usr/lib/redborder/bin/rb_manager_functions.sh
/usr/lib/redborder/bin/rb_manager_functions.rb
/var/chef/data

#/usr/lib/redborder/bin/rb_service
#/usr/lib/redborder/bin/rb_clean_riak_data.sh
#/usr/lib/redborder/bin/rb_create_manager_role.rb
#/usr/lib/redborder/bin/rb_get_managers.sh
#/usr/lib/redborder/bin/rb_get_managers.rb
#/usr/lib/redborder/bin/rb_manager_ssh.sh
#/usr/lib/redborder/bin/rb_nodes_with_service.rb
#/usr/lib/redborder/bin/rb_set_mode.rb
#/usr/lib/redborder/bin/rb_set_service.sh
#/usr/lib/redborder/bin/rb_set_service.rb
#/usr/lib/redborder/bin/rb_chef_node
#/usr/lib/redborder/bin/rb_route53.sh
#/usr/lib/redborder/bin/rb_upload_ips
#/usr/lib/redborder/bin/rb_aws_secondary_ip.sh
#/usr/lib/redborder/bin/rb_external_s3
#/usr/lib/redborder/bin/rb_upload_cookbooks.sh
#/usr/lib/redborder/bin/rb_md5_file.py
#/usr/lib/redborder/bin/rb_create_rsa.sh
#/usr/lib/redborder/bin/rb_riak_status.rb
#/usr/lib/redborder/bin/rb_update_timestamp.rb
#/usr/lib/redborder/bin/rb_set_modules.rb
#/usr/lib/redborder/bin/rb_set_topic.rb
#/usr/lib/redborder/bin/rb_external_memcached
#/usr/lib/redborder/bin/rb_external_postgresql
#/usr/lib/redborder/bin/rb_initpg.sh
#/usr/lib/redborder/bin/rb_chef_role
#/usr/lib/redborder/bin/rb_backup_node.rb
#/usr/lib/redborder/bin/rb_create_rabbitusers.sh
#/usr/lib/redborder/bin/rb_upload_certs.sh
#/usr/lib/redborder/bin/rb_create_cert.sh
%doc

%changelog
* Thu Jul 07 2016 Carlos J. Mateos <cjmateos@redborder.com> - 1.0.0-1
- Added various rb scripts
* Thu Jun 23 2016 Juan J. Prieto <jjprieto@redborder.com> - 1.0.0-1
- first spec version
