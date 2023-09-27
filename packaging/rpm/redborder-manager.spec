Name: redborder-manager
Version: %{__version}
Release: %{__release}%{?dist}
BuildArch: noarch
Summary: Main package for redborder manager

License: AGPL 3.0
URL: https://github.com/redBorder/redborder-manager
Source0: %{name}-%{version}.tar.gz

Requires: bash ntp dialog postgresql s3cmd dmidecode rsync nc
Requires: telnet redborder-serf redborder-common redborder-chef-client
Requires: redborder-cookbooks redborder-rubyrvm redborder-cli
Requires: synthetic-producer darklist-updated tcpdump
%description
%{summary}

%prep
%setup -qn %{name}-%{version}

%build

%install
mkdir -p %{buildroot}/etc/redborder
mkdir -p %{buildroot}/usr/lib/redborder/bin
mkdir -p %{buildroot}/usr/lib/redborder/scripts
mkdir -p %{buildroot}/usr/lib/redborder/lib
mkdir -p %{buildroot}/usr/lib/redborder/lib/check
mkdir -p %{buildroot}/etc/profile.d
mkdir -p %{buildroot}/var/chef/cookbooks
mkdir -p %{buildroot}/var/chef/solo
mkdir -p %{buildroot}/var/chef/data/role
mkdir -p %{buildroot}/var/chef/data/data_bag
install -D -m 0644 resources/redborder-manager.sh %{buildroot}/etc/profile.d
install -D -m 0644 resources/dialogrc %{buildroot}/etc/redborder
cp resources/bin/* %{buildroot}/usr/lib/redborder/bin
cp resources/scripts/* %{buildroot}/usr/lib/redborder/scripts
cp -r resources/check/* %{buildroot}/usr/lib/redborder/lib/check
chmod 0755 %{buildroot}/usr/lib/redborder/bin/*
chmod 0755 %{buildroot}/usr/lib/redborder/scripts/*
install -D -m 0644 resources/lib/rb_wiz_lib.rb %{buildroot}/usr/lib/redborder/lib
install -D -m 0644 resources/lib/rb_config_utils.rb %{buildroot}/usr/lib/redborder/lib
install -D -m 0644 resources/lib/rb_manager_functions.sh %{buildroot}/usr/lib/redborder/lib
cp -r resources/chef/role %{buildroot}/var/chef/data/
chmod -R 0644 %{buildroot}/var/chef/data
cp -r resources/chef/solo %{buildroot}/var/chef/
install -D -m 0644 resources/etc/mode-list.yml %{buildroot}/usr/lib/redborder
install -D -m 0644 resources/systemd/rb-init-conf.service %{buildroot}/usr/lib/systemd/system/rb-init-conf.service
install -D -m 0644 resources/systemd/rb-bootstrap.service %{buildroot}/usr/lib/systemd/system/rb-bootstrap.service
install -D -m 0755 resources/lib/dhclient-enter-hooks %{buildroot}/usr/lib/redborder/lib/dhclient-enter-hooks
install -D -m 0644 resources/etc/01default_handlers.json %{buildroot}/etc/serf/01default_handlers.json

%pre

%post
/usr/lib/redborder/bin/rb_rubywrapper.sh -c
firewall-cmd --zone=public --add-port=443/tcp --permanent
firewall-cmd --zone=public --add-port=7946/tcp --permanent
#firewall-cmd --zone=public --add-port=7373/tcp --permanent
#firewall-cmd --zone=public --add-port=5353/tcp --permanent
firewall-cmd --reload

%files
%defattr(0755,root,root)
/usr/lib/redborder/bin
/usr/lib/redborder/scripts
/usr/lib/redborder/lib/check
%defattr(0755,root,root)
/etc/profile.d/redborder-manager.sh
/usr/lib/redborder/lib/dhclient-enter-hooks
%defattr(0644,root,root)
/etc/redborder
/usr/lib/redborder/mode-list.yml
/usr/lib/systemd/system/rb-init-conf.service
/usr/lib/systemd/system/rb-bootstrap.service
/usr/lib/redborder/lib/rb_wiz_lib.rb
/usr/lib/redborder/lib/rb_config_utils.rb
/usr/lib/redborder/lib/rb_manager_functions.sh
/etc/serf/01default_handlers.json
/var/chef/data
/var/chef/solo
%doc

%changelog
* Thu Sep 26 2023 Miguel Álvarez <malvarez@redborder.com> - 0.9.1-1
- Added rbaioutliers in cookbook list for upload in rb_configure_leader.sh
- Updated manager.json chef role for outliers adaption

* Thu Sep 14 2023 Julio Peralta <jperalta@redborder.com> - 0.9.0-1
- Removed IF="," when accesing zookeeper in rb_get_zkinfo.sh

* Wed Sep 13 2023 Julio Peralta <jperalta@redborder.com> - 0.8.9-1
- Fix chef running duplicate on boot

* Thu May 04 2023 Luis J. Blanco <ljblanco@redborder.com> - 0.8.8-1
- Add ohai recipe to the list 

* Mon Apr 24 2023 Luis J. Blanco <ljblanco@redborder.com> - 0.8.7-1
- Scripts recovery from old version for monitor sensors

* Tue Apr 18 2023 Luis J. Blanco <ljblanco@redborder.com> - 0.8.6-1
- Databag monitors

* Thu Jan 26 2023 Luis Blanco <ljblanco@redborder.com> - 0.8.4-1
- Check config.json is a directory when the setup of s3

* Wed Jan 25 2023 Luis Blanco <ljblanco@redborder.com> - 
- Open snmp ports

* Wed May 11 2022 Eduardo Reyes <eareyes@redborder.com> -
- Add check directory

* Fri Jan 28 2022 Eduardo Reyes <eareyes@redborder.com> -
- Add rb_synthetic_producer.rb

* Wed Jan 31 2018 Alberto Rodriguez <arodriguez@redborder.com> - 0.0.11-1
- Add chef-solo files

* Tue Nov 22 2016 Juan J. Prieto <jjprieto@redborder.com> - 0.0.10-1
- Change rvm require and fix pack versioning.

* Wed Oct 26 2016 Juan J. Prieto <jjprieto@redborder.com> - 0.0.6-1
- Add directory scripts and support for wrapper on ruby.

* Tue Sep 06 2016 Carlos J. Mateos <cjmateos@redborder.com> - 0.0.5-1
- Add rb-init-conf service and remove chef package installation
- Remove rb_manager_functions.rb from spec

* Fri Sep 02 2016 Carlos J. Mateos <cjmateos@redborder.com> - 0.0.4-1
- Add YML config files

* Tue Aug 30 2016 Carlos J. Mateos <cjmateos@redborder.com> - 0.0.3-1
- Change chef packages

* Thu Jul 07 2016 Carlos J. Mateos <cjmateos@redborder.com> - 0.0.2-1
- Added various rb scripts and chef data

* Thu Jun 23 2016 Juan J. Prieto <jjprieto@redborder.com> - 0.0.1-1
- first spec version
