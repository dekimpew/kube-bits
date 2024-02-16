#!/bin/bash
set -o pipefail

# Setting some colors for readability
#####################################
GREEN='\033[0;32m'
RED='\033[0;31m'
WHITE='\033[0;37m'
BLUE='\033[0;34m'  

# Welcome banner!
#################

echo ""
echo "Kubernetes basic healthcheck script"
echo "###################################"
echo ""
echo ""

# Checking the kubeconfig context
#################################
if [ -z $1 ]
then
    echo -e "INFO: no kubeconfig file provided, using current environment context"
    if [ $(kubectl config current-context) ]
    then
        echo -e "${BLUE}INFO:${WHITE} Current context is $(kubectl config current-context)"
        echo ""
        kctl="kubectl"
    else
        echo -e "${RED}WARNING:${WHITE} no kubecontext found!"
        echo ""
        exit 1
    fi
    
else
    kubeconfig=$1
    kctl="kubectl --kubeconfig=$1"
    echo -e "${BLUE}INFO:${WHITE} Selected kubeconfig file is" $1
    echo ""
fi

# Healthcheck functions
#######################

function cluster_check ()
{
    # check commands
    cluster_apicheck=$($kctl get --raw='/livez/ping')
    cluster_etcdcheck=$($kctl get --raw='/livez/etcd')
    cluster_etcdpod=$($kctl get pods -A | grep etcd | awk '{print $2}' | head -n1)
    cluster_etcdpeercmd="etcdctl member list --key=/etc/kubernetes/pki/etcd/server.key --cert=/etc/kubernetes/pki/etcd/server.crt --cacert=/etc/kubernetes/pki/etcd/ca.crt"
    
    # Produce cluster-info
    $kctl cluster-info | head -n2

    # Check cluster api-server
    if [ $cluster_apicheck == "ok" ]
    then
        echo -e "${GREEN}OK:${WHITE} API server is running"
    else
        echo -e "${RED}WARNING:${WHITE} API server is faulty"
    fi
    sleep 1

    # Check cluster etcd server
    if [[ $cluster_etcdcheck == "ok" ]]
    then
        echo -e "${GREEN}OK:${WHITE} etcd cluster is running"
    else
        echo -e "${RED}WARNING:${WHITE} etcd is faulty"
    fi

    # Check cluster etcd members
    if [ -z $cluster_etcdpod ]
    then
        echo -e "${BLUE}INFO:${WHITE} No etcd pods available to verify peers"
    else
        echo ""
        echo -e "${BLUE}INFO:${WHITE} Active etcd cluster peers:"
        $kctl exec -n kube-system -it $cluster_etcdpod -- $cluster_etcdpeercmd | awk '{print "    "$0}'
    fi

    echo ""

}

function node_check ()
{
    # Check commands
    node_notready=$($kctl get nodes | grep NotReady | awk '{print $1}')
    node_scheddisabled=$($kctl get nodes | grep SchedulingDisabled | awk '{print $1}')
    node_top=$($kctl top nodes)

    # Check for NotReady nodes
    if [ -z $node_status ]
    then
        echo -e "${GREEN}OK:${WHITE} No NotReady nodes found"  
    else
        echo -e "${RED}WARNING:${WHITE} NotReady nodes found:"
        echo "$node_notready"
    fi
    sleep 1
    # Check for SchedulingDisabled nodes
    if [ -z $node_scheddisabled ]
    then
        echo -e "${GREEN}OK:${WHITE} No SchedulingDisabled nodes found"  
    else
        echo -e "${RED}WARNING:${WHITE} SchedulingDisabled nodes found:"
        echo "$node_scheddisabled" | awk '{print "    "$0}'
    fi
    sleep 1
    # Check for node CPU/mem metrics
    echo ""
    echo -e "${BLUE}INFO:${WHITE} Listing node CPU/memory metrics"
    echo "$node_top" | awk '{print "    "$0}'
    echo ""
    sleep 1
    # Check for node conditions
    echo -e "${BLUE}INFO:${WHITE} Listing node conditions:"
    $kctl get nodes | awk '{print $1}' | tail -n +2 | while read node ;
    do  
        echo -e ${GREEN}$node${WHITE};
        $kctl describe node $node | grep -A 6 "Conditions:" | tail -n +2;
    done
    echo ""
}

function pod_check ()
{
    # Check commands
    podunavailable=$($kctl get pods -A | grep -v Running | grep -v Completed | tail -n +2)

    # Check for pods that are not Running or Completed
    if [ -z $podunavailable ]
    then
        echo -e "${GREEN}OK:${WHITE} All pods in running or completed state"
        echo ""
    else
        echo "${RED}WARNING:${WHITE} Pods found that are not Running or Completed:"
        echo "$podunavailable"
        echo ""
    fi

    # Check for pod restarts
    echo -e "${BLUE}INFO:${WHITE} Listing pods with 5 or more restarts: "
    $kctl get pods -A | tail -n +2 | while read pod ; 
    do 
        if [[ $(echo $pod | awk '{print $5}') > 5 ]]
        then
            echo $pod | awk '{print "Pod \033[31m" $2 "\033[37m in namespace \033[31m" $1 "\033[37m has \033[31m" $5 "\033[37m restarts, last one \033[31m" $6 " " $7 "\033[37m"}'; 
        fi
    done
}


# Main
######

echo "Checking cluster status:"
echo "------------------------"
cluster_check

echo "Checking node status:"
echo "---------------------"
node_check

echo "Checking pod status:"
echo "--------------------"
pod_check
