#!/bin/bash
set -euo pipefail

if [[ ! -z ${CI+x} ]]; then
  aws-configure chef-cd

  mkdir -p ~/.kube
  aws --profile chef-cd s3 cp s3://chef-cd-citadel/kubernetes.chef.co.config ~/.kube/config
else
  echo "WARN: Not running in Buildkite, assuming local manual deployment"
  echo "WARN: This requires that ~/.kube/config exists with the proper content"
fi

export ENVIRONMENT=${ENVIRONMENT:-acceptance}
export APP=${APP:-nginx-demo}
DEBUG=${DEBUG:-false}

# This block translates the "environment" into the appropriate Habitat
# channel from which we'll deploy from
if [ "$ENVIRONMENT" == "acceptance" ]; then
  export CHANNEL=dev
elif [ "$ENVIRONMENT" == "production" ]; then
  export CHANNEL=stable
elif [ "$ENVIRONMENT" == "dev" ]; then
  export CHANNEL=unstable
else
  echo "We do not currently support deploying to $ENVIRONMENT"
  exit 1
fi

get_image_tag() {
  results=$(curl --silent https://willem.habitat.sh/v1/depot/channels/chefops/${CHANNEL}/pkgs/nginx-demo/latest | jq '.ident')
  pkg_version=$(echo "$results" | jq -r .version)
  pkg_release=$(echo "$results" | jq -r .release)
  echo "${pkg_version}-${pkg_release}"
}

get_elb_hostname() {
  kubectl get services ${APP}-${ENVIRONMENT} --namespace=${APP} -o json 2>/dev/null | \
    jq '.status.loadBalancer.ingress[].hostname' -r
}

get_namespace() {
    kubectl get namespace $APP -o json 2>/dev/null | \
    jq '.metadata.name'
}

create_namespace() {
  target_name=$(get_namespace || echo)
  if [[ ! -n $target_name ]]; then
    kubectl create namespace $APP
  fi
}

wait_for_elb() {
  attempts=0
  max_attempts=10
  elb_host=""
  while [[ $attempts -lt $max_attempts ]]; do
    elb_host=$(get_elb_hostname || echo)

    if [[ ! -n $elb_host ]]; then
      echo "Did not find ELB yet... sleeping 5s"
      attempts=$[$attempts + 1]
      sleep 5
    else
      echo "Found ELB: $elb_host"
      break
    fi
  done
}

if [[ $DEBUG == "true" ]]; then
  echo "--- DEBUG: Environment"
  echo "Application: ${APP}"
  echo "Channel: ${CHANNEL}"
  echo "Environment: ${ENVIRONMENT}"
fi

echo "--- Checking for and creating ${APP} namespace in Kubernetes"
create_namespace

echo "--- Applying kubernetes configuration for ${ENVIRONMENT} to cluster"
IMAGE_TAG=$(get_image_tag) erb -T- kubernetes/deployment.yml | kubectl apply -f -

echo "+++ Waiting for Load Balancer..."
wait_for_elb
