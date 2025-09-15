#!/usr/bin/env bash
set -euo pipefail

# Simple local test runner for the Vector -> ServiceNow forwarder in a Podman pod
# Requirements: podman, base64, curl

# --- Configurable env vars ---
VECTOR_IMAGE="${VECTOR_IMAGE:-docker.io/timberio/vector:0.36.0-debian}"
PORT="${PORT:-9097}"
POD_NAME="${POD_NAME:-vector-servicenow-test}"
CONTAINER_NAME="${CONTAINER_NAME:-vector-servicenow}"
CONFIG_PATH="${CONFIG_PATH:-${HOME}/.local/share/vector-servicenow-test/vector_servicenow_test.toml}"
PAYLOAD_PATH="${PAYLOAD_PATH:-/tmp/alert_test_payload.json}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SERVICENOW_INSTANCE_URL="${SERVICENOW_INSTANCE_URL:-}"
SERVICENOW_USERNAME="${SERVICENOW_USERNAME:-}"
SERVICENOW_PASSWORD="${SERVICENOW_PASSWORD:-}"

if [[ -z "${SERVICENOW_INSTANCE_URL}" || -z "${SERVICENOW_USERNAME}" || -z "${SERVICENOW_PASSWORD}" ]]; then
  echo "Error: Set SERVICENOW_INSTANCE_URL, SERVICENOW_USERNAME, and SERVICENOW_PASSWORD env vars." >&2
  exit 1
fi

INSTANCE_URL_NO_SLASH="${SERVICENOW_INSTANCE_URL%/}"

if ! command -v ansible >/dev/null 2>&1; then
  echo "Error: ansible CLI not found in PATH. Please install Ansible to render the Jinja2 template." >&2
  exit 1
fi

echo "[1/5] Rendering Vector config from Jinja2 template to ${CONFIG_PATH}"
J2_TEMPLATE="${REPO_ROOT}/roles/alertmanager/templates/vector_servicenow.toml.j2"
if [[ ! -f "${J2_TEMPLATE}" ]]; then
  echo "Error: Template not found at ${J2_TEMPLATE}" >&2
  exit 1
fi

# Use ansible to render Jinja2 template with provided vars
mkdir -p "$(dirname "${CONFIG_PATH}")"
ansible -i localhost, localhost -c local \
  -m ansible.builtin.template \
  -a "src=${J2_TEMPLATE} dest=${CONFIG_PATH} mode=0644" \
  -e "servicenow_instance_url=${SERVICENOW_INSTANCE_URL}" \
  -e "servicenow_username=${SERVICENOW_USERNAME}" \
  -e "servicenow_password=${SERVICENOW_PASSWORD}" \
  -e "alertmanager_forwarder_port=${PORT}"

if [[ ! -f "${CONFIG_PATH}" ]]; then
  echo "Error: Failed to render Vector config to ${CONFIG_PATH}. See Ansible output above." >&2
  exit 1
fi

echo "[2/5] Writing sample Alertmanager payload to ${PAYLOAD_PATH}"
cat >"${PAYLOAD_PATH}" <<'JSON'
{
  "body": {
    "alerts": [
      {
        "annotations": {
          "description": "Selinux has been set to permissive on hostX in non-prod environment",
          "summary": "Selinux is disabled on hostX"
        },
        "endsAt": "0001-01-01T00:00:00Z",
        "fingerprint": "53639d9317258d51",
        "generatorURL": "http://monitoring:9090/graph?g0.expr=node_selinux_current_mode%20%3D%3D%200&g0.tab=1",
        "labels": {
          "alertname": "selinux not enforcing",
          "environment": "non-prod",
          "instance": "hostX",
          "job": "node",
          "severity": "warning"
        },
        "startsAt": "2025-09-12T14:08:23.046Z",
        "status": "firing"
      }
    ],
    "commonAnnotations": {
      "description": "Selinux has been set to permissive on hostX in non-prod environment",
      "summary": "Selinux is disabled on hostX"
    },
    "commonLabels": {
      "alertname": "selinux not enforcing",
      "environment": "non-prod",
      "instance": "hostX",
      "job": "node",
      "severity": "warning"
    },
    "externalURL": "http://monitoring:9093",
    "groupKey": "{}:{}",
    "groupLabels": {},
    "receiver": "servicenow_forwarder",
    "status": "firing",
    "version": "4"
  },
  "path": "/",
  "source_type": "http_server",
  "timestamp": "2025-09-12T14:08:38.051070718Z",
  "truncatedAlerts": 0
}
JSON

echo "[3/5] Cleaning up any previous pod/container"
podman rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
podman pod rm -f "${POD_NAME}" >/dev/null 2>&1 || true

echo "[4/5] Starting pod and Vector container"
podman pod create --name "${POD_NAME}" -p ${PORT}:${PORT} >/dev/null
podman run -d --name "${CONTAINER_NAME}" --pod "${POD_NAME}" \
  -v "${CONFIG_PATH}:/etc/vector/vector.toml" \
  "${VECTOR_IMAGE}" -c /etc/vector/vector.toml >/dev/null

echo "Vector is running. Tailing logs for readiness... (5s)"
sleep 5
podman logs --since 5s "${CONTAINER_NAME}" || true

echo "[5/5] Sending sample alert payload to http://127.0.0.1:${PORT}/"
curl -sS -X POST "http://127.0.0.1:${PORT}/" \
  -H 'Content-Type: application/json' \
  --data-binary @"${PAYLOAD_PATH}" | cat

echo
echo "Done. Follow container logs with: podman logs -f ${CONTAINER_NAME}"

