#!/bin/bash -e

# Run this script as root or sudo
# Set the following environment variables:
#   INSTALL_USER (the userid used for viya ansible install)



install_java () {
   echo Install java 1.8
   sudo yum -y install java-1.8.0
}

if type -p java; then
    echo found java executable in PATH
    _java=java
elif [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then
    echo found java executable in JAVA_HOME
    _java="$JAVA_HOME/bin/java"
else
    install_java
fi


if [[ "$_java" ]]; then
    version=$("$_java" -version 2>&1 | awk -F '"' '/version/ {print $2}')
    echo version "$version"
    if [[ "$version" < "1.8" ]]; then
        sudo yum -y remove java
        install_java
    else
        echo version 1.8 or greater
    fi
fi


if ! type -p ansible;  then
   # install Ansible
   pip install 'ansible==2.4.3'
fi

if ! type -p git; then
   # install git
   sudo yum install -y git
fi

ANSIBLE_LOG_PATH=/tmp/prereqs.log ansible-playbook -v /tmp/prereqs.yml -e "INSTALL_USER=${INSTALL_USER}"






