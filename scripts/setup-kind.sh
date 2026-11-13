#!/usr/bin/env bash
set -euo pipefail
kind create cluster --name secure-release --config deploy/kind.yaml --wait 120s
helm repo add sigstore https://sigstore.github.io/helm-charts
helm repo update sigstore
helm upgrade --install policy-controller sigstore/policy-controller \
  --version 0.10.8 --namespace cosign-system --create-namespace \
  -f deploy/controller-values.yaml --wait --timeout 5m
kubectl apply -f deploy/release-policy.yaml
kubectl wait --for=condition=Ready clusterimagepolicy/trusted-release --timeout=120s
kubectl apply -f deploy/namespace.yaml
