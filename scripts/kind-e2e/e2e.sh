#!/usr/bin/env bash

## Process command line flags ##

source /usr/share/shflags/shflags
FLAGS "$@" || exit $?
eval set -- "${FLAGS_ARGV}"

set -em

source ${SCRIPTS_DIR}/lib/debug_functions
source ${SCRIPTS_DIR}/lib/version
source ${SCRIPTS_DIR}/lib/utils

### Functions ###

function deploy_broker {
    kubectl apply -f ${DAPPER_SOURCE}/test/e2e/deploy/broker.yaml
}

function deploy_crds {
    kubectl apply -f ${DAPPER_SOURCE}/test/e2e/deploy/crds.yaml
}

function test_with_e2e_tests {
    set -o pipefail 

    cd ${DAPPER_SOURCE}/test/e2e

    go test -v -args -v=2 -logtostderr=true -ginkgo.v -ginkgo.randomizeAllSpecs \
        -dp-context cluster1 -dp-context cluster2 \
        -ginkgo.reportFile ${DAPPER_OUTPUT}/e2e-junit.xml 2>&1 | \
        tee ${DAPPER_OUTPUT}/e2e-tests.log
}

function cleanup {
    "${SCRIPTS_DIR}"/cleanup.sh
}

### Main ###

declare_kubeconfig

with_context cluster1 deploy_crds
with_context cluster2 deploy_crds
with_context cluster2 deploy_broker


export BROKER_K8S_REMOTENAMESPACE=broker

export BROKER_K8S_APISERVER=$(kubectl --context=cluster2 -n default get endpoints kubernetes -o jsonpath="{.subsets[0].addresses[0].ip}:{.subsets[0].ports[?(@.name=='https')].port}")

export BROKER_K8S_CA=$(kubectl --context=cluster2 -n ${BROKER_K8S_REMOTENAMESPACE} get secrets -o jsonpath="{.items[?(@.metadata.annotations['kubernetes\.io/service-account\.name']=='${BROKER_K8S_REMOTENAMESPACE}-client')].data['ca\.crt']}")

export BROKER_K8S_APISERVERTOKEN=$(kubectl --context=cluster2 -n ${BROKER_K8S_REMOTENAMESPACE} get secrets -o jsonpath="{.items[?(@.metadata.annotations['kubernetes\.io/service-account\.name']=='${BROKER_K8S_REMOTENAMESPACE}-client')].data.token}"|base64 --decode)

test_with_e2e_tests

cat << EOM
Your 3 virtual clusters are deployed and working properly and can be accessed with:

export KUBECONFIG=\$(echo \$(git rev-parse --show-toplevel)/output/kubeconfigs/kind-config-cluster{1..3} | sed 's/ /:/g')

$ kubectl config use-context cluster1 # or cluster2, cluster3..

To clean evertyhing up, just run: make cleanup
EOM
