#!/bin/bash
#######################################
# First script to configure redborder #
#######################################

source $RBBIN/rb_functions.sh
source $RBBIN/rb_manager_functions.sh
source /etc/profile

# Check if cluster is installed
if [ ! -f /etc/redborder/cluster-installed.txt -a ! -f /etc/redborder/installed.txt ]; then # Check lock files

    manufacturer=$(dmidecode -t 1| grep "Manufacturer:" | sed 's/.*Manufacturer: //')
    productname=$(dmidecode -t 1| grep "Product Name:" | sed 's/.*Product Name: //')

    #echo "Manufacturer: $manufacturer"
    #echo "Productname: $productname"
    #echo "Disk Size: " && df -h

    ## CLOUD configuration ##
    mkdir -p /etc/redborder
    if [ "x$manufacturer" == "xXen" -o "x$manufacturer" == "xxen" -o "x$manufacturer" == "xOpenStack Foundation" -o "x$manufacturer" == "xOpenStack" -o "x$manufacturer" == "xopenstack" -o "x$productname" == "xOpenStack Compute" ]; then
    [ "x$manufacturer" == "xXen" -o "x$manufacturer" == "xxen" ] && touch /etc/redborder/cloud.flag
        echo "Configuring cloud init"

        # Modify default cloud.cfg file
        cat > /etc/cloud/cloud.cfg <<_RBEOF2_
users:
- default

disable_root: 1
ssh_pwauth:   0

locale_configfile: /etc/sysconfig/i18n
resize_rootfs_tmp: /dev
ssh_deletekeys:   0
ssh_genkeytypes:  ~
syslog_fix_perms: ~

final_message: "Welcome to redborder Cloud"

runcmd:
- /var/lib/redborder/bin/rb_cloud_init.sh

cloud_init_modules:
- migrator
- bootcmd
- write-files
- growpart
- resizefs
- update_etc_hosts
- rsyslog
- users-groups
- ssh

cloud_config_modules:
 - runcmd
 - mounts
 - locale
 - set-passwords
 - timezone
 - yum-add-repo
 - package-update-upgrade-install
 - chef
 - disable-ec2-metadata

cloud_final_modules:
 - rightscale_userdata
 - scripts-per-once
 - scripts-per-boot
 - scripts-per-instance
 - scripts-user
 - ssh-authkey-fingerprints
 - keys-to-console
 - phone-home
 - final-message

system_info:
  default_user:
    name: ec2
    lock_passwd: true
    gecos: redborder Cloud User
    groups: [wheel, adm]
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
  distro: rhel
  paths:
    cloud_dir: /var/lib/cloud
    templates_dir: /etc/cloud/templates
  ssh_svcname: sshd

datasource:
  Ec2:
    timeout: 10
    max_wait: 30

# vim:syntax=yaml
_RBEOF2_

        # Enable cloud services
        systemctl enable cloud-init-local
        systemctl enable cloud-init
        systemctl enable cloud-config
        systemctl enable cloud-final

        # Starting cloud services
        systemctl start cloud-init-local
        systemctl start cloud-init

        wait_file /var/lib/cloud/data/instance-id

        systemctl start cloud-config
        systemctl start cloud-final

        # Configure hostname if cloud_init has not configured it
        [ -f /etc/redborder/cdomain ] && cdomain=$(head -n 1 /etc/redborder/cdomain | tr '\n' ' ' | awk '{print $1}')
        [ "x$cdomain" == "x" ] && cdomain="redborder.cluster"
        # Change hostname in role
        sed -i "s/manager/$(hostname -s)/g" /var/chef/data/role/manager.json #/etc/chef/role-manager*
        # Create specific role for this node
        cp /var/chef/data/role/manager.json /var/chef/data/role/$(hostname -s).json
        # And set hostname in another essential files
        sed -i "s/^HOSTNAME=.*/HOSTNAME=$(hostname -s).${cdomain}/" /etc/sysconfig/network
        sed -i "s/ manager / $(hostname -s) $(hostname -s).${cdomain} /" /etc/hosts

        ## Configuring Datastore ##
        # TODO

    else # ON-PREMISE configuration #

        # Configure hostname if cloud_init has not configured it
        [ -f /etc/redborder/cdomain ] && cdomain=$(head -n 1 /etc/redborder/cdomain | tr '\n' ' ' | awk '{print $1}')
        [ "x$cdomain" == "x" ] && cdomain="redborder.cluster"

        # Configure hostname with randon name if not set #JOTA #Get from wizard
        newhostname="rb$(< /dev/urandom tr -dc a-z0-9 | head -c10 | sed 's/ //g')"
        hostnamectl set-hostname $newhostname.$cdomain
        echo -e "127.0.0.1 `hostname` `hostname -s`" | sudo tee -a /etc/hosts &>/dev/null #check if don't use loopback IP

        # Create specific role for this node
        cp /var/chef/data/role/manager.json /var/chef/data/role/$(hostname -s).json
        # Change hostname in new role
        sed -i "s/manager/$(hostname -s)/g" /var/chef/data/role/$(hostname -s).json
        # And set hostname in another essential files
        sed -i "s/ manager |localhost.*/ $(hostname -s) $(hostname -s).${cdomain} /" /etc/hosts #Check this one...

        # NTP configuration # JOTA
        # Check Internet connectivity
        echo "Trying to adjust time"
        #systemctl stop ntpd &>/dev/null
        #ntpdate -t 5 pool.ntp.org &>/dev/null
        #if [ $? -ne 0 ]; then
        #    router=$(ip r |grep "default via"|awk '{print $3}')
        #    [ "x$router" != "x" ] && ntpdate -t 5 $router &>/dev/null
        #fi
        hwclock --systohc
        systemctl start ntpd
    fi
    # end initial configuration

    # Set cdomain file
    echo $cdomain > /etc/redborder/cdomain

    #SSH generate RSA keys # JOTA
    mkdir -p /root/.ssh && echo -e  'y\n'|ssh-keygen -q -t rsa -N "" -f ~/.ssh/id_rsa
    cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
    #SSH enable auth login
    sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/" /etc/ssh/sshd_config
    sed -i "s/\#PermitRootLogin/PermitRootLogin/" /etc/ssh/sshd_config
    systemctl restart sshd.service

    ## Initial manager mode(role) node configuration ##
    [ -f /etc/chef/initialrole ] && initialrole=$(head /etc/chef/initialrole -n 10) || initialrole=""

    # Enable and start SERF
    systemctl enable serf
    systemctl enable serf-join
    systemctl start serf
    systemctl start serf-join

    # Serf calls configure nodes script (master or custom).

fi
