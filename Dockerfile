FROM jenkins/jenkins:lts
USER root

ARG IMAGE_VERSION=v1.0
ENV JENKINS_IMAGE_VERSION=$IMAGE_VERSION

RUN jenkins-plugin-cli --plugins \
    workflow-aggregator \
    git \
    docker-workflow \
    blueocean \
    timestamper

USER jenkins
