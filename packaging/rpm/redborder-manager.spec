Name: redborder-manager
Version: %{__version}
Release: %{__release}%{?dist}
BuildArch: noarch
Summary: Main package for redborder manager

License: AGPL 3.0
URL: https://github.com/redBorder/redborder-manager
Source0: %{name}-%{version}.tar.gz

Requires: bash ntp dialog rvm postgresql s3cmd dmidecode rsync redborder-serf redborder-common redborder-chef-client redborder-cookbooks

%description
%{summary}

%prep
%setup -qn %{name}-%{version}

%build

%install
mkdir -p %{buildroot}/etc/redborder
mkdir -p %{buildroot}/usr/lib/redborder/bin
mkdir -p %{buildroot}/usr/lib/redborder/lib
mkdir -p %{buildroot}/etc/profile.d
mkdir -p %{buildroot}/var/chef/cookbooks
mkdir -p %{buildroot}/var/chef/data/role
mkdir -p %{buildroot}/var/chef/data/data_bag/passwords
mkdir -p %{buildroot}/var/chef/data/data_bag/rBglobal
mkdir -p %{buildroot}/var/chef/data/data_bag_encrypted/passwords
install -D -m 0644 resources/redborder-manager.sh %{buildroot}/etc/profile.d
install -D -m 0644 resources/dialogrc %{buildroot}/etc/redborder
cp resources/bin/* %{buildroot}/usr/lib/redborder/bin
chmod 0755 %{buildroot}/usr/lib/redborder/bin/*
install -D -m 0644 resources/lib/rb_wiz_lib.rb %{buildroot}/usr/lib/redborder/lib
install -D -m 0644 resources/lib/rb_config_utils.rb %{buildroot}/usr/lib/redborder/lib
install -D -m 0644 resources/lib/rb_manager_functions.sh %{buildroot}/usr/lib/redborder/lib
cp -r resources/chef/* %{buildroot}/var/chef/data
chmod -R 0644 %{buildroot}/var/chef/data
install -D -m 0644 resources/mode-list.yml %{buildroot}/usr/lib/redborder
install -D -m 0644 resources/systemd/rb-init-conf.service %{buildroot}/usr/lib/systemd/system/rb-init-conf.service
install -D -m 0755 resources/lib/dhclient-enter-hooks %{buildroot}/usr/lib/redborder/lib/dhclient-enter-hooks

%pre

%post
firewall-cmd --zone=public --add-port=443/tcp --permanent
firewall-cmd --zone=public --add-port=7946/tcp --permanent
#firewall-cmd --zone=public --add-port=7373/tcp --permanent
#firewall-cmd --zone=public --add-port=5353/tcp --permanent
firewall-cmd --reload

%files
%defattr(0755,root,root)
/usr/lib/redborder/bin
%defattr(0755,root,root)
/etc/profile.d/redborder-manager.sh
/var/chef/data
/usr/lib/redborder/lib/dhclient-enter-hooks
%defattr(0644,root,root)
/etc/redborder
/usr/lib/redborder/mode-list.yml
/usr/lib/systemd/system/rb-init-conf.service
/usr/lib/redborder/lib/rb_wiz_lib.rb
/usr/lib/redborder/lib/rb_config_utils.rb
/usr/lib/redborder/lib/rb_manager_functions.sh

%doc

%changelog
* Tue Sep 06 2016 Carlos J. Mateos <cjmateos@redborder.com> - 1.0.0-1
- Add rb-init-conf service and remove chef package installation
- Remove rb_manager_functions.rb from spec

* Fri Sep 02 2016 Carlos J. Mateos <cjmateos@redborder.com> - 1.0.0-1
- Add YML config files

* Tue Aug 30 2016 Carlos J. Mateos <cjmateos@redborder.com> - 1.0.0-1
- Change chef packages

* Thu Jul 07 2016 Carlos J. Mateos <cjmateos@redborder.com> - 1.0.0-1
- Added various rb scripts and chef data

* Thu Jun 23 2016 Juan J. Prieto <jjprieto@redborder.com> - 1.0.0-1
- first spec version
