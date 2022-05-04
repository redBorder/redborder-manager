#!/bin/bash

if [ -d /var/www/repo ]; then
        reposync -n -d -q -r base -p /var/www/repo
        reposync -n -d -q -r updates -p /var/www/repo
        pushd /var/www/repo &>/dev/null
        if [ -d repodata ]; then
                createrepo -q --update .
        else
                createrepo -q .
        fi
        popd &>/dev/null
fi
exit 0;