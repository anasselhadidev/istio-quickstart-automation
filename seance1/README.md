# Formation Istio - Séance 1 : Introduction, Installation et Fonctionnalités de Base

Bienvenue dans ce premier Lab de notre formation Istio ! 
Dans cette session, nous allons découvrir comment installer Istio sur un cluster Kubernetes via Killercoda, déployer une application de test (Bookinfo), et explorer trois fonctionnalités majeures d'Istio : le **Routage des requêtes**, l'**Injection de pannes** et le **Circuit Breaking**.
## Prérequis
- Accéder à l'environnement interactif gratuit **Killercoda**.
- Aucune connaissance préalable d'Istio n'est requise, suivez simplement les étapes !
---

## Partie 1 : Installation automatisée d'Istio

Pour vous faciliter la vie, nous allons utiliser un script d'automatisation qui va télécharger et configurer Istio sur votre environnement en quelques secondes.

Exécutez la commande suivante dans le terminal de Killercoda :
```markdown
git clone https://github.com/anasselhadidev/istio-quickstart-automation.git && cd istio-quickstart-automation && chmod +x setup.sh && ./setup.sh
```

Une fois le script terminé, placez-vous dans le dossier d'installation d'Istio (la version téléchargée par le script, ici `1.29.2`) :

```bash
cd istio-1.29.2
```

---

## Partie 2 : Déploiement de l'application "Bookinfo" et Exposition

Pour tester Istio, nous allons utiliser **Bookinfo**, une application de démonstration composée de 4 microservices (productpage, details, reviews, ratings). 

### 1. Déployer l'application et la Gateway
Nous allons déployer les composants de l'application et configurer la passerelle d'entrée (Gateway) d'Istio pour autoriser le trafic externe à entrer dans notre cluster.

```bash
kubectl apply -f samples/bookinfo/platform/kube/bookinfo.yaml
kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
```

Vérifions que le composant `istio-ingressgateway` (qui agit comme la porte d'entrée de notre cluster) est bien en cours d'exécution :

```bash
kubectl get svc istio-ingressgateway -n istio-system
```

### 2. Récupérer l'URL de l'application (NodePort)
Pour accéder à notre application depuis notre navigateur, nous devons extraire l'adresse IP de notre nœud et le port exposé. Copiez-collez ce bloc entier dans votre terminal :

```bash
# 1. Définir le nom et namespace du composant Ingress d'Istio
export INGRESS_NAME=istio-ingressgateway
export INGRESS_NS=istio-system

# 2. Extraire le NodePort (le port exposé physiquement sur le nœud)
export INGRESS_PORT=$(kubectl -n "${INGRESS_NS}" get service "${INGRESS_NAME}" -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')

# 3. Extraire l'adresse IP interne du nœud (Host IP)
export INGRESS_HOST=$(kubectl get po -l istio=ingressgateway -n "${INGRESS_NS}" -o jsonpath='{.items[0].status.hostIP}')

# 4. Assembler l'URL complète
export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT

# 5. Vérifier le résultat
echo "L'URL de la Gateway est : http://$GATEWAY_URL/productpage"
```

> **Action :** Cliquez sur l'URL générée ou copiez-la dans votre navigateur pour voir la page de l'application Bookinfo ! Rafraîchissez la page plusieurs fois : vous remarquerez que la section des avis (reviews) change (parfois pas d'étoiles, parfois étoiles noires, parfois étoiles rouges). C'est parce qu'Istio répartit le trafic aléatoirement entre les 3 versions du service `reviews` existantes.

### 3. Définir les versions des services (Destination Rules)
Avant de pouvoir utiliser Istio pour contrôler le routage des versions de Bookinfo, vous devez définir les versions disponibles. Istio utilise des *subsets* (sous-ensembles), dans des *destination rules* (règles de destination), pour définir les versions d'un service.

Exécutez la commande suivante pour créer les règles de destination par défaut pour les services Bookinfo :

```bash
kubectl apply -f samples/bookinfo/networking/destination-rule-all.yaml
```

Attendez quelques secondes pour que les règles de destination se propagent. Vous pouvez afficher ces règles avec la commande suivante :

```bash
kubectl get destinationrules -o yaml
```

---

## Partie 3 : Routage des requêtes (Request Routing)

L'objectif de cette tâche est de prendre le contrôle du trafic. Nous allons d'abord forcer tout le monde à utiliser la "Version 1" de tous les microservices. Ensuite, nous allons diriger un utilisateur spécifique vers la "Version 2".

### 1. Router tout le trafic vers la Version 1 (v1)
Appliquons des règles (VirtualServices) pour envoyer 100% du trafic vers la v1.

```bash
kubectl apply -f samples/bookinfo/networking/virtual-service-all-v1.yaml
```

> **Test :** Retournez sur la page web `/productpage` et rafraîchissez plusieurs fois. Vous verrez qu'il n'y a **plus jamais d'étoiles**. Tout le trafic va maintenant sur `reviews:v1` (qui ne possède pas la fonctionnalité des étoiles).

### 2. Router en fonction de l'identité de l'utilisateur
Nous voulons que seul l'utilisateur nommé **jason** ait accès à la version avec les étoiles (`reviews:v2`).

```bash
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-test-v2.yaml
```

> **Test :** > 1. Sur la page web de Bookinfo, cliquez sur **"Sign in"** en haut à droite.
> 2. Connectez-vous avec le nom d'utilisateur `jason` (le mot de passe n'a pas d'importance).
> 3. Regardez les avis : les étoiles noires apparaissent !
> 4. Déconnectez-vous : les étoiles disparaissent. Istio lit l'en-tête HTTP pour identifier "jason" et redirige son trafic intelligemment.

---

## Partie 4 : Injection de pannes (Fault Injection)

Istio permet de tester la résilience de votre application en introduisant volontairement des pannes ou des lenteurs, sans toucher au code source !

### 1. Injecter un délai (Lenteur réseau)
Nous allons injecter un délai de 7 secondes pour l'utilisateur `jason` entre les services `reviews:v2` et `ratings`.

```bash
kubectl apply -f samples/bookinfo/networking/virtual-service-ratings-test-delay.yaml
```

> **Test :** Connectez-vous en tant que `jason` et rechargez la page. Vous remarquerez que la page met environ 6 secondes à charger, et affiche un **message d'erreur** à la place des avis. 
> *Pourquoi ?* Le service `productpage` a un délai d'attente codé en dur (timeout) de 6 secondes. Puisque nous avons forcé un délai de 7 secondes en dessous, l'application parente abandonne avant et affiche une erreur. Nous avons découvert un bug d'architecture grâce à Istio !

### 2. Injecter une erreur HTTP (Abort)
Annulons le délai et introduisons plutôt une panne totale (Erreur 500) pour `jason`.

```bash
kubectl apply -f samples/bookinfo/networking/virtual-service-ratings-test-abort.yaml
```

> **Test :** Toujours connecté en tant que `jason`, rechargez la page. Elle se charge instantanément, mais indique : *"Ratings service is currently unavailable"*. Le composant a été bloqué par notre règle.

---

## Partie 5 : Le Disjoncteur (Circuit Breaking)

Le "Circuit Breaking" permet de protéger vos services en limitant le nombre de requêtes simultanées. Si un service est sous l'eau, Istio "coupe le disjoncteur" et rejette rapidement les requêtes supplémentaires au lieu de faire planter tout le système.

### 1. Préparer l'environnement de test
Nous allons déployer un service appelé `httpbin` et un outil de test de charge appelé `fortio`.

```bash
# Déployer l'application cible
kubectl apply -f samples/httpbin/httpbin.yaml

# Déployer l'outil de test de charge client
kubectl apply -f samples/httpbin/sample-client/fortio-deploy.yaml
```

### 2. Configurer la règle du disjoncteur
Nous allons limiter le service `httpbin` à **1 seule connexion simultanée** et **1 seule requête en attente**.

```bash
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
spec:
  host: httpbin
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1
      http:
        http1MaxPendingRequests: 1
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 1
      interval: 1s
      baseEjectionTime: 3m
      maxEjectionPercent: 100
EOF
```

### 3. Tester le disjoncteur
Récupérons le nom du Pod de notre outil de test `fortio` :
```bash
export FORTIO_POD=$(kubectl get pods -l app=fortio -o 'jsonpath={.items[0].metadata.name}')
```

Faisons une simple requête unique pour vérifier que tout fonctionne (Statut 200 OK attendu) :
```bash
kubectl exec "$FORTIO_POD" -c fortio -- /usr/bin/fortio curl -quiet http://httpbin:8000/get
```

**Surchargeons le système !**
Lançons 20 requêtes avec 2 connexions simultanées :
```bash
kubectl exec "$FORTIO_POD" -c fortio -- /usr/bin/fortio load -c 2 -qps 0 -n 20 -loglevel Warning http://httpbin:8000/get
```
*Observez les résultats : vous verrez que certaines requêtes échouent avec un code `503` (Service Unavailable).*

Augmentons la charge à 30 requêtes et 3 connexions simultanées :
```bash
kubectl exec "$FORTIO_POD" -c fortio -- /usr/bin/fortio load -c 3 -qps 0 -n 30 -loglevel Warning http://httpbin:8000/get
```
*Le pourcentage de codes `503` augmentera considérablement (souvent plus de 60% d'échec).*

### 4. Analyser les statistiques d'Istio
Pour confirmer qu'il s'agit bien d'Istio qui a bloqué le trafic (et non le service qui a planté), nous pouvons consulter les statistiques du proxy :

```bash
kubectl exec "$FORTIO_POD" -c istio-proxy -- pilot-agent request GET stats | grep httpbin | grep pending
```

Vous verrez une valeur pour `upstream_rq_pending_overflow` (ex: 21). Cela indique le nombre exact d'appels qui ont été bloqués et rejetés par le mécanisme de Circuit Breaking d'Istio pour protéger l'application `httpbin`.
