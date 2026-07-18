FROM jenkins/jenkins:lts-jdk21

USER root
ARG TARGETARCH
ARG KUBECTL_VERSION=v1.35.6

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg unzip jq git python3 python3-pip python3-venv \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg \
       -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && . /etc/os-release \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $VERSION_CODENAME stable" \
       > /etc/apt/sources.list.d/docker.list \
    && curl -fsSL https://apt.releases.hashicorp.com/gpg \
       | gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg \
    && . /etc/os-release \
    && echo "deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $VERSION_CODENAME main" \
       > /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       docker-ce-cli docker-buildx-plugin docker-compose-plugin terraform \
    && case "$TARGETARCH" in \
         amd64) AWS_ARCH=x86_64 ;; \
         arm64) AWS_ARCH=aarch64 ;; \
         *) echo "Unsupported architecture: $TARGETARCH" && exit 1 ;; \
       esac \
    && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" \
       -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
       -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl \
    && rm -rf /var/lib/apt/lists/* /tmp/aws /tmp/awscliv2.zip

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

USER root
