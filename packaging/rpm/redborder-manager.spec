%undefine __brp_mangle_shebangs

Name: redborder-manager
Version: %{__version}
Release: %{__release}%{?dist}
BuildArch: noarch
Summary: Main package for redborder manager

License: AGPL 3.0
URL: https://github.com/redBorder/redborder-manager
Source0: %{name}-%{version}.tar.gz


Requires: bash chrony dialog postgresql s3cmd dmidecode rsync nc dhclient
Requires: telnet redborder-serf redborder-common redborder-chef-client
Requires: redborder-cookbooks redborder-rubyrvm redborder-cli
Requires: synthetic-producer tcpdump
Requires: chef-workstation
Requires: alternatives java-1.8.0-openjdk java-1.8.0-openjdk-devel
Requires: network-scripts network-scripts-teamd
Requires: redborder-cgroups rb-logstatter redborder-pythonlibs
Requires: mcli

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
mkdir -p %{buildroot}/usr/lib/redborder/tools
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
cp resources/tools/* %{buildroot}/usr/lib/redborder/tools
cp -r resources/check/* %{buildroot}/usr/lib/redborder/lib/check
chmod 0755 %{buildroot}/usr/lib/redborder/bin/*
chmod 0755 %{buildroot}/usr/lib/redborder/scripts/*
chmod 0755 %{buildroot}/usr/lib/redborder/tools/*
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
if ls /opt/chef-workstation/embedded/lib/ruby/gems/3.1.0/specifications/default/openssl-3.0.1.* 1> /dev/null 2>&1; then
    rm -f /opt/chef-workstation/embedded/lib/ruby/gems/3.1.0/specifications/default/openssl-3.0.1.*
fi
/usr/lib/redborder/bin/rb_rubywrapper.sh -c
firewall-cmd --zone=public --add-port=443/tcp --permanent
#firewall-cmd --zone=public --add-port=7946/tcp --permanent
#firewall-cmd --zone=public --add-port=7373/tcp --permanent
#firewall-cmd --zone=public --add-port=5353/tcp --permanent
firewall-cmd --reload
# adjust kernel printk settings for the console
echo "kernel.printk = 1 4 1 7" > /usr/lib/sysctl.d/99-redborder-printk.conf
/sbin/sysctl --system > /dev/null 2>&1

%posttrans
update-alternatives --set java $(find /usr/lib/jvm/*java-1.8.0-openjdk* -name "java"|head -n 1)

%files
%defattr(0755,root,root)
/usr/lib/redborder/bin
/usr/lib/redborder/scripts
/usr/lib/redborder/tools
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
* Tue Apr 22 2025 Rafael Gómez <rgomez@redborder.com> - 5.1.1-1
- Remove openssl gemspec file handling from chef-workstation package

* Fri Mar 28 2025 Vicente Mesa, José Navarro <vimesa@redborder.com, jnavarro@redborder.com> - 5.1.0-1
- Chef-workstation update handling conflict with embedded openssl gemspec

* Mon Jul 29 2024 Miguel Alvarez <malvarez@redborder.com> - 2.4.0-1
- Add redboder tools path

* Fri Jan 19 2024 Miguel Negrón <manegron@redborder.com> - 1.0.7-1
- Add journald script to configure logs storage

* Fri Jan 19 2024 David Vanhoucke <dvanhoucke@redborder.com> - 1.0.6-1
- Add rb-arubacentral

* Mon Dec 18 2023 Miguel Álvarez <malvarez@redborder.com> - 1.0.5-1
- Add rb-logstatter

* Thu Dec 14 2023 Miguel Negrón <manegron@redborder.com> - 1.0.4-1
- Fix order of cookbooks

* Fri Dec 01 2023 David Vanhoucke <dvanhoucke@redborder.com> - 1.0.3-1
- Add selinux

* Thu Nov 30 2023 David Vanhoucke <dvanhoucke@redborder.com> - 1.0.2-1
- Change rescue of json parse

* Wed Nov 29 2023 David Vanhoucke <dvanhoucke@redborder.com> - 1.0.1-1
- Fix firewall public zone broadcast

* Wed Nov 29 2023 Miguel Álvarez <malvarez@redborder.com> - 1.0.0-1
- Add cgroup

* Tue Nov 28 2023 David Vanhoucke <dvanhoucke@redborder.com> - 0.9.9-1
- Fix single interface manager configuration

* Tue Nov 28 2023 David Vanhoucke <dvanhoucke@redborder.com> - 0.9.8-1
- Fix sync network routes and allow no gateways

* Tue Nov 21 2023 David Vanhoucke <dvanhoucke@redborder.com> - 0.9.7-1
- Add support for sync network

* Tue Nov 21 2023 David Vanhoucke, Vicente Mesa <dvanhoucke@redborder.com, vimesa@redborder.com> - 0.9.6-1
- Fix firewall direct rules
- Add dhclient

* Thu Nov 16 2023 Vicente Mesa <vimesa@redborder.com> - 0.9.5-1
- Fix random hostname

* Wed Nov 15 2023 Miguel Negron, Miguel Álvarez <manegron@redborder.com, malvarez@redborder.com> - 0.9.4-1
- Fix chef license auto accept and fix serf DNS

* Tue Nov 14 2023 David Vanhoucke <dvanhoucke@redborder.com> - 0.9.3-1
- Fix RSA creation for RHEL9

* Tue Nov 14 2023 Miguel Negron <manegron@redborder.com> - 0.9.2-1
- Add network scripts

* Fri Sep 22 2023 Miguel Álvarez <malvarez@redborder.com> - 0.9.1-1
- Change ntp by chrony
- Added rbaioutliers in cookbook list for upload in rb_configure_leader.sh
- Updated manager.json chef role for outliers adaption

* Thu Sep 14 2023 Julio Peralta <jperalta@redborder.com> - 0.9.0
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
