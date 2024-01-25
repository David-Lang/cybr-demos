#!/bin/bash
# shellcheck disable=SC2046
# shellcheck disable=SC2005
# shellcheck disable=SC2153
set -euo pipefail

main() {
  printf "\nJenkins Setup\n"
  set_variables
  start_jenkins
  printf "\n"
}


set_variables() {
  printf "\nSetting local vars from Env\n"

#  jenkins_image="jenkins/jenkins:lts"
  jenkins_container="$JENKINS_CONTAINER"
#  jenkins_volume="cybr-jenkins"
  jenkins_port=8081

  host_fqdn=$(curl --silent http://169.254.169.254/latest/meta-data/public-hostname)
}

start_jenkins() {
  printf "\nStarting Jenkins\n"
#  docker build -f ./Dockerfile -t $cybr_jenkins_image:latest .

  # create volume for persistence of state across container instances
#  if [[ "$(docker volume ls | grep "$jenkins_volume")" == "" ]]; then
#    docker volume create "$jenkins_volume"
#  fi

  if [[ "$(docker ps | grep "$jenkins_container")" == "" ]]; then
     docker run -p "$jenkins_port":8080 -d --name "$jenkins_container" --restart always jenkins/jenkins:lts
     sleep 5
     docker logs "$jenkins_container"
  fi

  printf "\n\nKeystore Password is: changeit\n\n"
  printf "\nWaiting for Jenkins to start up...\n"

  echo
  echo "======== Configuration info ========="
  echo
  echo "Follow the README.md file for guidance on setting up Jenkins"
  echo
  echo "Jenkins URL: http://$host_fqdn:$jenkins_port"
  echo
  echo -n "Initial Jenkins admin password: "
  echo $(docker exec "$jenkins_container" cat /var/lib/jenkins/secrets/initialAdminPassword)
  echo
}

main "$@"
