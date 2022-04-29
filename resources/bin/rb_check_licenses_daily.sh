#!/bin/bash
source /etc/profile.d/rvm.sh

if [ -d /var/www/rb-rails ]; then
    if [ -d /etc/licenses ]; then
        for license in $(ls /etc/licenses 2>/dev/null); do
            expire_at=$(cat /etc/licenses/${license} | /bin/jq '.["info"]["expire_at"]' 2>/dev/null)
            license_uuid=$(cat /etc/licenses/${license}| /bin/jq '.["info"]["uuid"]' 2>/dev/null | sed 's/"//g')
            if [ "x${expire_at}" == "xnull" ]; then
                # nothing to do
                continue
            else
                current_date=$(date '+%s')
                if [ ${expire_at} -lt ${current_date} ]; then
                    # just expired?
                    continue
                else
                    time_to_expire=$((${expire_at}-${current_date}))
                    if [ ${time_to_expire} -gt 86400 ]; then
                        # Valid license > 24h
                        continue
                    else
                        # license next to expire (<24h), generate email
                        rvm gemset use web &>/dev/null
                        pushd /var/www/rb-rails &>/dev/null
                        rake redBorder:admin_email['License next to expire',"The license with UUID ${license_uuid} will expire in 1 day"]
                        popd &>/dev/null
                    fi
                fi
            fi
        done
    fi
fi

exit 0;
## vim:ts=4:sw=4:expandtab:ai:nowrap:formatoptions=croqln:
