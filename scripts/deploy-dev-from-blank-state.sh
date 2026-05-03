#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${1:-$ROOT_DIR/.env/dev-deploy.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE"
  echo "Copy $ROOT_DIR/.env/dev-deploy.env.example to .env/dev-deploy.env and update it."
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

: "${AWS_PROFILE:?AWS_PROFILE is required}"
: "${AWS_REGION:?AWS_REGION is required}"
: "${AWS_ACCOUNT_ID:?AWS_ACCOUNT_ID is required}"
: "${ENVIRONMENT:?ENVIRONMENT is required}"
: "${CLUSTER_NAME:?CLUSTER_NAME is required}"
: "${TF_ENV_DIR:?TF_ENV_DIR is required}"
: "${TF_VARS_FILE:?TF_VARS_FILE is required}"
: "${TF_BACKEND_BUCKET:?TF_BACKEND_BUCKET is required}"
: "${TF_BACKEND_KEY:?TF_BACKEND_KEY is required}"
: "${DOCKER_COMPOSE_FILE:?DOCKER_COMPOSE_FILE is required}"
: "${API_GATEWAY_TAG:?API_GATEWAY_TAG is required}"
: "${DASHBOARD_API_TAG:?DASHBOARD_API_TAG is required}"
: "${DEFAULT_APP_TAG:?DEFAULT_APP_TAG is required}"

export AWS_PROFILE AWS_REGION
export XDG_RUNTIME_DIR="/tmp/docker-rootless-$UID"
export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock"

services=(
  api-gateway
  dashboard-api
  inventory-service
  notification-service
  order-service
  payment-service
  scheduler
  shipping-service
  worker
)

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1"
    exit 1
  }
}

ensure_prereqs() {
  require_cmd aws
  require_cmd terraform
  require_cmd kubectl
  require_cmd helm
  require_cmd docker
}

ensure_backend_bucket() {
  if aws s3api head-bucket --bucket "$TF_BACKEND_BUCKET" >/dev/null 2>&1; then
    echo "Backend bucket already exists: $TF_BACKEND_BUCKET"
    return
  fi

  echo "Creating backend bucket: $TF_BACKEND_BUCKET"
  aws s3api create-bucket \
    --bucket "$TF_BACKEND_BUCKET" \
    --region "$AWS_REGION" \
    --create-bucket-configuration "LocationConstraint=$AWS_REGION"

  aws s3api put-bucket-versioning \
    --bucket "$TF_BACKEND_BUCKET" \
    --versioning-configuration Status=Enabled

  aws s3api put-bucket-encryption \
    --bucket "$TF_BACKEND_BUCKET" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
}

terraform_init() {
  terraform -chdir="$ROOT_DIR/$TF_ENV_DIR" init -reconfigure \
    -backend-config="bucket=$TF_BACKEND_BUCKET" \
    -backend-config="key=$TF_BACKEND_KEY" \
    -backend-config="region=$AWS_REGION" \
    -backend-config="encrypt=${TF_BACKEND_ENCRYPT:-true}" \
    -backend-config="use_lockfile=${TF_BACKEND_USE_LOCKFILE:-true}"
}

terraform_plan_apply() {
  terraform -chdir="$ROOT_DIR/$TF_ENV_DIR" plan -var-file="$TF_VARS_FILE"

  if [[ "${RUN_TERRAFORM_APPLY:-false}" == "true" ]]; then
    terraform -chdir="$ROOT_DIR/$TF_ENV_DIR" apply -var-file="$TF_VARS_FILE" -auto-approve
  else
    echo "Skipping terraform apply because RUN_TERRAFORM_APPLY=false"
  fi
}

ensure_kubeconfig() {
  aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null
}

ensure_ecr_login() {
  aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
}

build_and_push_images() {
  docker compose -f "$ROOT_DIR/$DOCKER_COMPOSE_FILE" build "${services[@]}"

  for service in "${services[@]}"; do
    local_image="eks-microservices-$service"
    remote_repo="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/${ENVIRONMENT}-${service}"
    tag="$DEFAULT_APP_TAG"

    case "$service" in
      api-gateway)
        tag="$API_GATEWAY_TAG"
        ;;
      dashboard-api)
        tag="$DASHBOARD_API_TAG"
        ;;
    esac

    docker tag "${local_image}:latest" "${remote_repo}:latest"
    docker push "${remote_repo}:latest"

    if [[ "$tag" != "latest" ]]; then
      docker tag "${local_image}:latest" "${remote_repo}:${tag}"
      docker push "${remote_repo}:${tag}"
    fi
  done
}

deploy_helm_stack() {
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
  helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
  helm repo update >/dev/null

  kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl create namespace app --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --version 4.11.3 \
    -f "$ROOT_DIR/helm-values/nginx.yaml" \
    --wait --timeout 10m

  helm upgrade --install postgres bitnami/postgresql \
    --namespace app \
    --version 16.7.27 \
    -f "$ROOT_DIR/helm-values/postgres.yaml" \
    --wait --timeout 10m

  helm upgrade --install redis bitnami/redis \
    --namespace app \
    --version 20.11.3 \
    -f "$ROOT_DIR/helm-values/redis.yaml" \
    --wait --timeout 10m

  helm upgrade --install api-gateway "$ROOT_DIR/charts/app" \
    --namespace app \
    -f "$ROOT_DIR/helm-values/app/api-gateway.yaml" \
    --set "image.tag=$API_GATEWAY_TAG" \
    --wait --timeout 10m

  helm upgrade --install dashboard-api "$ROOT_DIR/charts/app" \
    --namespace app \
    -f "$ROOT_DIR/helm-values/app/dashboard-api.yaml" \
    --set "image.tag=$DASHBOARD_API_TAG" \
    --wait --timeout 10m

  for service in inventory-service notification-service order-service payment-service scheduler shipping-service worker; do
    helm upgrade --install "$service" "$ROOT_DIR/charts/app" \
      --namespace app \
      -f "$ROOT_DIR/helm-values/app/$service.yaml" \
      --set "image.tag=$DEFAULT_APP_TAG" \
      --wait --timeout 10m
  done
}

print_result() {
  echo
  echo "Ingress:"
  kubectl get ingress -A
  echo
  echo "Services:"
  kubectl get svc -A
}

main() {
  ensure_prereqs
  ensure_backend_bucket
  terraform_init
  terraform_plan_apply
  ensure_kubeconfig

  if [[ "${RUN_IMAGE_PUSH:-true}" == "true" ]]; then
    ensure_ecr_login
    build_and_push_images
  else
    echo "Skipping image push because RUN_IMAGE_PUSH=false"
  fi

  if [[ "${RUN_HELM_DEPLOY:-true}" == "true" ]]; then
    deploy_helm_stack
    print_result
  else
    echo "Skipping Helm deploy because RUN_HELM_DEPLOY=false"
  fi
}

main "$@"
