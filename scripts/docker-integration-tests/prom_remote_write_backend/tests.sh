#!/usr/bin/env bash

set -xe

source "$M3_PATH"/scripts/docker-integration-tests/common.sh

function prometheus_remote_write {
  local metric_name=$1
  local datapoint_timestamp=$2
  local datapoint_value=$3
  local expect_success=$4
  local expect_success_err=$5
  local expect_status=$6
  local expect_status_err=$7
  local metrics_type=$8
  local metrics_storage_policy=$9
  local map_tags_header=${10}

  local optional_tags=""
  for i in $(seq 0 10); do
    local optional_tag_name=$(eval "echo \$TAG_NAME_$i")
    local optional_tag_value=$(eval "echo \$TAG_VALUE_$i")
    if [[ "$optional_tag_name" != "" ]] || [[ "$optional_tag_value" != "" ]]; then
      optional_tags="$optional_tags -t ${optional_tag_name}:${optional_tag_value}"
    fi
  done

  network_name="prom_remote_write_backend_backend"
  network=$(docker network ls | fgrep $network_name | tr -s ' ' | cut -f 1 -d ' ' | tail -n 1)
  out=$((docker run -it --rm --network $network           \
    $PROMREMOTECLI_IMAGE                                  \
    -u http://coordinator01:7201/api/v1/prom/remote/write \
    -t __name__:${metric_name} ${optional_tags}           \
    -h "M3-Metrics-Type: ${metrics_type}"                 \
    -h "M3-Storage-Policy: ${metrics_storage_policy}"     \
    -h "M3-Map-Tags-JSON: ${map_tags_header}"          \
    -d ${datapoint_timestamp},${datapoint_value} | grep -v promremotecli_log) || true)
  success=$(echo $out | grep -v promremotecli_log | docker run --rm -i $JQ_IMAGE jq .success)
  status=$(echo $out | grep -v promremotecli_log | docker run --rm -i $JQ_IMAGE jq .statusCode)
  if [[ "$success" != "$expect_success" ]]; then
    echo $expect_success_err
    return 1
  fi
  if [[ "$status" != "$expect_status" ]]; then
    echo "${expect_status_err}: actual=${status}"
    return 1
  fi
  echo "Returned success=${success}, status=${status} as expected"
  return 0
}


function test_readiness {
  host=$1
  # Check readiness probe eventually succeeds
  echo "Check readiness probe eventually succeeds"
  ATTEMPTS=50 TIMEOUT=2 MAX_TIMEOUT=4 retry_with_backoff  \
    "[[ \$(curl --write-out \"%{http_code}\" --silent --output /dev/null $host/ready) -eq \"200\" ]]"
}

function test_prometheus_remote_write_multi_namespaces {
  now=$(date +"%s")
  now_truncate_by=$(( $now % 5 ))
  now_truncated=$(( $now - $now_truncate_by ))

  prometheus_remote_write \
    foo_metric $now_truncated 42.42 \
    true "Expected request to succeed" \
    200 "Expected request to return status code 200"

  # Make sure we're proxying writes to the unaggregated namespace
  echo "Wait until data begins being written to remote storage for the unaggregated namespace"
  ATTEMPTS=50 TIMEOUT=2 MAX_TIMEOUT=4 retry_with_backoff  \
    '[[ $(curl -sSf 0.0.0.0:9090/api/v1/query?query=database_write_tagged_success\\{namespace=\"unagg\"\\} | jq -r .data.result[0].value[1]) -gt 0 ]]'

  # Make sure we're proxying writes to the aggregated namespace
  echo "Wait until data begins being written to remote storage for the aggregated namespace"
  ATTEMPTS=50 TIMEOUT=2 MAX_TIMEOUT=4 retry_with_backoff  \
    '[[ $(curl -sSf 0.0.0.0:9090/api/v1/query?query=database_write_tagged_success\\{namespace=\"agg\"\\} | jq -r .data.result[0].value[1]) -gt 0 ]]'
}