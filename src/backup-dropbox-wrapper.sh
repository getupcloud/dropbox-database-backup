#!/bin/bash

if [ ! -d $OPENSHIFT_DATA_DIR/.virtenv ]; then
    virtualenv $OPENSHIFT_DATA_DIR/.virtenv
    source $OPENSHIFT_DATA_DIR/.virtenv/bin/activate
    easy_install -U setuptools
    pip install dropbox
else
    source $OPENSHIFT_DATA_DIR/.virtenv/bin/activate
fi

exec $@
