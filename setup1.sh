#!/bin/bash

# Couleurs pour le terminal
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==> Démarrage de la configuration de l'environnement Istio...${NC}"

# 1. Vérification et installation de k3d (Kubernetes local)
if ! command -v k3d &> /dev/null; then
    echo -e "${GREEN}Installation de k3d...${NC}"
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

# 2. Création du cluster Kubernetes s'il n'existe pas
if ! k3d cluster list | grep -q "istio-cluster"; then
    echo -e "${GREEN}Création du cluster Kubernetes 'istio-cluster'...${NC}"
    k3d cluster create istio-cluster --servers 1 --agents 0 --no-lb
else
    echo -e "${BLUE}Le cluster 'istio-cluster' existe déjà.${NC}"
fi

# 3. Téléchargement d'Istio
ISTIO_VERSION="1.29.2"
if [ ! -d "istio-$ISTIO_VERSION" ]; then
    echo -e "${GREEN}Téléchargement d'Istio $ISTIO_VERSION...${NC}"
    curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh -
fi

# 4. Configuration du PATH pour istioctl
export PATH=$PWD/istio-$ISTIO_VERSION/bin:$PATH
# Ajout permanent pour la session Codespace
if ! grep -q "istio-$ISTIO_VERSION/bin" ~/.bashrc; then
    echo "export PATH=$PWD/istio-$ISTIO_VERSION/bin:\$PATH" >> ~/.bashrc
fi

# 5. Installation d'Istio avec le profil default
echo -e "${GREEN}Installation d'Istio avec le profil 'default'...${NC}"
istioctl install --set profile=default -y

# 6. Vérification finale
echo -e "${BLUE}==> Vérification des pods Istio...${NC}"
kubectl get pods -n istio-system

echo -e "${GREEN}Configuration terminée !${NC}"
echo -e "Tapez ${BLUE}'source ~/.bashrc'${NC} pour activer la commande 'istioctl' immédiatement."
