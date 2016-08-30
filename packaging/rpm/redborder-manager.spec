Name: redborder-manager
Version: %{__version}
Release: %{__release}%{?dist}
BuildArch: noarch
Summary: Package for redborder containing common functions and scripts.

License: AGPL 3.0
URL: https://github.com/redBorder/redborder-common
Source0: %{name}-%{version}.tar.gz

Requires: bash ntp dialog rvm s3cmd dmidecode cloud-init postgresql-pgpool-II chef-server-core redborder-serf redborder-common chef redborder-chef-client

%description
%{summary}

%prep
%setup -qn %{name}-%{version}

%build

%install
mkdir -p %{buildroot}/usr/lib/redborder/bin
mkdir -p %{buildroot}/usr/lib/redborder/lib
mkdir -p %{buildroot}/etc/profile.d
mkdir -p %{buildroot}/var/chef/cookbooks
mkdir -p %{buildroot}/var/chef/data/role
mkdir -p %{buildroot}/var/chef/data/data_bag/passwords
mkdir -p %{buildroot}/var/chef/data/data_bag/rBglobal
install -D -m 0644 resources/redborder-manager.sh %{buildroot}/etc/profile.d
cp resources/bin/* %{buildroot}/usr/lib/redborder/bin
chmod 0755 %{buildroot}/usr/lib/redborder/bin/*
chmod 0644 %{buildroot}/usr/lib/redborder/bin/rb_manager_functions.sh
chmod 0644 %{buildroot}/usr/lib/redborder/bin/rb_manager_functions.rb
install -D -m 0755 resources/lib/rb_wiz_lib.rb %{buildroot}/usr/lib/redborder/lib
cp -r resources/chef/* %{buildroot}/var/chef/data
chmod -R 0644 %{buildroot}/var/chef/data

%pre
getent group opscode-pgsql >/dev/null || groupadd -r opscode.pgsql
getent passwd opscode-pgsql >/dev/null || \
    useradd -r -g opscode-pgsql -d /opt/opscode/embedded/postgresql -s /bin/bash \
    -c "PostgreSQL" opscode-pgsql
exit 0

%post
firewall-cmd --zone=public --add-port=443/tcp --permanent
firewall-cmd --zone=public --add-port=7946/tcp --permanent
firewall-cmd --zone=public --add-port=7373/tcp --permanent
firewall-cmd --reload

%files
%defattr(0755,root,root)
/usr/lib/redborder/bin
%defattr(0755,root,root)
/usr/lib/redborder/lib/rb_wiz_lib.rb
/etc/profile.d/redborder-manager.sh
/usr/lib/redborder/bin/rb_manager_functions.sh
/usr/lib/redborder/bin/rb_manager_functions.rb
/var/chef/data

%doc

%changelog
* Thu Aug 30 2016 Carlos J. Mateos <cjmateos@redborder.com> - 1.0.0-3
- Change chef packages

* Thu Jul 07 2016 Carlos J. Mateos <cjmateos@redborder.com> - 1.0.0-2
- Added various rb scripts

* Thu Jun 23 2016 Juan J. Prieto <jjprieto@redborder.com> - 1.0.0-1
- first spec version
