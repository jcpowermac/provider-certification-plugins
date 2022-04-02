#!/bin/sh

#
# openshift-tests-partner-cert runner
#

#set -x
set -o pipefail
set -o nounset
# set -o errexit

os_log_info "[executor] Starting..."

#export KUBECONFIG=/tmp/kubeconfig

suite="${E2E_SUITE:-kubernetes/conformance}"
#ca_path="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
#sa_token="/var/run/secrets/kubernetes.io/serviceaccount/token"

os_log_info "[executor] Checking if credentials are present..."
test ! -f "${SA_CA_PATH}" || os_log_info "[executor] secret not found=${SA_CA_PATH}"
test ! -f "${SA_TOKEN_PATH}" || os_log_info "[executor] secret not found=${SA_TOKEN_PATH}"

#
# openshift login
#

os_log_info "[executor] Login to OpenShift cluster locally..."
oc login https://172.30.0.1:443 \
    --token="$(cat ${SA_TOKEN_PATH})" \
    --certificate-authority="${SA_CA_PATH}" || true;

#
# Executor options
#
os_log_info "[executor] Executor started. Choosing execution type based on environment sets."

# To run custom tests, set the environment CUSTOM_TEST_FILE on plugin definition.
# To generate the test file, use the parse-test.py.
if [[ ! -z ${CERT_TEST_FILE:-} ]]; then
    os_log_info "Running openshift-tests for custom tests [${CERT_TEST_FILE}]..."
    if [[ -s ${CERT_TEST_FILE} ]]; then
        openshift-tests run \
            --junit-dir ${RESULTS_DIR} \
            -f ${CERT_TEST_FILE} \
            | tee -a "${RESULTS_PIPE}" || true
        os_log_info "openshift-tests finished"
    else
        os_log_info "the file provided has no tests. Sending progress and finish executor...";
        echo "(0/0/0)" > ${RESULTS_PIPE}
    fi

# reusing script to parser jobs.
# ToDo: keep more simple in basic filters. Example:
# $ openshift-tests run --dry-run all |grep '\[sig-storage\]' |openshift-tests run -f -
elif [[ ! -z ${CUSTOM_TEST_FILTER_SIG:-} ]]; then
    os_log_info "Generating tests for SIG [${CUSTOM_TEST_FILTER_SIG}]..."
    mkdir tmp/
    ./parse-tests.py \
        --filter-suites all \
        --filter-key sig \
        --filter-value "${CUSTOM_TEST_FILTER_SIG}"

    os_log_info "#executor>Running"
    openshift-tests run \
        --junit-dir ${RESULTS_DIR} \
        -f ./tmp/openshift-e2e-suites.txt \
        | tee -a "${RESULTS_PIPE}" || true

# Filter by string pattern from 'all' tests
elif [[ ! -z ${CUSTOM_TEST_FILTER_STR:-} ]]; then
    os_log_info "#executor>Generating a filter [${CUSTOM_TEST_FILTER_STR}]..."
    openshift-tests run --dry-run all \
        | grep "${CUSTOM_TEST_FILTER_STR}" \
        | openshift-tests run -f - \
        | tee -a "${RESULTS_PIPE}" || true

# Default execution - running default suite
else
    os_log_info "#executor>Running default execution for openshift-tests suite [${suite}]..."
    openshift-tests run \
        --junit-dir ${RESULTS_DIR} \
        ${suite} \
        | tee -a "${RESULTS_PIPE}" || true
fi

os_log_info "Plugin executor finished. Result[$?]";
