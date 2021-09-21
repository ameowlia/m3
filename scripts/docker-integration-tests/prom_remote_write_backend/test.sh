#!/usr/bin/env bash

set -xe

M3_PATH=${M3_PATH:-$GOPATH/src/github.com/m3db/m3}
TESTDIR="$M3_PATH"/scripts/docker-integration-tests/
source "$TESTDIR"/common.sh
source "$TESTDIR"/prom_remote_write_backend/tests.sh
REVISION=$(git rev-parse HEAD)
COMPOSE_FILE="$TESTDIR"/prom_remote_write_backend/docker-compose.yml
# quay.io/m3db/prometheus_remote_client_golang @ v0.4.3
PROMREMOTECLI_IMAGE=quay.io/m3db/prometheus_remote_client_golang:v0.4.3
JQ_IMAGE=realguess/jq:1.4@sha256:300c5d9fb1d74154248d155ce182e207cf6630acccbaadd0168e18b15bfaa786
METRIC_NAME_TEST_RESTRICT_WRITE=bar_metric
QUERY_LIMIT_MESSAGE="${QUERY_LIMIT_MESSAGE:-query exceeded limit}"
RUN_GLOBAL_LIMIT_TEST="${RUN_GLOBAL_LIMIT_TEST:-true}"
QUERY_TIMEOUT_STATUS_CODE="${QUERY_TIMEOUT_STATUS_CODE:-504}"
export REVISION

echo "Pull containers required for test"
docker pull $PROMREMOTECLI_IMAGE
docker pull $JQ_IMAGE

echo "Run ETCD"
docker-compose -f ${COMPOSE_FILE} up -d etcd01

echo "Run Coordinator in Admin mode"
docker-compose -f ${COMPOSE_FILE} up -d coordinatoradmin

test_readiness "0.0.0.0:7201"

echo "Initializing aggregator topology"
curl -vvvsSf -X POST -H "Cluster-Environment-Name: override_test_env" localhost:7201/api/v1/services/m3aggregator/placement/init -d '{
    "num_shards": 64,
    "replication_factor": 2,
    "instances": [
        {
            "id": "m3aggregator01",
            "isolation_group": "availability-zone-a",
            "zone": "embedded",
            "weight": 100,
            "endpoint": "aggregator01:6000",
            "hostname": "aggregator01",
            "port": 6000
        },
        {
            "id": "m3aggregator02",
            "isolation_group": "availability-zone-b",
            "zone": "embedded",
            "weight": 100,
            "endpoint": "aggregator02:6000",
            "hostname": "aggregator02",
            "port": 6000
        }
    ]
}'

echo "Initializing m3msg inbound topic for m3aggregator ingestion from m3coordinators"
curl -vvvsSf -X POST -H "Topic-Name: aggregator_ingest" -H "Cluster-Environment-Name: override_test_env" localhost:7201/api/v1/topic/init -d '{
    "numberOfShards": 64
}'

# Do this after placement and topic for m3aggregator is created.
echo "Adding m3aggregator as a consumer to the aggregator ingest topic"
curl -vvvsSf -X POST -H "Topic-Name: aggregator_ingest" -H "Cluster-Environment-Name: override_test_env" localhost:7201/api/v1/topic -d '{
  "consumerService": {
    "serviceId": {
      "name": "m3aggregator",
      "environment": "override_test_env",
      "zone": "embedded"
    },
    "consumptionType": "REPLICATED",
    "messageTtlNanos": "600000000000"
  }
}' # msgs will be discarded after 600000000000ns = 10mins

# TODO paziuret ar nereik

# Do this after placement for m3coordinator is created.
echo "Initializing m3msg outbound topic for m3coordinator ingestion from m3aggregators"
curl -vvvsSf -X POST -H "Topic-Name: aggregated_metrics" -H "Cluster-Environment-Name: override_test_env" 0.0.0.0:7201/api/v1/topic/init -d '{
    "numberOfShards": 64
}'

echo "Adding m3coordinator as a consumer to the aggregator publish topic"
curl -vvvsSf -X POST -H "Topic-Name: aggregated_metrics" -H "Cluster-Environment-Name: override_test_env" 0.0.0.0:7201/api/v1/topic -d '{
  "consumerService": {
    "serviceId": {
      "name": "m3coordinator",
      "environment": "default_env",
      "zone": "embedded"
    },
    "consumptionType": "SHARED",
    "messageTtlNanos": "600000000000"
  }
}' # msgs will be discarded after 600000000000ns = 10mins

echo "Run M3 containers"
docker-compose -f ${COMPOSE_FILE} up -d coordinator01
docker-compose -f ${COMPOSE_FILE} up -d aggregator01
docker-compose -f ${COMPOSE_FILE} up -d aggregator02

test_readiness "0.0.0.0:7202"

echo "Start Prometheus containers"
docker-compose -f ${COMPOSE_FILE} up -d prometheus01

TEST_SUCCESS=false

function defer {
  if [[ "$TEST_SUCCESS" != "true" ]]; then
    echo "Test failure, printing docker-compose logs"
    docker-compose -f ${COMPOSE_FILE} logs
  fi

  docker-compose -f ${COMPOSE_FILE} down || echo "unable to shutdown containers" # CI fails to stop all containers sometimes
}
trap defer EXIT

echo "Running write tests"
test_prometheus_remote_write_multi_namespaces

TEST_SUCCESS=true
