#!/usr/bin/env bash
set -euo pipefail
: "${UNSIGNED_IMAGE:?Set project-owned unsigned digest reference}"
: "${UNAPPROVED_IMAGE:?Set project-owned wrong-workflow digest reference}"
mkdir -p evidence
approved=ghcr.io/arhumamjad07/secure-release-pipeline@sha256:48f8e715474cc904933cd36eb3ac7ef16c91ddffb2f16a779e73f094ee9d4a78
# Pod CREATE (server dry run) exercises admission without conflating it with image pull.
probe() {
  local name=$1 image=$2
  cat <<EOF | kubectl create --dry-run=server -f -
apiVersion: v1
kind: Pod
metadata:
  name: $name
  namespace: secure-app
spec:
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: api
      image: $image
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: [ALL]
EOF
}
probe approved "$approved" 2>&1 | tee evidence/approved.txt
reject() {
  local name=$1 image=$2
  if probe "$name" "$image" > "evidence/$name.txt" 2>&1; then
    echo "ERROR: $name was admitted"; exit 1
  fi
  cat "evidence/$name.txt"
  # Infrastructure failures and Pod Security rejections must never count as success.
  grep -Eq 'admission webhook.*(sigstore|image-policy).*denied|validation failed.*(policy|authority)|no matching policies' "evidence/$name.txt"
}
reject unsigned "$UNSIGNED_IMAGE"
reject unapproved-workflow "$UNAPPROVED_IMAGE"
reject outside-policy ghcr.io/sigstore/policy-controller/policy-controller@sha256:0bcd60beb93f4427c29cf3a669743caf58490e98ded4380c33c09f092734a6ab
helm upgrade --install secure-api charts/secure-api -n secure-app --wait --timeout 180s
kubectl -n secure-app rollout status deployment/secure-api --timeout=120s
kubectl -n secure-app get pods -o json > evidence/running-pods.json
kubectl -n secure-app port-forward deployment/secure-api 18000:8000 > /tmp/secure-forward.log 2>&1 &
forward_pid=$!
trap 'kill "$forward_pid" 2>/dev/null || true' EXIT
for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:18000/health > evidence/health.json; then break; fi
  sleep 1
done
curl -fsS http://127.0.0.1:18000/version > evidence/version.json
python3 - <<'CHECK'
import json
assert json.load(open('evidence/health.json')) == {'status':'ok'}
assert json.load(open('evidence/version.json')) == {'version':'efeeea72b970b20166e4e65d1322cfa3c12462df'}
pods=json.load(open('evidence/running-pods.json'))['items']
assert len(pods)==1
assert pods[0]['spec']['containers'][0]['image']=='ghcr.io/arhumamjad07/secure-release-pipeline@sha256:48f8e715474cc904933cd36eb3ac7ef16c91ddffb2f16a779e73f094ee9d4a78'
print('Approved digest ready; health/version passed; three negative cases denied.')
CHECK
