#!/bin/bash
# Install a single node deployment of Stackable

# This is the list of currently supported operators for Stackable Quickstart
# Don't edit this list unless you know what you're doing. If you get an error
# that you're attempting to install an unsupported operator then check the
# OPERATORS list for typos.
ALLOWED_OPERATORS=(zookeeper kafka nifi spark hive trino opa regorule)

# Do you want to use the dev or release repository?
REPO_TYPE=dev
HELM_REPO_URL="https://repo.stackable.tech/repository/helm-${REPO_TYPE}/"
HELM_REPO_NAME="stackable"

# List of operators to install
OPERATORS=(zookeeper kafka nifi spark hive trino opa regorule)

if [ $UID != 0 ]
then
  echo "This script must be run as root, exiting."
  exit 1
fi

BASEDIR=$(dirname "$0")
CONFDIR=$BASEDIR/conf
CRDDIR=$BASEDIR/crds

function print_r {
  /usr/bin/echo -e "\e[0;31m${1}\e[m"
}
function print_y {
  /usr/bin/echo -e "\e[0;33m${1}\e[m"
}
function print_g {
  /usr/bin/echo -e "\e[0;32m${1}\e[m"
}

function install_prereqs {
  . /etc/os-release

  if [ "$ID" = "centos" ] || [ "$ID" = "redhat" ]; then
    if [ "$VERSION_ID" = "8" ] || [ "$VERSION_ID" = "7" ]; then
      print_g "$ID $VERSION found"
      INSTALLER=/usr/bin/yum
      install_prereqs_redhat
    else
      print_r "Only Redhat/CentOS 7 & 8 are supported. This host is running $VERSION_ID."
      exit 1
    fi
  elif [ "$ID" = "ubuntu" ]; then
    print_g "$ID $VERSION_ID found"
    if [ "$VERSION_ID" != "20.04" ]; then
        print_y "Only Ubuntu 20.04 LTS is officially supported by Stackable Quickstart. Your mileage may vary."
    fi
    INSTALLER=apt
    install_prereqs_ubuntu
  elif [ "$ID" = "debian" ]; then
    if [ "$VERSION_ID" = "10" ]; then
      print_g "$ID $VERSION_ID found"
      INSTALLER=apt
      install_prereqs_debian
    else
      print_r "Only Debian 10 is supported. This host is running $ID $VERSION_ID."
      exit 1
    fi
  else
    print_r "Unsupported operating system detected: $ID $VERSION_ID"
    exit 1
  fi
}

function install_prereqs_redhat {
  print_g "Installing prerequisite OS packages"
  /usr/bin/yum -y install gnupg2 java-11-openjdk curl python
}

function install_prereqs_debian {
  print_g "Installing prerequisite OS packages"
  apt-get -q -y install gnupg openjdk-11-jdk curl python
}

function install_prereqs_ubuntu {
  print_g "Installing prerequisite OS packages"
#  apt-get -q -y install gnupg openjdk-11-jdk curl python
  apt-get -q -y install curl
}

function install_k8s {
  print_g "Installing K8s"

  # Check for previous installation of k8s
  if [ -f "/usr/local/bin/kubectl" ]
  then
    print_y "kubectl already present, skipping k8s install"
    return
  fi

  /usr/bin/curl -sfL https://get.k3s.io | /bin/sh -
  /usr/local/bin/kubectl cluster-info

  print_g "Copying K8s configuration to /root/.kube/config"
  /usr/bin/mkdir -p /root/.kube
  /usr/bin/cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
}

function install_k9s {
  print_g "Installing K9s"

  # Check for previous installation of k9s
  if [ -f "/usr/local/bin/k9s" ]
  then
    print_y "k9s already present, skipping k9s install"
    return
  fi

  URL=https://github.com/derailed/k9s/releases/download/v0.24.15/k9s_Linux_x86_64.tar.gz
  TMPFILE=/tmp/k9s.tar.gz
  /usr/bin/curl -s -L $URL > $TMPFILE
  (cd /usr/local/bin && /usr/bin/tar xf $TMPFILE k9s)
  /usr/bin/rm $TMPFILE
}

function install_helm {
  print_g "Installing Helm"
  /usr/bin/curl -sfL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | /bin/bash -
  /usr/local/bin/helm repo add ${HELM_REPO_NAME} ${HELM_REPO_URL}
}

function install_crds {
  # TODO: Install the CRDs based on the list of operators to install
  print_g "Installing Stackable CRDs"
  kubectl apply -f "$CRDDIR"
}

function check_operator_list {
  for OPERATOR in "${OPERATORS[@]}"; do
    if [[ ! " ${ALLOWED_OPERATORS[@]} " =~ " ${OPERATOR} " ]]; then
      print_r "Operator $OPERATOR is not in the allowed operator list."
      exit 1
    fi
  done
  print_g "List of operators checked"
}

function install_operator {
  OPERATOR=$1
  PKG_NAME=${OPERATOR}-operator
  print_g "Installing Stackable operator for ${OPERATOR}"
  /usr/local/bin/helm install "${PKG_NAME}" "${HELM_REPO_NAME}/$PKG_NAME" --devel
}

function install_stackable_operators {
  print_g "Installing Stackable operators"
  for OPERATOR in "${OPERATORS[@]}"; do
    install_operator $OPERATOR
  done
}

function deploy_service {
  SERVICE=$1
  CONF=${CONFDIR}/${SERVICE}.yaml
  if [ ! -f $CONF ]
  then
    print_r "Cannot find service configuration file ${CONF} for ${SERVICE}"
    exit 1
  fi

  print_g "Deploying ${SERVICE}"
  kubectl apply -f "${CONF}"
}


# MAIN
# Check the list of operators to deploy against the allowed list
check_operator_list

# Install the prerequisite OS-dependant repos and packages
install_prereqs

# Install the K3s Kubernetes distribution
install_k8s

# Install k9s
install_k9s

# Install Helm
install_helm

# Install the Stackable operators for the chosen components
install_stackable_operators

# Deploy Stackable Components
for OPERATOR in "${OPERATORS[@]}"; do
  print_g "Deploying ${OPERATOR}"
  deploy_service "${OPERATOR}"
done
