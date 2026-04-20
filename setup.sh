#!/bin/bash

echo "🚀 Démarrage de l'automatisation Istio..."

# 1. Télécharger Istio (on prend la dernière version stable)
curl -L https://istio.io/downloadIstio | sh -

# 2. Identifier le dossier créé (ex: istio-1.24.1)
ISTIO_DIR=$(ls -d istio-*)
echo "Dossier Istio détecté : $ISTIO_DIR"

# 3. Ajouter istioctl au PATH
export PATH=$PWD/$ISTIO_DIR/bin:$PATH
# On l'ajoute aussi au .bashrc pour que ce soit permanent durant la session
echo "export PATH=$PWD/$ISTIO_DIR/bin:\$PATH" >> ~/.bashrc

# 4. Installer Istio avec le profil demo
istioctl install --set profile=demo -y

# 5. Activer l'injection automatique de sidecars sur le namespace default
kubectl label namespace default istio-injection=enabled

# 6. (Optionnel) Installer les addons : Kiali, Prometheus, Grafana
echo "Installation des addons (Kiali, Prometheus...)"
kubectl apply -f $ISTIO_DIR/samples/addons

echo " Installation terminée ! Tape 'source ~/.bashrc' pour activer istioctl."
