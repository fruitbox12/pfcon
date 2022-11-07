#!/bin/bash
#
# NAME
#
#   deploy.sh
#
# SYNPOSIS
#
#   deploy.sh                   [-h]
#                               [-O <swarm|kubernetes>] \
#                               [-N <namespace>]        \
#                               [-T <host|nfs>]         \
#                               [-P <nfsServerIp>]      \
#                               [-S <storeBase>]        \
#                               [up|down]
#
# DESC
#
#   'deploy.sh' script will depending on the argument deploy the pfcon set
#    of services in production or tear down the system.
#
# TYPICAL CASES:
#
#   Deploy pfcon services into a Swarm cluster:
#
#       deploy.sh up
#
#
#   Deploy pfcon services into a Kubernetes cluster:
#
#       deploy.sh -O kubernetes up
#
# ARGS
#
#
#   -h
#
#       Optional print usage help.
#
#   -O <swarm|kubernetes>
#
#       Explicitly set the orchestrator. Default is swarm.
#
#   -N <namespace>
#
#       Explicitly set the kubernetes namespace to <namespace>. Default is chris.
#       Not used for swarm.
#
#   -T <host|nfs>
#
#       Explicitly set the storage type for the STOREBASE dir. Default is host.
#       Note: The nfs storage type is not implemented for swarm orchestrator yet.
#
#   -P <nfsServerIp>
#
#       Set the IP address of the NFS server. Required when storage type is set to 'nfs'.
#       Not used for 'host' storage type.
#
#   -S <storeBase>
#
#       Explicitly set the STOREBASE dir to <storeBase>. This is the remote ChRIS
#       filesystem where pfcon and plugins share data (usually externally mounted NFS).
#
#   [up|down] (optional, default = 'up')
#
#       Denotes whether to fire up or tear down the production set of services.
#
#


source ./decorate.sh
source ./cparse.sh

declare -i STEP=0
IDRAC="127.0.0.1"
NAMESPACE="newton-idracs"
HERE=$(pwd)

print_usage () {
    echo "Usage: ./deploy.sh [-h] [-O <ip|http://127.0.0.1>] [-N <namespace>]"
    exit 1
}

while getopts ":hO:N:" opt; do
    case $opt in
        h) print_usage
           ;;
        O) IDRAC=$OPTARG
           if ! [[ "$IDRAC" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
              echo "Invalid value for IDRAC URL -- O"
              print_usage
           fi
           ;;
        N) NAMESPACE=$OPTARG
           ;;
       
        \?) echo "Invalid option -- $OPTARG"
            print_usage
            ;;
        :) echo "Option requires an argument -- $OPTARG"
           print_usage
           ;;
    esac
done
shift $(($OPTIND - 1))


COMMAND=deploy
if (( $# == 1 )) ; then
    COMMAND=$1
    if ! [[ "$COMMAND" =~ ^(up|down)$ ]]; then
        echo "Invalid value $COMMAND"
        print_usage
    fi
fi

title -d 1 "Setting global exports..."
    echo -e "ORCHESTRATOR=$ORCHESTRATOR"                          | ./boxes.sh
    echo -e "exporting STORAGE_TYPE=$STORAGE_TYPE"                | ./boxes.sh
    export STORAGE_TYPE=$STORAGE_TYPE
    if [[ $STORAGE_TYPE == nfs ]]; then
        echo -e "exporting NFS_SERVER=$NFS_SERVER"                | ./boxes.sh
        export NFS_SERVER=$NFS_SERVER
    fi
    echo -e "exporting STOREBASE=$STOREBASE"                      | ./boxes.sh
    export STOREBASE=$STOREBASE
    if [[ $ORCHESTRATOR == kubernetes ]]; then
        echo -e "exporting NAMESPACE=$NAMESPACE"                  | ./boxes.sh
        export NAMESPACE=$NAMESPACE
    fi
windowBottom

if [[ "$COMMAND" == 'deploy' ]]; then

    title -d 1 "Deploying new pods scanning $IDRAC"
    if [[ $IDRAC == swarm ]]; then
        echo "docker stack deploy -c swarm/prod/docker-compose.yml pfcon_stack"   | ./boxes.sh ${LightCyan}
        docker stack deploy -c swarm/prod/docker-compose.yml pfcon_stack
    elif [[ $ORCHESTRATOR == kubernetes ]]; then
        echo "kubectl create namespace $NAMESPACE"   | ./boxes.sh ${LightCyan}
        namespace=$(kubectl get namespaces $NAMESPACE --no-headers -o custom-columns=:metadata.name 2> /dev/null)
        if [ -z "$namespace" ]; then
            kubectl create namespace $NAMESPACE
        else
            echo "$NAMESPACE namespace already exists, skipping creation"
        fi
        if [[ $STORAGE_TYPE == host ]]; then
            echo "kubectl kustomize kubernetes/prod/overlays/host | envsubst | kubectl apply -f -"  | ./boxes.sh ${LightCyan}
            kubectl kustomize kubernetes/prod/overlays/host | envsubst | kubectl apply -f -
        else
            echo "kubectl kustomize kubernetes/prod/overlays/nfs | envsubst | kubectl apply -f -"  | ./boxes.sh ${LightCyan}
            kubectl kustomize kubernetes/prod/overlays/nfs | envsubst | kubectl apply -f -
        fi
    fi
    windowBottom
fi

if [[ "$COMMAND" == 'down' ]]; then

    title -d 1 "Destroying pfcon containerized prod environment on $ORCHESTRATOR"
    if [[ $ORCHESTRATOR == swarm ]]; then
        echo "docker stack rm pfcon_stack"                               | ./boxes.sh ${LightCyan}
        docker stack rm pfcon_stack
    elif [[ $ORCHESTRATOR == kubernetes ]]; then
        if [[ $STORAGE_TYPE == host ]]; then
            echo "kubectl kustomize kubernetes/prod/overlays/host | envsubst | kubectl delete -f -"  | ./boxes.sh ${LightCyan}
            kubectl kustomize kubernetes/prod/overlays/host | envsubst | kubectl delete -f -
        else
            echo "kubectl kustomize kubernetes/prod/overlays/nfs | envsubst | kubectl delete -f -"  | ./boxes.sh ${LightCyan}
            kubectl kustomize kubernetes/prod/overlays/nfs | envsubst | kubectl delete -f -
        fi
    fi
    windowBottom
fi
