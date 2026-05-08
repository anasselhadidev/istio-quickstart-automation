# Formation Istio - Séance 2 : Sécurité — Gestion des Certificats, Authentification & Autorisation

Bienvenue dans ce deuxième Lab de notre formation Istio !

Dans cette session, nous allons explorer le côté **sécurité** d'Istio, qui est l'une des fonctionnalités les plus puissantes du service mesh. Nous allons couvrir trois grandes thématiques :

1. **Gestion des Certificats (CA Certificates)** — comment Istio sécurise les communications entre services avec du chiffrement TLS mutuel, et comment remplacer les certificats auto-signés par les vôtres.
2. **Politiques d'Authentification (Authentication Policies)** — comment contrôler *qui peut parler à qui* dans votre mesh, en utilisant mTLS et JWT.
3. **Politiques d'Autorisation (Authorization Policies)** — comment contrôler *ce que chaque service ou utilisateur a le droit de faire*.

> **Pas de panique !** Ce lab est conçu pour être suivi pas à pas, même si vous n'avez jamais touché à Istio ou Kubernetes auparavant. Chaque commande est expliquée, chaque résultat attendu est décrit.

---

## 🖥️ Environnement : Killercoda

Tous les exercices se font sur **[Killercoda](https://killercoda.com)**, un environnement Kubernetes gratuit accessible depuis votre navigateur.

### Comment démarrer sur Killercoda :

1. Allez sur [https://killercoda.com](https://killercoda.com)
2. Créez un compte gratuit (ou connectez-vous avec GitHub/Google)
3. Cherchez **"Kubernetes"** et ouvrez un playground avec un cluster Kubernetes
4. Vous obtenez un terminal dans votre navigateur — c'est là que vous allez coller toutes les commandes de ce lab !

---

## Partie 0 : Installation automatisée d'Istio (point de départ obligatoire)

Avant de commencer, il faut installer Istio sur votre cluster Killercoda. Utilisez le script d'automatisation ci-dessous — il fait tout pour vous en quelques secondes.

**Collez cette commande dans votre terminal Killercoda :**

```bash
git clone https://github.com/anasselhadidev/istio-quickstart-automation.git && cd istio-quickstart-automation && chmod +x setup.sh && ./setup.sh
```

> ⏳ Attendez que le script se termine complètement. Vous verrez un message de confirmation à la fin.

Ensuite, placez-vous dans le dossier Istio :

```bash
cd istio-1.29.2
```

✅ **Vérification :** Tapez la commande suivante pour confirmer qu'Istio est bien installé :

```bash
kubectl get pods -n istio-system
```

Vous devez voir plusieurs pods avec le statut `Running`. Si c'est le cas, vous êtes prêt !

---

---

# 🔐 Partie 1 : Gestion des Certificats CA (Plug in CA Certificates)

## Qu'est-ce que c'est, et pourquoi c'est important ?

Imaginez que deux services dans votre cluster veulent se parler. Comment savent-ils que l'autre service est *vraiment* lui, et pas un imposteur ? Grâce aux **certificats TLS**.

Par défaut, Istio génère automatiquement ses propres certificats "auto-signés" (il joue à la fois le rôle de la banque et du client qui se garantit lui-même). C'est fonctionnel, mais pas idéal pour la production.

Dans cette partie, nous allons apprendre à **remplacer ces certificats auto-signés** par une hiérarchie de certificats que nous contrôlons :

```
[Certificat Racine (Root CA)]  ← vous le créez et le gardez précieusement
         ↓
[Certificat Intermédiaire (Intermediate CA)]  ← utilisé par Istio dans le cluster
         ↓
[Certificats des workloads]  ← générés automatiquement par Istio pour chaque pod
```

---

## Étape 1 : Créer le dossier de travail pour les certificats

Depuis le dossier `istio-1.29.2`, créez un dossier `certs` et entrez dedans :

```bash
mkdir -p certs
pushd certs
```

> 💡 `pushd` est comme `cd`, mais il mémorise où vous étiez pour pouvoir y revenir avec `popd`.

---

## Étape 2 : Générer le certificat racine (Root CA)

Le certificat racine est la **clé maîtresse** de toute votre infrastructure de sécurité. Dans un environnement de production, on le génère sur une machine hors ligne et on le garde dans un coffre-fort. Ici, on le génère pour l'exercice.

```bash
make -f ../tools/certs/Makefile.selfsigned.mk root-ca
```

✅ Cette commande génère 4 fichiers dans le dossier courant :

| Fichier | Rôle |
|---|---|
| `root-cert.pem` | Le certificat racine (la "carte d'identité" de votre CA racine) |
| `root-key.pem` | La clé privée racine ⚠️ À garder secrète ! |
| `root-ca.conf` | La configuration OpenSSL utilisée pour générer le certificat |
| `root-cert.csr` | La demande de signature de certificat (CSR) |

---

## Étape 3 : Générer le certificat intermédiaire pour le cluster

C'est ce certificat intermédiaire qu'Istio va utiliser dans votre cluster pour signer les certificats des workloads.

```bash
make -f ../tools/certs/Makefile.selfsigned.mk cluster1-cacerts
```

✅ Cette commande crée un sous-dossier `cluster1/` avec :

| Fichier | Rôle |
|---|---|
| `ca-cert.pem` | Le certificat CA intermédiaire |
| `ca-key.pem` | La clé privée du CA intermédiaire |
| `cert-chain.pem` | La chaîne complète (intermédiaire + racine), utilisée par istiod |
| `root-cert.pem` | Copie du certificat racine |

Vérifiez que les fichiers sont bien là :

```bash
ls -la cluster1/
```

---

## Étape 4 : Créer le namespace `istio-system` et injecter les certificats

Maintenant on va donner ces certificats à Istio via un **Secret Kubernetes**. Un Secret, c'est un objet Kubernetes pour stocker des données sensibles (mots de passe, certificats, clés…).

```bash
# Retour dans le dossier certs si vous en êtes sorti
# (normalement vous y êtes encore avec pushd)

# 1. Créer le namespace istio-system (où vit le plan de contrôle d'Istio)
kubectl create namespace istio-system

# 2. Créer le Secret avec nos 4 fichiers de certificats
kubectl create secret generic cacerts -n istio-system \
      --from-file=cluster1/ca-cert.pem \
      --from-file=cluster1/ca-key.pem \
      --from-file=cluster1/root-cert.pem \
      --from-file=cluster1/cert-chain.pem
```

✅ **Vérification :** Confirmez que le Secret existe :

```bash
kubectl get secret cacerts -n istio-system
```

Vous devez voir quelque chose comme :
```
NAME      TYPE     DATA   AGE
cacerts   Opaque   4      5s
```

---

## Étape 5 : Revenir au dossier principal et déployer Istio

```bash
# Revenir au dossier istio-1.29.2 (c'est ce que fait popd)
popd

# Déployer Istio avec le profil demo
istioctl install --set profile=demo
```

> ⏳ Cette commande prend environ 1-2 minutes. Répondez `y` si on vous demande confirmation.
>
> 💡 Istio va maintenant lire automatiquement le Secret `cacerts` pour utiliser VOS certificats au lieu de ceux auto-signés.

✅ **Vérification :** Attendez que tous les pods soient prêts :

```bash
kubectl get pods -n istio-system
```

Tous les pods doivent être en état `Running`.

---

## Étape 6 : Déployer des services de test

Nous allons déployer deux services simples (`httpbin` et `curl`) dans un namespace `foo` pour tester notre configuration.

```bash
# Créer le namespace foo
kubectl create ns foo

# Déployer httpbin (un service HTTP de test)
# La commande "istioctl kube-inject" injecte automatiquement le sidecar proxy Envoy
kubectl apply -f <(istioctl kube-inject -f samples/httpbin/httpbin.yaml) -n foo

# Déployer curl (un client HTTP pour faire des requêtes)
kubectl apply -f <(istioctl kube-inject -f samples/curl/curl.yaml) -n foo
```

> 💡 **Qu'est-ce que `istioctl kube-inject` ?** Istio fonctionne en injectant un petit proxy (appelé "sidecar") à côté de chaque pod. Cette commande modifie les manifestes YAML pour ajouter ce proxy automatiquement.

✅ **Vérification :** Les pods doivent être en état `Running` avec 2 containers chacun (l'app + le sidecar) :

```bash
kubectl get pods -n foo
```

---

## Étape 7 : Appliquer une politique mTLS stricte

Pour que tous les services du namespace `foo` n'acceptent que des connexions chiffrées mTLS, on applique une `PeerAuthentication` :

```bash
kubectl apply -n foo -f - <<EOF
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: "default"
spec:
  mtls:
    mode: STRICT
EOF
```

> 💡 **Qu'est-ce que mTLS ?** Le TLS mutuel (mTLS) signifie que les deux parties (client ET serveur) présentent un certificat pour se vérifier mutuellement. Contrairement au HTTPS classique où seul le serveur présente un certificat.

---

## Étape 8 : Vérifier que les certificats sont bien les nôtres !

C'est le moment de vérification. Attendons 20 secondes que la politique mTLS se propage, puis on inspecte les certificats utilisés par le proxy :

```bash
sleep 20; kubectl exec "$(kubectl get pod -l app=curl -n foo -o jsonpath={.items..metadata.name})" -c istio-proxy -n foo -- openssl s_client -showcerts -connect httpbin.foo:8000 > httpbin-proxy-cert.txt
```

> 💡 Cette commande utilise `openssl` à l'intérieur du container proxy pour faire une connexion TLS et récupérer tous les certificats présentés. Le résultat est sauvegardé dans `httpbin-proxy-cert.txt`.

Extrayons les certificats individuels :

```bash
sed -n '/-----BEGIN CERTIFICATE-----/{:start /-----END CERTIFICATE-----/!{N;b start};/.*/p}' httpbin-proxy-cert.txt > certs.pem
awk 'BEGIN {counter=0;} /BEGIN CERT/{counter++} { print > "proxy-cert-" counter ".pem"}' < certs.pem
```

Vous avez maintenant des fichiers `proxy-cert-1.pem`, `proxy-cert-2.pem`, `proxy-cert-3.pem`.

**Vérification 1 — Le certificat racine est bien le nôtre :**

```bash
openssl x509 -in certs/cluster1/root-cert.pem -text -noout > /tmp/root-cert.crt.txt
openssl x509 -in ./proxy-cert-3.pem -text -noout > /tmp/pod-root-cert.crt.txt
diff -s /tmp/root-cert.crt.txt /tmp/pod-root-cert.crt.txt
```

✅ **Résultat attendu :**
```
Files /tmp/root-cert.crt.txt and /tmp/pod-root-cert.crt.txt are identical
```

**Vérification 2 — Le certificat CA intermédiaire est bien le nôtre :**

```bash
openssl x509 -in certs/cluster1/ca-cert.pem -text -noout > /tmp/ca-cert.crt.txt
openssl x509 -in ./proxy-cert-2.pem -text -noout > /tmp/pod-cert-chain-ca.crt.txt
diff -s /tmp/ca-cert.crt.txt /tmp/pod-cert-chain-ca.crt.txt
```

✅ **Résultat attendu :**
```
Files /tmp/ca-cert.crt.txt and /tmp/pod-cert-chain-ca.crt.txt are identical
```

**Vérification 3 — La chaîne de certificats est valide :**

```bash
openssl verify -CAfile <(cat certs/cluster1/ca-cert.pem certs/cluster1/root-cert.pem) ./proxy-cert-1.pem
```

✅ **Résultat attendu :**
```
./proxy-cert-1.pem: OK
```

🎉 **Félicitations !** Vous avez prouvé qu'Istio utilise bien VOS certificats pour sécuriser les communications entre services !

---

## 🧹 Nettoyage de la Partie 1

```bash
# Supprimer les fichiers de certificats locaux
rm -rf certs

# Supprimer le Secret dans Kubernetes
kubectl delete secret cacerts -n istio-system

# Supprimer la politique d'authentification
kubectl delete peerauthentication -n foo default

# Supprimer les applications de test
kubectl delete -f samples/curl/curl.yaml -n foo
kubectl delete -f samples/httpbin/httpbin.yaml -n foo

# Désinstaller Istio complètement
istioctl uninstall --purge -y

# Supprimer les namespaces
kubectl delete ns foo istio-system
```

---

---

# 🛡️ Partie 2 : Politiques d'Authentification (Authentication Policies)

## Qu'est-ce que l'authentification dans Istio ?

L'authentification répond à la question : **"Qui êtes-vous ?"**

Istio supporte deux types d'authentification :

- **`PeerAuthentication`** (authentification entre services) : Contrôle comment les services se vérifient mutuellement, via **mTLS** (TLS mutuel). C'est la sécurité au niveau réseau/transport.
- **`RequestAuthentication`** (authentification des utilisateurs finaux) : Contrôle si un utilisateur humain (ou une application externe) présente un **token JWT** valide. C'est la sécurité au niveau applicatif.

---

## Installation d'Istio pour cette partie dans codespace
Une fois votre Codespace ouvert, lancez simplement la commande suivante :

```bash
chmod +x setup1.sh && ./setup1.sh && source ~/.bashrc
```
---

## Étape 1 : Préparer l'environnement de test (3 namespaces)

Nous allons créer 3 namespaces avec des configurations différentes pour voir comment les politiques interagissent :

- `foo` : namespace avec sidecar Istio injecté
- `bar` : namespace avec sidecar Istio injecté
- `legacy` : namespace **SANS** sidecar (simule un vieux service non-managé par Istio)

```bash
# Namespace foo avec sidecar
kubectl create ns foo
kubectl apply -f <(istioctl kube-inject -f samples/httpbin/httpbin.yaml) -n foo
kubectl apply -f <(istioctl kube-inject -f samples/curl/curl.yaml) -n foo

# Namespace bar avec sidecar
kubectl create ns bar
kubectl apply -f <(istioctl kube-inject -f samples/httpbin/httpbin.yaml) -n bar
kubectl apply -f <(istioctl kube-inject -f samples/curl/curl.yaml) -n bar

# Namespace legacy SANS sidecar (on n'utilise pas kube-inject ici !)
kubectl create ns legacy
kubectl apply -f samples/httpbin/httpbin.yaml -n legacy
kubectl apply -f samples/curl/curl.yaml -n legacy
```

> ⏳ Attendez que tous les pods soient en état `Running` :

```bash
kubectl get pods -n foo
kubectl get pods -n bar
kubectl get pods -n legacy
```

---

## Étape 2 : Vérifier la connectivité initiale (tout doit fonctionner)

Avant d'appliquer des politiques, vérifions que tous les services peuvent se parler. Cette commande teste toutes les combinaisons `curl → httpbin` entre les 3 namespaces :

```bash
for from in "foo" "bar" "legacy"; do
  for to in "foo" "bar" "legacy"; do
    kubectl exec "$(kubectl get pod -l app=curl -n ${from} -o jsonpath={.items..metadata.name})" \
      -c curl -n ${from} -- curl -s "http://httpbin.${to}:8000/ip" -s -o /dev/null \
      -w "curl.${from} to httpbin.${to}: %{http_code}\n"
  done
done
```

✅ **Résultat attendu (tout 200 = tout OK) :**
```
curl.foo to httpbin.foo: 200
curl.foo to httpbin.bar: 200
curl.foo to httpbin.legacy: 200
curl.bar to httpbin.foo: 200
curl.bar to httpbin.bar: 200
curl.bar to httpbin.legacy: 200
curl.legacy to httpbin.foo: 200
curl.legacy to httpbin.bar: 200
curl.legacy to httpbin.legacy: 200
```

> 💡 **Pourquoi tout fonctionne ?** Par défaut, Istio est en mode "permissif" : il peut utiliser mTLS mais accepte aussi du trafic non-chiffré. C'est pour assurer la rétrocompatibilité.

---

## 🔒 Section A : mTLS Strict au niveau Global (tout le mesh)

### Activer mTLS STRICT sur tout le mesh

Cette politique interdit tout trafic non-chiffré dans l'ensemble du mesh. Elle s'applique dans le namespace `istio-system` avec le nom `default` pour couvrir tous les workloads.

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: "default"
  namespace: "istio-system"
spec:
  mtls:
    mode: STRICT
EOF
```

Retestez toutes les connexions :

```bash
for from in "foo" "bar" "legacy"; do
  for to in "foo" "bar" "legacy"; do
    kubectl exec "$(kubectl get pod -l app=curl -n ${from} -o jsonpath={.items..metadata.name})" \
      -c curl -n ${from} -- curl "http://httpbin.${to}:8000/ip" -s -o /dev/null \
      -w "curl.${from} to httpbin.${to}: %{http_code}\n"
  done
done
```

✅ **Résultat attendu :**
```
curl.foo to httpbin.foo: 200
curl.foo to httpbin.bar: 200
curl.foo to httpbin.legacy: 200
curl.bar to httpbin.foo: 200
curl.bar to httpbin.bar: 200
curl.bar to httpbin.legacy: 200
curl.legacy to httpbin.foo: 000   ← BLOQUÉ !
curl.legacy to httpbin.bar: 000   ← BLOQUÉ !
curl.legacy to httpbin.legacy: 200
```

> 💡 **Analyse :** Les requêtes de `curl.legacy` vers `httpbin.foo` et `httpbin.bar` échouent. Pourquoi ? Parce que `curl.legacy` n'a pas de sidecar Istio, donc il ne peut pas faire de mTLS. Les services `httpbin.foo` et `httpbin.bar` ont un sidecar et exigent maintenant mTLS strict → connexion refusée.
>
> Par contre, `curl.legacy → httpbin.legacy` fonctionne toujours car aucun des deux n'a de sidecar : Istio ne gère pas cette connexion du tout.

### Nettoyage de la politique globale

```bash
kubectl delete peerauthentication -n istio-system default
```

---

## 🔒 Section B : mTLS Strict au niveau d'un Namespace

Plutôt que d'appliquer à tout le mesh, on peut cibler un seul namespace.

### Appliquer mTLS STRICT uniquement sur `foo`

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: "default"
  namespace: "foo"
spec:
  mtls:
    mode: STRICT
EOF
```

Retestez :

```bash
for from in "foo" "bar" "legacy"; do
  for to in "foo" "bar" "legacy"; do
    kubectl exec "$(kubectl get pod -l app=curl -n ${from} -o jsonpath={.items..metadata.name})" \
      -c curl -n ${from} -- curl "http://httpbin.${to}:8000/ip" -s -o /dev/null \
      -w "curl.${from} to httpbin.${to}: %{http_code}\n"
  done
done
```

✅ **Résultat attendu :**
```
curl.foo to httpbin.foo: 200
curl.foo to httpbin.bar: 200
curl.foo to httpbin.legacy: 200
curl.bar to httpbin.foo: 200
curl.bar to httpbin.bar: 200
curl.bar to httpbin.legacy: 200
curl.legacy to httpbin.foo: 000   ← BLOQUÉ (foo est strict)
curl.legacy to httpbin.bar: 200   ← OK (bar n'est pas strict)
curl.legacy to httpbin.legacy: 200
```

> 💡 **Analyse :** Seul `httpbin.foo` refuse les connexions non-mTLS. `httpbin.bar` et `httpbin.legacy` les acceptent encore car ils ne sont pas sous la politique STRICT.

---

## 🔒 Section C : mTLS Strict au niveau d'un Workload spécifique

On peut aller encore plus précis et cibler un seul service.

### Appliquer mTLS STRICT uniquement sur `httpbin` dans `bar`

```bash
cat <<EOF | kubectl apply -n bar -f -
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: "httpbin"
  namespace: "bar"
spec:
  selector:
    matchLabels:
      app: httpbin
  mtls:
    mode: STRICT
EOF
```

Retestez :

```bash
for from in "foo" "bar" "legacy"; do
  for to in "foo" "bar" "legacy"; do
    kubectl exec "$(kubectl get pod -l app=curl -n ${from} -o jsonpath={.items..metadata.name})" \
      -c curl -n ${from} -- curl "http://httpbin.${to}:8000/ip" -s -o /dev/null \
      -w "curl.${from} to httpbin.${to}: %{http_code}\n"
  done
done
```

✅ **Résultat attendu :**
```
curl.legacy to httpbin.foo: 000   ← BLOQUÉ (politique namespace foo)
curl.legacy to httpbin.bar: 000   ← BLOQUÉ (politique workload httpbin dans bar)
curl.legacy to httpbin.legacy: 200
```

---

## 🔒 Section D : mTLS par Port (Port-Level mTLS)

On peut même désactiver mTLS sur un port spécifique tout en gardant STRICT sur les autres.

```bash
cat <<EOF | kubectl apply -n bar -f -
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: "httpbin"
  namespace: "bar"
spec:
  selector:
    matchLabels:
      app: httpbin
  mtls:
    mode: STRICT
  portLevelMtls:
    8080:
      mode: DISABLE
EOF
```

> 💡 Cette politique dit : "Pour `httpbin` dans `bar`, exige mTLS sur tous les ports SAUF le port 8080 qui sera en texte clair."

Retestez :

```bash
for from in "foo" "bar" "legacy"; do
  for to in "foo" "bar" "legacy"; do
    kubectl exec "$(kubectl get pod -l app=curl -n ${from} -o jsonpath={.items..metadata.name})" \
      -c curl -n ${from} -- curl "http://httpbin.${to}:8000/ip" -s -o /dev/null \
      -w "curl.${from} to httpbin.${to}: %{http_code}\n"
  done
done
```

✅ **Résultat attendu :** `curl.legacy to httpbin.bar` passe à `200` car le port 8080 est maintenant exempt (mais les tests utilisent le port 8000 donc sur ce port mTLS est toujours actif — observez bien les résultats).

---

## 🔒 Section E : Priorité des politiques (Policy Precedence)

Les politiques **par workload** ont la priorité sur les politiques **par namespace**.

Testez en ajoutant une politique qui **désactive** mTLS pour `httpbin.foo` alors qu'une politique namespace l'exige :

```bash
cat <<EOF | kubectl apply -n foo -f -
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: "overwrite-example"
  namespace: "foo"
spec:
  selector:
    matchLabels:
      app: httpbin
  mtls:
    mode: DISABLE
EOF
```

Testez depuis `legacy` vers `foo` :

```bash
kubectl exec "$(kubectl get pod -l app=curl -n legacy -o jsonpath={.items..metadata.name})" \
  -c curl -n legacy -- curl http://httpbin.foo:8000/ip -s -o /dev/null -w "%{http_code}\n"
```

✅ **Résultat attendu :** `200` — La politique workload a pris le dessus sur la politique namespace !

### Nettoyage de la Section mTLS

```bash
kubectl delete peerauthentication default overwrite-example -n foo
kubectl delete peerauthentication httpbin -n bar
```

---

## 🔑 Section F : Authentification des Utilisateurs Finaux (JWT)

Jusqu'ici on a géré l'authentification **service-à-service**. Maintenant gérons l'authentification des **utilisateurs finaux** avec des tokens JWT.

**Qu'est-ce qu'un JWT ?** C'est un token (jeton) numérique signé que l'utilisateur présente dans ses requêtes pour prouver qui il est. C'est ce qu'utilisent la plupart des APIs modernes.

### Préparer l'Ingress Gateway

D'abord, exposons `httpbin.foo` via l'Ingress Gateway pour simuler un accès depuis l'extérieur :

```bash
kubectl apply -f samples/httpbin/httpbin-gateway.yaml -n foo
```

Récupérez l'URL d'accès :

```bash
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
export INGRESS_HOST=$(kubectl get po -l istio=ingressgateway -n istio-system -o jsonpath='{.items[0].status.hostIP}')
echo "URL de test : http://$INGRESS_HOST:$INGRESS_PORT/headers"
```

Vérifiez que l'accès fonctionne sans authentification :

```bash
curl "http://$INGRESS_HOST:$INGRESS_PORT/headers" -s -o /dev/null -w "%{http_code}\n"
```

✅ **Résultat attendu :** `200`

---

### Ajouter une politique de validation JWT

Cette politique dit à l'Ingress Gateway de valider les tokens JWT émis par `testing@secure.istio.io` :

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: RequestAuthentication
metadata:
  name: "jwt-example"
  namespace: istio-system
spec:
  selector:
    matchLabels:
      istio: ingressgateway
  jwtRules:
  - issuer: "testing@secure.istio.io"
    jwksUri: "https://raw.githubusercontent.com/istio/istio/release-1.29/security/tools/jwt/samples/jwks.json"
EOF
```

> 💡 `jwksUri` pointe vers les clés publiques du serveur d'authentification, utilisées pour vérifier la signature du token JWT.

**Testez trois scénarios :**

```bash
# 1. Sans token → toujours accepté (la RequestAuthentication valide, n'exige pas)
curl "http://$INGRESS_HOST:$INGRESS_PORT/headers" -s -o /dev/null -w "%{http_code}\n"
# Attendu : 200

# 2. Avec un token invalide → refusé
curl --header "Authorization: Bearer ceciestunfauxtokeninutile" \
  "http://$INGRESS_HOST:$INGRESS_PORT/headers" -s -o /dev/null -w "%{http_code}\n"
# Attendu : 401

# 3. Avec un token valide → accepté
TOKEN=$(curl https://raw.githubusercontent.com/istio/istio/release-1.29/security/tools/jwt/samples/demo.jwt -s)
curl --header "Authorization: Bearer $TOKEN" \
  "http://$INGRESS_HOST:$INGRESS_PORT/headers" -s -o /dev/null -w "%{http_code}\n"
# Attendu : 200
```

> 💡 **Important :** La `RequestAuthentication` seule ne rejette pas les requêtes sans token. Elle valide juste les tokens présents. Pour EXIGER un token, il faut une `AuthorizationPolicy` en plus (voir section suivante).

---

### Exiger un token valide (DENY sans token)

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: "frontend-ingress"
  namespace: istio-system
spec:
  selector:
    matchLabels:
      istio: ingressgateway
  action: DENY
  rules:
  - from:
    - source:
        notRequestPrincipals: ["*"]
EOF
```

> 💡 `notRequestPrincipals: ["*"]` signifie "tout le monde qui N'A PAS de principal valide" = tout le monde sans token JWT valide.

Testez maintenant sans token :

```bash
curl "http://$INGRESS_HOST:$INGRESS_PORT/headers" -s -o /dev/null -w "%{http_code}\n"
```

✅ **Résultat attendu :** `403` — Accès refusé car pas de token !

Testez avec un token valide :

```bash
curl --header "Authorization: Bearer $TOKEN" \
  "http://$INGRESS_HOST:$INGRESS_PORT/headers" -s -o /dev/null -w "%{http_code}\n"
```

✅ **Résultat attendu :** `200`

---

### Exiger un token seulement sur certains chemins

On peut raffiner : exiger le JWT seulement sur `/headers`, pas sur `/ip` :

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: "frontend-ingress"
  namespace: istio-system
spec:
  selector:
    matchLabels:
      istio: ingressgateway
  action: DENY
  rules:
  - from:
    - source:
        notRequestPrincipals: ["*"]
    to:
    - operation:
        paths: ["/headers"]
EOF
```

```bash
# /headers sans token → 403 (chemin protégé)
curl "http://$INGRESS_HOST:$INGRESS_PORT/headers" -s -o /dev/null -w "%{http_code}\n"

# /ip sans token → 200 (chemin non protégé)
curl "http://$INGRESS_HOST:$INGRESS_PORT/ip" -s -o /dev/null -w "%{http_code}\n"
```

### Nettoyage de la Section JWT

```bash
kubectl -n istio-system delete requestauthentication jwt-example
kubectl -n istio-system delete authorizationpolicy frontend-ingress
kubectl delete ns foo bar legacy
```

---

---

# 🚦 Partie 3 : Politiques d'Autorisation (Authorization Policies)

## Qu'est-ce que l'autorisation dans Istio ?

L'autorisation répond à la question : **"Avez-vous le droit de faire ça ?"**

Après avoir vérifié qui vous êtes (authentification), Istio vérifie si vous avez la permission d'effectuer l'action demandée.

Istio utilise des `AuthorizationPolicy` avec trois types d'actions :
- **`ALLOW`** : Autoriser explicitement des requêtes qui correspondent aux règles
- **`DENY`** : Refuser explicitement des requêtes (priorité sur ALLOW !)
- **`AUDIT`** : Enregistrer sans bloquer

---

## 🔐 Section A : Contrôle d'accès HTTP sur Bookinfo

Cette section utilise l'application **Bookinfo** (la même que dans le Lab 1). On va construire les permissions couche par couche, en partant de "tout refuser" et en ajoutant progressivement les accès nécessaires.

### Installer Bookinfo

Assurez-vous qu'Istio est installé. Ensuite :

```bash
kubectl apply -f samples/bookinfo/platform/kube/bookinfo.yaml
kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
```

Récupérez l'URL :

```bash
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
export INGRESS_HOST=$(kubectl get po -l istio=ingressgateway -n istio-system -o jsonpath='{.items[0].status.hostIP}')
export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
echo "http://$GATEWAY_URL/productpage"
```

Vérifiez que l'application fonctionne dans votre navigateur.

---

### Étape 1 : Politique "Tout Refuser" (Allow-Nothing)

Commençons par bloquer TOUT le trafic dans le namespace `default` :

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-nothing
  namespace: default
spec:
  {}
EOF
```

> 💡 `spec: {}` (spec vide) signifie "aucune règle d'autorisation" = tout est refusé par défaut. C'est le principe du "deny all, permit by exception".

✅ **Allez dans votre navigateur** à l'URL de Bookinfo → Vous devez voir : **"RBAC: access denied"**

---

### Étape 2 : Autoriser l'accès à la page principale

On autorise les requêtes GET vers `productpage` :

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: "productpage-viewer"
  namespace: default
spec:
  selector:
    matchLabels:
      app: productpage
  action: ALLOW
  rules:
  - to:
    - operation:
        methods: ["GET"]
EOF
```

✅ **Rafraîchissez Bookinfo** → Vous voyez maintenant la page, mais avec des erreurs :
- "Error fetching product details"
- "Error fetching product reviews"

> 💡 Normal ! On a seulement autorisé l'accès à `productpage`. Les autres services (`details`, `reviews`, `ratings`) sont encore bloqués.

---

### Étape 3 : Autoriser `productpage` à accéder à `details`

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: "details-viewer"
  namespace: default
spec:
  selector:
    matchLabels:
      app: details
  action: ALLOW
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/default/sa/bookinfo-productpage"]
    to:
    - operation:
        methods: ["GET"]
EOF
```

> 💡 `principals` est l'identité SPIFFE du service appelant. On dit : "Autorise seulement les requêtes venant du service account `bookinfo-productpage`". C'est du contrôle d'accès basé sur l'identité.

---

### Étape 4 : Autoriser `productpage` à accéder à `reviews`

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: "reviews-viewer"
  namespace: default
spec:
  selector:
    matchLabels:
      app: reviews
  action: ALLOW
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/default/sa/bookinfo-productpage"]
    to:
    - operation:
        methods: ["GET"]
EOF
```

✅ **Rafraîchissez Bookinfo** → Vous voyez maintenant les détails et les reviews, mais dans la section reviews : **"Ratings service currently unavailable"**

---

### Étape 5 : Autoriser `reviews` à accéder à `ratings`

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: "ratings-viewer"
  namespace: default
spec:
  selector:
    matchLabels:
      app: ratings
  action: ALLOW
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/default/sa/bookinfo-reviews"]
    to:
    - operation:
        methods: ["GET"]
EOF
```

✅ **Rafraîchissez Bookinfo** → Vous voyez maintenant les étoiles (noires et rouges) dans les reviews. **L'application fonctionne complètement !**

> 🎯 **Récapitulatif :** On a reconstruit les permissions de zéro, service par service, en respectant le principe du moindre privilège. Chaque service n'a accès qu'à ce dont il a besoin.

### Nettoyage Section A

```bash
kubectl delete authorizationpolicy.security.istio.io/allow-nothing
kubectl delete authorizationpolicy.security.istio.io/productpage-viewer
kubectl delete authorizationpolicy.security.istio.io/details-viewer
kubectl delete authorizationpolicy.security.istio.io/reviews-viewer
kubectl delete authorizationpolicy.security.istio.io/ratings-viewer
```

---

## 🔐 Section B : Autorisation basée sur des tokens JWT

On peut aussi utiliser le contenu d'un token JWT (ses "claims") pour prendre des décisions d'autorisation.

### Préparer l'environnement

```bash
kubectl create ns foo
kubectl apply -f <(istioctl kube-inject -f samples/httpbin/httpbin.yaml) -n foo
kubectl apply -f <(istioctl kube-inject -f samples/curl/curl.yaml) -n foo
```

Vérifiez que `curl` peut atteindre `httpbin` :

```bash
kubectl exec "$(kubectl get pod -l app=curl -n foo -o jsonpath={.items..metadata.name})" \
  -c curl -n foo -- curl http://httpbin.foo:8000/ip -sS -o /dev/null -w "%{http_code}\n"
```

✅ **Attendu :** `200`

---

### Étape 1 : Créer la politique de validation JWT

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: RequestAuthentication
metadata:
  name: "jwt-example"
  namespace: foo
spec:
  selector:
    matchLabels:
      app: httpbin
  jwtRules:
  - issuer: "testing@secure.istio.io"
    jwksUri: "https://raw.githubusercontent.com/istio/istio/release-1.29/security/tools/jwt/samples/jwks.json"
EOF
```

**Testez :**

```bash
# Token invalide → 401
kubectl exec "$(kubectl get pod -l app=curl -n foo -o jsonpath={.items..metadata.name})" \
  -c curl -n foo -- curl "http://httpbin.foo:8000/headers" -sS -o /dev/null \
  -H "Authorization: Bearer tokenInvalide" -w "%{http_code}\n"

# Sans token → 200 (pas encore d'obligation de token)
kubectl exec "$(kubectl get pod -l app=curl -n foo -o jsonpath={.items..metadata.name})" \
  -c curl -n foo -- curl "http://httpbin.foo:8000/headers" -sS -o /dev/null -w "%{http_code}\n"
```

---

### Étape 2 : Exiger un token JWT valide (avec requestPrincipal)

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: require-jwt
  namespace: foo
spec:
  selector:
    matchLabels:
      app: httpbin
  action: ALLOW
  rules:
  - from:
    - source:
       requestPrincipals: ["testing@secure.istio.io/testing@secure.istio.io"]
EOF
```

Récupérons un token de test valide et testons :

```bash
TOKEN=$(curl https://raw.githubusercontent.com/istio/istio/release-1.29/security/tools/jwt/samples/demo.jwt -s)

# Voyons le contenu du token (décodé) :
echo "$TOKEN" | cut -d '.' -f2 - | base64 --decode
```

✅ Vous verrez : `{"iss":"testing@secure.istio.io","sub":"testing@secure.istio.io",...}`

```bash
# Avec token valide → 200
kubectl exec "$(kubectl get pod -l app=curl -n foo -o jsonpath={.items..metadata.name})" \
  -c curl -n foo -- curl "http://httpbin.foo:8000/headers" -sS -o /dev/null \
  -H "Authorization: Bearer $TOKEN" -w "%{http_code}\n"

# Sans token → 403
kubectl exec "$(kubectl get pod -l app=curl -n foo -o jsonpath={.items..metadata.name})" \
  -c curl -n foo -- curl "http://httpbin.foo:8000/headers" -sS -o /dev/null -w "%{http_code}\n"
```

---

### Étape 3 : Exiger un claim spécifique dans le token (groups: group1)

On peut aller encore plus loin : exiger que le token contienne un claim précis.

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: require-jwt
  namespace: foo
spec:
  selector:
    matchLabels:
      app: httpbin
  action: ALLOW
  rules:
  - from:
    - source:
       requestPrincipals: ["testing@secure.istio.io/testing@secure.istio.io"]
    when:
    - key: request.auth.claims[groups]
      values: ["group1"]
EOF
```

Récupérons un token avec le claim `groups: ["group1", "group2"]` :

```bash
TOKEN_GROUP=$(curl https://raw.githubusercontent.com/istio/istio/release-1.29/security/tools/jwt/samples/groups-scope.jwt -s)

# Voyons le contenu :
echo "$TOKEN_GROUP" | cut -d '.' -f2 - | base64 --decode
```

✅ Vous verrez : `{"groups":["group1","group2"],"iss":"testing@secure.istio.io",...}`

```bash
# Token avec group1 → 200
kubectl exec "$(kubectl get pod -l app=curl -n foo -o jsonpath={.items..metadata.name})" \
  -c curl -n foo -- curl "http://httpbin.foo:8000/headers" -sS -o /dev/null \
  -H "Authorization: Bearer $TOKEN_GROUP" -w "%{http_code}\n"

# Token sans group1 (TOKEN normal) → 403
kubectl exec "$(kubectl get pod -l app=curl -n foo -o jsonpath={.items..metadata.name})" \
  -c curl -n foo -- curl "http://httpbin.foo:8000/headers" -sS -o /dev/null \
  -H "Authorization: Bearer $TOKEN" -w "%{http_code}\n"
```

### Nettoyage Section B

```bash
kubectl delete namespace foo
```

---

## 🔐 Section C : Routage basé sur les claims JWT (JWT Claim Based Routing)

Cette fonctionnalité avancée permet de **router les requêtes vers différents backends** selon le contenu du token JWT.

### Préparer l'environnement

```bash
kubectl create ns foo
kubectl apply -f <(istioctl kube-inject -f samples/httpbin/httpbin.yaml) -n foo
kubectl apply -f samples/httpbin/httpbin-gateway.yaml -n foo
```

Récupérez l'URL :

```bash
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
export INGRESS_HOST=$(kubectl get po -l istio=ingressgateway -n istio-system -o jsonpath='{.items[0].status.hostIP}')
curl "$INGRESS_HOST:$INGRESS_PORT/headers" -s -o /dev/null -w "%{http_code}\n"
```

✅ **Attendu :** `200`

---

### Étape 1 : Activer la validation JWT sur l'Ingress Gateway

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: RequestAuthentication
metadata:
  name: ingress-jwt
  namespace: istio-system
spec:
  selector:
    matchLabels:
      istio: ingressgateway
  jwtRules:
  - issuer: "testing@secure.istio.io"
    jwksUri: "https://raw.githubusercontent.com/istio/istio/release-1.29/security/tools/jwt/samples/jwks.json"
EOF
```

---

### Étape 2 : Créer un VirtualService qui route selon le claim JWT

```bash
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: httpbin
  namespace: foo
spec:
  hosts:
  - "*"
  gateways:
  - httpbin-gateway
  http:
  - match:
    - uri:
        prefix: /headers
      headers:
        "@request.auth.claims.groups":
          exact: group1
    route:
    - destination:
        port:
          number: 8000
        host: httpbin
EOF
```

> 💡 Le header spécial `@request.auth.claims.groups` (avec le `@` devant) permet de matcher les claims JWT validés. C'est une syntaxe propre à Istio pour distinguer les claims JWT des headers HTTP ordinaires.

---

### Étape 3 : Tester les différents scénarios

```bash
# 1. Sans JWT → 404 (pas de route correspondante)
curl -s -I "http://$INGRESS_HOST:$INGRESS_PORT/headers"
# HTTP/1.1 404 Not Found

# 2. Avec JWT invalide → 401
curl -s -I "http://$INGRESS_HOST:$INGRESS_PORT/headers" -H "Authorization: Bearer token.invalide.ici"
# HTTP/1.1 401 Unauthorized

# 3. Avec JWT valide contenant groups: group1 → 200
TOKEN_GROUP=$(curl https://raw.githubusercontent.com/istio/istio/release-1.29/security/tools/jwt/samples/groups-scope.jwt -s)
curl -s -I "http://$INGRESS_HOST:$INGRESS_PORT/headers" -H "Authorization: Bearer $TOKEN_GROUP"
# HTTP/1.1 200 OK

# 4. Avec JWT valide mais sans groups: group1 → 404 (la route ne correspond pas)
TOKEN_NO_GROUP=$(curl https://raw.githubusercontent.com/istio/istio/release-1.29/security/tools/jwt/samples/demo.jwt -s)
curl -s -I "http://$INGRESS_HOST:$INGRESS_PORT/headers" -H "Authorization: Bearer $TOKEN_NO_GROUP"
# HTTP/1.1 404 Not Found
```

> 💡 **Analyse des résultats :**
> - Sans JWT → 404 : Aucune route ne correspond (le VirtualService n'a pas de route par défaut pour `/headers`)
> - JWT invalide → 401 : La RequestAuthentication rejette le token avant même d'arriver au routing
> - JWT avec `group1` → 200 : Le claim correspond, la route est sélectionnée
> - JWT valide sans `group1` → 404 : Le token est valide mais le claim ne correspond pas → pas de route

### Nettoyage Section C

```bash
kubectl delete namespace foo
kubectl delete requestauthentication ingress-jwt -n istio-system
```

---

## 🔐 Section D : Refus Explicite (Explicit Deny)

La règle `DENY` a la **priorité absolue** sur toutes les règles `ALLOW`. C'est important pour implémenter des exceptions ou des blocages d'urgence.

### Préparer l'environnement

```bash
kubectl create ns foo
kubectl apply -f <(istioctl kube-inject -f samples/httpbin/httpbin.yaml) -n foo
kubectl apply -f <(istioctl kube-inject -f samples/curl/curl.yaml) -n foo

# Vérification initiale
kubectl exec "$(kubectl get pod -l app=curl -n foo -o jsonpath={.items..metadata.name})" \
  -c curl -n foo -- curl http://httpbin.foo:8000/ip -sS -o /dev/null -w "%{http_code}\n"
```

✅ **Attendu :** `200`

---

### Étape 1 : Refuser toutes les requêtes GET

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: deny-method-get
  namespace: foo
spec:
  selector:
    matchLabels:
      app: httpbin
  action: DENY
  rules:
  - to:
    - operation:
        methods: ["GET"]
EOF
```

```bash
# GET → 403 (refusé)
kubectl exec "$(kubectl get pod -l app=curl -n foo -o jsonpath={.items..metadata.name})" \
  -c curl -n foo -- curl "http://httpbin.foo:8000/get" -X GET -sS -o /dev/null -w "%{http_code}\n"

# POST → 200 (autorisé car pas de règle DENY pour POST)
kubectl exec "$(kubectl get pod -l app=curl -n foo -o jsonpath={.items..metadata.name})" \
  -c curl -n foo -- curl "http://httpbin.foo:8000/post" -X POST -sS -o /dev/null -w "%{http_code}\n"
```

---

### Étape 2 : Affiner — Refuser GET sauf pour les admins

On ne refuse GET que si le header `x-token` n'est pas `admin` :

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: deny-method-get
  namespace: foo
spec:
  selector:
    matchLabels:
      app: httpbin
  action: DENY
  rules:
  - to:
    - operation:
        methods: ["GET"]
    when:
    - key: request.headers[x-token]
      notValues: ["admin"]
EOF
```

```bash
# GET avec x-token: admin → 200 (autorisé, la condition DENY ne s'applique pas)
kubectl exec "$(kubectl get pod -l app=curl -n foo -o jsonpath={.items..metadata.name})" \
  -c curl -n foo -- curl "http://httpbin.foo:8000/get" -X GET \
  -H "x-token: admin" -sS -o /dev/null -w "%{http_code}\n"

# GET avec x-token: guest → 403 (refusé, guest n'est pas admin)
kubectl exec "$(kubectl get pod -l app=curl -n foo -o jsonpath={.items..metadata.name})" \
  -c curl -n foo -- curl "http://httpbin.foo:8000/get" -X GET \
  -H "x-token: guest" -sS -o /dev/null -w "%{http_code}\n"
```

---

### Étape 3 : Démontrer la priorité DENY sur ALLOW

Ajoutons une règle ALLOW pour le chemin `/ip`, puis vérifions que DENY gagne quand même :

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-path-ip
  namespace: foo
spec:
  selector:
    matchLabels:
      app: httpbin
  action: ALLOW
  rules:
  - to:
    - operation:
        paths: ["/ip"]
EOF
```

```bash
# GET /ip avec x-token: guest → 403 (DENY gagne sur ALLOW !)
kubectl exec "$(kubectl get pod -l app=curl -n foo -o jsonpath={.items..metadata.name})" \
  -c curl -n foo -- curl "http://httpbin.foo:8000/ip" -X GET \
  -H "x-token: guest" -s -o /dev/null -w "%{http_code}\n"

# GET /ip avec x-token: admin → 200 (DENY ne s'applique pas pour admin, ALLOW s'applique)
kubectl exec "$(kubectl get pod -l app=curl -n foo -o jsonpath={.items..metadata.name})" \
  -c curl -n foo -- curl "http://httpbin.foo:8000/ip" -X GET \
  -H "x-token: admin" -s -o /dev/null -w "%{http_code}\n"

# GET /get avec x-token: admin → 403 (ALLOW ne couvre que /ip, pas /get)
kubectl exec "$(kubectl get pod -l app=curl -n foo -o jsonpath={.items..metadata.name})" \
  -c curl -n foo -- curl "http://httpbin.foo:8000/get" -X GET \
  -H "x-token: admin" -s -o /dev/null -w "%{http_code}\n"
```

> 🎯 **Récapitulatif sur la priorité :**
> 1. Si une règle `DENY` matche → **toujours refusé** (même si une règle ALLOW matche aussi)
> 2. Si une règle `ALLOW` matche (et aucun DENY) → autorisé
> 3. Si aucune règle ne matche → refusé par défaut (si des politiques existent dans le namespace)

### Nettoyage Final

```bash
kubectl delete namespace foo
```

---

---

# 📋 Récapitulatif des Concepts Appris

| Concept | Ressource Kubernetes | Usage |
|---|---|---|
| Certificats personnalisés | Secret `cacerts` | Remplacer les certificats auto-signés d'Istio |
| mTLS entre services | `PeerAuthentication` | Chiffrer et authentifier les communications inter-services |
| Authentification JWT | `RequestAuthentication` | Valider les tokens des utilisateurs finaux |
| Autorisation ALLOW | `AuthorizationPolicy (ALLOW)` | Définir qui peut faire quoi |
| Autorisation DENY | `AuthorizationPolicy (DENY)Étape 3 : mTLS automatique — la preuve avec les headers` | Bloquer explicitement (priorité absolue) |
| Routage par JWT | `VirtualService` + `RequestAuthentication` | Router selon le contenu du token |

---

# 🆘 Dépannage Courant sur Killercoda

| Problème | Solution |
|---|---|
| Les pods restent en `Pending` | `kubectl describe pod <nom> -n <namespace>` pour voir les erreurs |
| Erreur `istioctl: command not found` | `export PATH=$HOME/.istioctl/bin:$PATH` |
| `403` inattendu | Vérifiez les AuthorizationPolicies : `kubectl get authorizationpolicy --all-namespaces` |
| `000` / connexion refusée | Le service n'a peut-être pas de sidecar, ou mTLS est strict |
| Token JWT expiré | Récupérez un nouveau token depuis GitHub avec la commande `curl` fournie |
| Environnement Killercoda expiré | Les sessions Killercoda durent 1h. Recommencez depuis la Partie 0 |

---

*Lab réalisé dans le cadre de la Formation Istio — Séance 2 : Sécurité*
*Basé sur la documentation officielle Istio : https://istio.io/latest/docs/tasks/security/*
