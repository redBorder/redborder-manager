Name: redborder-manager
Version: %{__version}
Release: %{__release}%{?dist}
BuildArch: noarch
Summary: Package for redborder containing common functions and scripts.

License: AGPL 3.0
URL: https://github.com/redBorder/redborder-common
Source0: %{name}-%{version}.tar.gz

Requires: bash dialog rvm s3cmd postgresql-pgpool-II

%description
%{summary}

%prep
%setup -qn %{name}-%{version}

%build

%install
mkdir -p %{buildroot}/usr/lib/redborder/bin
mkdir -p %{buildroot}/etc/profile.d
install -D -m 0644 redborder-manager.sh %{buildroot}/etc/profile.d
install -D -m 0644 resources/rb_manager_functions.sh %{buildroot}/usr/lib/redborder/bin
install -D -m 0644 resources/rb_manager_functions.rb %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_clean_riak_data.sh %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_create_manager_role.rb %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_get_managers.sh %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_get_managers.rb %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_manager_ssh.sh %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_nodes_with_service.rb %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_service %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_set_mode.rb %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_set_service.sh %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_set_service.rb %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_chef_node %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_route53.sh %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_upload_ips %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_aws_secondary_ip.sh %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_external_s3 %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_upload_cookbooks.sh %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_md5_file.py %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_create_rsa.sh %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_riak_status.rb %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_update_timestamp.rb %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_set_modules.rb %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_set_topic.rb %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_external_memcached %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_external_postgresql %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_initpg.sh %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_chef_role %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_backup_node.rb %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_create_rabbitusers.sh %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_upload_certs.sh %{buildroot}/usr/lib/redborder/bin
install -D -m 0755 resources/rb_create_cert.sh %{buildroot}/usr/lib/redborder/bin
%pre

%files
%defattr(0644,root,root)
/etc/profile.d/redborder-manager.sh
/usr/lib/redborder/bin/rb_manager_functions.sh
/usr/lib/redborder/bin/rb_manager_functions.rb
%defattr(0755,root,root)
/usr/lib/redborder/bin/rb_service
/usr/lib/redborder/bin/rb_clean_riak_data.sh
/usr/lib/redborder/bin/rb_create_manager_role.rb
/usr/lib/redborder/bin/rb_get_managers.sh
/usr/lib/redborder/bin/rb_get_managers.rb
/usr/lib/redborder/bin/rb_manager_ssh.sh
/usr/lib/redborder/bin/rb_nodes_with_service.rb
/usr/lib/redborder/bin/rb_set_mode.rb
/usr/lib/redborder/bin/rb_set_service.sh
/usr/lib/redborder/bin/rb_set_service.rb
/usr/lib/redborder/bin/rb_chef_node
/usr/lib/redborder/bin/rb_route53.sh
/usr/lib/redborder/bin/rb_upload_ips
/usr/lib/redborder/bin/rb_aws_secondary_ip.sh
/usr/lib/redborder/bin/rb_external_s3
/usr/lib/redborder/bin/rb_upload_cookbooks.sh
/usr/lib/redborder/bin/rb_md5_file.py
/usr/lib/redborder/bin/rb_create_rsa.sh
/usr/lib/redborder/bin/rb_riak_status.rb
/usr/lib/redborder/bin/rb_update_timestamp.rb
/usr/lib/redborder/bin/rb_set_modules.rb
/usr/lib/redborder/bin/rb_set_topic.rb
/usr/lib/redborder/bin/rb_external_memcached
/usr/lib/redborder/bin/rb_external_postgresql
/usr/lib/redborder/bin/rb_initpg.sh
/usr/lib/redborder/bin/rb_chef_role
/usr/lib/redborder/bin/rb_backup_node.rb
/usr/lib/redborder/bin/rb_create_rabbitusers.sh
/usr/lib/redborder/bin/rb_upload_certs.sh
/usr/lib/redborder/bin/rb_create_cert.sh
%doc

%changelog
* Thu Jul 07 2016 Carlos J. Mateos <cjmateos@redborder.com> - 1.0.0-2
- Added various rb scripts
* Thu Jun 23 2016 Juan J. Prieto <jjprieto@redborder.com> - 1.0.0-1
- first spec version
