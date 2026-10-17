#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"
TEMPLATE="${REPO_ROOT}/clusters/oci-prod/secret-stores/clustersecretstore-oci-vault.yaml.tmpl"

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

if [[ -z "${OCI_REGION:-}" ]]; then
  echo "OCI_REGION is required" >&2
  exit 1
fi

if [[ -z "${OCI_VAULT_OCID:-}" ]]; then
  echo "OCI_VAULT_OCID is required" >&2
  exit 1
fi

OCI_KUBECONFIG="${OCI_KUBECONFIG:-${HOME}/.kube/oci-prod.yaml}"

if [[ ! -f "${OCI_KUBECONFIG}" ]]; then
  echo "OCI kubeconfig not found: ${OCI_KUBECONFIG}" >&2
  echo "Set OCI_KUBECONFIG to the OCI k3s kubeconfig path." >&2
  exit 1
fi

TARGET_CONTEXT="$(kubectl --kubeconfig "${OCI_KUBECONFIG}" config current-context)"

if [[ -z "${TARGET_CONTEXT}" ]]; then
  echo "No current context in OCI kubeconfig: ${OCI_KUBECONFIG}" >&2
  exit 1
fi

echo "Applying ClusterSecretStore to context '${TARGET_CONTEXT}' using ${OCI_KUBECONFIG}"
envsubst '${OCI_REGION} ${OCI_VAULT_OCID}' < "${TEMPLATE}" \
  | kubectl --kubeconfig "${OCI_KUBECONFIG}" apply -f -
