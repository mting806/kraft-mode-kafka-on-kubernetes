#!/bin/bash
set -e

POD_NAME="$HOSTNAME"
NODE_ID="${POD_NAME##*-}"
STATEFULSET_NAME="${POD_NAME%-*}"

ADVERTISED_LISTENERS="PLAINTEXT://${POD_NAME}.${SERVICE}.${NAMESPACE}.svc.cluster.local:9092"
LISTENERS="PLAINTEXT://:9092,CONTROLLER://:9093"

CONTROLLER_QUORUM_VOTERS=""
for i in $(seq 0 $((REPLICAS - 1))); do
  CONTROLLER_QUORUM_VOTERS+="${i}@${STATEFULSET_NAME}-${i}.${SERVICE}.${NAMESPACE}.svc.cluster.local:9093,"
done
CONTROLLER_QUORUM_VOTERS="${CONTROLLER_QUORUM_VOTERS::-1}"

mkdir -p "$SHARE_DIR/$NODE_ID"

CLUSTER_ID_FILE="$SHARE_DIR/cluster_id"
if [[ "$NODE_ID" == "0" && ! -f "$CLUSTER_ID_FILE" ]]; then
  CLUSTER_ID=$(kafka-storage.sh random-uuid)
  echo "$CLUSTER_ID" > "$CLUSTER_ID_FILE"
else
  while [[ ! -f "$CLUSTER_ID_FILE" ]]; do sleep 1; done
  CLUSTER_ID=$(cat "$CLUSTER_ID_FILE")
fi

CONFIG_FILE="/opt/kafka/config/kraft/server.properties"
sed -e "s|^node.id=.*|node.id=$NODE_ID|" \
    -e "s|^controller.quorum.voters=.*|controller.quorum.voters=$CONTROLLER_QUORUM_VOTERS|" \
    -e "s|^listeners=.*|listeners=$LISTENERS|" \
    -e "s|^advertised.listeners=.*|advertised.listeners=$ADVERTISED_LISTENERS|" \
    -e "s|^log.dirs=.*|log.dirs=$SHARE_DIR/$NODE_ID|" \
    "$CONFIG_FILE" > "$CONFIG_FILE.tmp" \
    && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

LOG_DIR="$SHARE_DIR/$NODE_ID"
if [[ ! -f "$LOG_DIR/meta.properties" ]]; then
  kafka-storage.sh format -t "$CLUSTER_ID" -c "$CONFIG_FILE" --ignore-formatted
fi

exec kafka-server-start.sh "$CONFIG_FILE"
