#!/bin/bash -l
set -exo pipefail

CWDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${CWDIR}/common.bash"

function setup_gpadmin_user() {
    ./gpdb_src/concourse/scripts/setup_gpadmin_user.bash "$TEST_OS"
}

# Get ssh private key from REMOTE_KEY, which is assumed to
# be encode in base64. We can't pass the key content directly
# since newline doesn't work well for env variable.
function import_remote_key() {
    echo -n $REMOTE_KEY | base64 -d > ~/remote.key
    chmod 400 ~/remote.key

    eval `ssh-agent -s`
    ssh-add ~/remote.key

    # Scan for target server's public key, append port number
    # maybe run with ssh -o StrictHostKeyChecking=no?
    mkdir -p ~/.ssh
    ssh-keyscan -p $REMOTE_PORT $REMOTE_HOST > ~/.ssh/known_hosts
}

function run_remote_test() {
    source ./gpdb_src/gpAux/gpdemo/gpdemo-env.sh

    MSI=`ls ./bin_gpdb_clients_windows_rc/*.msi`
    if [[ $MSI =~ greenplum-clients-(.*)-x86_64.msi ]];
    then
      VERSION=${BASH_REMATCH[1]}
    else
      echo "invalid package name"
    fi
    scp ./bin_gpdb_clients_windows_rc/*.msi $REMOTE_USER@$REMOTE_HOST:
    ssh -T -p $REMOTE_PORT $REMOTE_USER@$REMOTE_HOST "msiexec /I greenplum-clients-$VERSION-x86_64.msi /quiet"

    scp -P $REMOTE_PORT -r ./gpdb_src/gpMgmt/bin/gpload_test/gpload2 $REMOTE_USER@$REMOTE_HOST:.
    scp -P $REMOTE_PORT ./gpdb_src/src/test/regress/*.pl $REMOTE_USER@$REMOTE_HOST:./gpload2
    scp -P $REMOTE_PORT ./gpdb_src/src/test/regress/*.pm $REMOTE_USER@$REMOTE_HOST:./gpload2
    scp -P $REMOTE_PORT ./gpdb_src/concourse/scripts/ic_gpdb_remote_windows.bat $REMOTE_USER@$REMOTE_HOST:

    ssh -T -R$PGPORT:127.0.0.1:$PGPORT -L8081:127.0.0.1:8081 -L8082:127.0.0.1:8082 -p $REMOTE_PORT $REMOTE_USER@$REMOTE_HOST "ic_gpdb_remote_windows.bat $PGPORT $VERSION"
}

function _main() {

    if [ -z "$REMOTE_PORT" ]; then
        REMOTE_PORT=22
    fi
    yum install -y jq
    export REMOTE_HOST=`jq -r '."gpdb-clients-ip"' terraform/metadata`

    time install_and_configure_gpdb
    time setup_gpadmin_user
    export WITH_MIRRORS=false
    time make_cluster
    time import_remote_key
    time run_remote_test
}

_main "$@"
