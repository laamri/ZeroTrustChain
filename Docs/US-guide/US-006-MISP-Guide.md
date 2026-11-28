# US-006 — Guide de déploiement des instances MISP A et B

**Projet : ZeroTrustChain | Sprint 1 | Épic EPIC-08**  
**État au 28 novembre 2026 :** MISP A opérationnel, persistance après redémarrage confirmée par l'opérateur ; MISP B et tests inter-nœuds à réaliser. Ce guide distingue les résultats obtenus des procédures proposées.

## 1. Objectif et périmètre

Installer deux instances MISP indépendantes pour simuler deux organisations de Threat Intelligence. Chaque instance possède sa base MariaDB, son cache, ses volumes, ses comptes et ses secrets. Aucune synchronisation directe entre les instances ne doit être configurée. Le connecteur Python et le mécanisme d'échange contrôlé sont hors périmètre. Le corpus de référence est fourni par US-004 ; le dépôt initial dépend de US-002.

## 2. Architecture et prérequis

```text
PC A                              PC B
MISP A                            MISP B
NGINX -> Core                     NGINX -> Core
         |-- MariaDB A                     |-- MariaDB B
         |-- Valkey A                      |-- Valkey B
         |-- Modules / SMTP                |-- Modules / SMTP
         |-- Volumes A                     |-- Volumes B
          \________ VPN privé ____________/
                 (à configurer)
```

Une seule pile par PC afin de répartir les ressources. Docker Desktop avec moteur Linux/WSL2, Git, PowerShell et accès à GHCR sont nécessaires. Environnement A observé : Docker 29.2.1, Compose 5.0.2, 4 CPU et 9,714 GiB alloués à Docker. La consommation réelle reste à mesurer. Les deux PC peuvent utiliser les mêmes ports 8080 et 8443.

| Service | Image / tag validé sur A |
|---|---|
| misp-core | ghcr.io/misp/misp-docker/misp-core:v2.5.53 |
| misp-nginx | ghcr.io/misp/misp-docker/misp-nginx:v2.5.53 |
| misp-modules | ghcr.io/misp/misp-docker/misp-modules:v3.1.6 |
| db | ghcr.io/mariadb/mariadb:10.11 |
| redis | ghcr.io/valkey-io/valkey:7.2 |
| mail | ghcr.io/egos-tech/smtp:2.0.12 |

MISP Guard reste désactivé. Les tags MariaDB et Valkey peuvent évoluer : enregistrer les digests pour figer les images exactes. Source : https://github.com/MISP/misp-docker ; conserver LICENSE et UPSTREAM_VERSION.txt.

## 3. Organisation du dépôt

```text
Docs/US-006-MISP-Guide.md
infra/misp/
  .gitignore
  LICENSE
  UPSTREAM_VERSION.txt
  README.md
  init-misp.ps1
  misp-a/docker-compose.yml
  misp-a/template.env
  misp-b/docker-compose.yml
  misp-b/template.env
  evidence/
```

Les fichiers .env, ssl/key.pem, configs, logs, files, gnupg et autres données locales ne doivent pas être versionnés. Vérifier aussi les fichiers déjà suivis par Git (un .gitignore ne les retire pas). Le script crée les secrets sur chaque PC ; ne jamais copier ceux de A vers B.

## 4. Préparation avant partage (responsable US-006)

Depuis la racine, vérifier dans le Compose A le `start_period: 15m` du service misp-core, les deux bindings NGINX ci-dessous et l'absence de ports publiés pour MariaDB et Valkey.

```yaml
ports:
  - "${MISP_BIND_IP:-127.0.0.1}:${NGINX_HTTP_PORT:-8080}:8080"
  - "${MISP_BIND_IP:-127.0.0.1}:${NGINX_HTTPS_PORT:-8443}:8443"
```

Rendre obligatoires les interpolations Compose ADMIN_PASSWORD, MYSQL_PASSWORD, MYSQL_ROOT_PASSWORD, REDIS_PASSWORD, GPG_PASSPHRASE et SUPERVISOR_PASSWORD dans les services concernés (syntaxe `${VARIABLE:?VARIABLE is required}`). Ne pas remplacer les expressions shell échappées `$${...}`. Vérifier les variables de synchronisation désactivées. Copier ensuite uniquement le YAML corrigé :

```powershell
Copy-Item infra/misp/misp-a/docker-compose.yml infra/misp/misp-b/docker-compose.yml -Force
Get-FileHash infra/misp/misp-a/docker-compose.yml,infra/misp/misp-b/docker-compose.yml
```

Les empreintes doivent être identiques. Au moment de la revue GitHub de scrum-18, B avait encore 60s, des bindings ouverts et des mots de passe par défaut ; A conservait certains fallbacks côté DB/cache. Les modifications locales ultérieures doivent être vérifiées avant le push.

## 5. Installation sur un nouveau PC (B)

Récupérer la branche contenant les modifications validées ; ne pas supposer qu'elles sont déjà intégrées à main/develop.

```powershell
git pull --ff-only
docker --version
docker compose version
docker info
Get-NetTCPConnection -State Listen -LocalPort 8080,8443 -ErrorAction SilentlyContinue
```

Aucun résultat pour les deux ports signifie qu'aucun listener TCP n'a été trouvé. Adapter les ports et BASE_URL si nécessaire.

Depuis la racine du dépôt :

```powershell
powershell -NoProfile -File infra/misp/init-misp.ps1 -Instance B
cd infra/misp/misp-b
docker compose config --quiet
docker compose config --services
docker compose config --images
docker compose pull
docker compose up -d --no-build --pull never
```

Le script proposé initialise un nouveau .env et un certificat RSA 2048 local valable 365 jours, avec SAN localhost et 127.0.0.1. Il refuse d'écraser une configuration existante. Il nécessite Docker et un accès réseau pour Alpine/OpenSSL. Il n'a pas été exécuté sur le PC B ; vérifier sa sortie. En cas d'échec partiel, examiner les fichiers créés avant de recommencer. Ne pas lancer sur A déjà installé.

Configuration attendue de B : COMPOSE_PROJECT_NAME=misp-b, ADMIN_EMAIL=admin@orgb.test, ADMIN_ORG=Organization-B, MYSQL_USER et MYSQL_DATABASE=misp_b, BASE_URL=https://localhost:8443. Secrets distincts générés localement. Pour une installation manuelle, copier template.env vers .env, appliquer ces paramètres, renseigner des secrets aléatoires uniques et générer ssl/cert.pem et ssl/key.pem avant de lancer Compose. Ne pas imprimer le .env.

## 6. Vérifications et première connexion

```powershell
docker compose ps -a
docker compose logs --tail 50 misp-core
docker volume ls --filter label=com.docker.compose.project=misp-b
docker network ls --filter label=com.docker.compose.project=misp-b
docker stats --no-stream $(docker compose ps -q)
```

Attendre les services healthy (mail peut simplement être running). Examiner et expurger les logs avant partage. Ouvrir https://localhost:8443 ; vérifier le certificat présenté avant de lui faire confiance. Le certificat auto-signé explique NET::ERR_CERT_AUTHORITY_INVALID ; ne pas désactiver la vérification TLS. Une AC privée de laboratoire sera préférable pour les échanges VPN. Se connecter avec ADMIN_EMAIL et ADMIN_PASSWORD du .env local. Modifier le mot de passe si demandé, sans régénérer les secrets DB après initialisation.

## 7. Incident résolu sur A

Le premier démarrage a pris environ 13 minutes selon l'opérateur : copies de fichiers via les montages Windows, permissions et initialisation des données. La période initiale de 60 s était insuffisante ; Core était unhealthy et NGINX ne démarrait pas normalement. Correction : `healthcheck.start_period: 15m` dans misp-core, sans supprimer le contrôle de santé. Un succès anticipé du health check permet de démarrer plus tôt. Les avertissements sur OIDC, LDAP, SES ou options de build non renseignées ne sont pas tous fatals ; vérifier le code retour et les fonctionnalités réellement nécessaires. Ne pas masquer les erreurs.

Résultat A rapporté : Core et NGINX healthy, login HTTP 200, ports liés à 127.0.0.1. Après restart, les six services sont Up, cinq healthy et mail Up. Volumes listés : misp-a_mysql_data, misp-a_cache_data, misp-a_misp_guard_ca. La présence du volume Guard ne prouve pas que le service Guard est actif.

## 8. Test de persistance et isolation

Sur A, l'événement `US-006 - Organization A Persistence Test` (ID 1), privé à Organization-A, non publié, contient l'attribut ip-dst `203.0.113.10` (adresse de documentation). L'opérateur confirme sa présence après `docker compose restart`. La capture initiale montre un avertissement de vue obsolète : actualiser pour confirmer les attributs.

Sur B, créer un événement privé distinct `US-006 - Organization B Local Test`, attribut domain `org-b.example.test`. Noter UUID et attributs avant et après `docker compose restart`. Vérifier que l'événement A est absent de B et inversement, y compris après connexion VPN, sans import ni synchronisation. Conserver preuves expurgées et UUID. Test renforcé facultatif : `docker compose down` puis `docker compose up -d --no-build --pull never`. Ne jamais utiliser `down -v` pour tester la persistance.

## 9. VPN et TLS (à réaliser)

Autoriser les deux nœuds dans un réseau ZeroTier privé. Identifier les IP VPN avec Get-NetIPAddress -AddressFamily IPv4. Sur chaque PC, modifier MISP_BIND_IP avec sa propre IP VPN et BASE_URL=https://IP_VPN:8443. Restreindre Windows Firewall et règles VPN aux pairs autorisés ; ne pas publier DB, Redis ni autres services internes. Vérifier le support du binding sur Docker Desktop. Générer un certificat avec SAN correspondant à l'IP VPN ou au DNS choisi et établir la confiance côté client. Recréer les services avec `docker compose up -d --no-build --pull never` après modification. Tester `Test-NetConnection IP_VPN_DISTANTE -Port 8443`, puis HTTPS avec validation TLS. Tester aussi un accès non autorisé. Ne pas exposer MISP à Internet. Aucune synchronisation MISP directe.

## 10. Clés API (à réaliser)

Créer un compte de service par instance, avec le rôle minimal nécessaire et autorisation API. Dans l'interface MISP, accéder aux Auth Keys du compte, générer une clé distincte, limiter sa durée et ses droits (lecture seule si suffisante) et éventuellement les IP autorisées. Stocker dans un gestionnaire de secrets ou un fichier local ignoré par Git avec accès restreint. Ne jamais inclure les clés dans les commandes partagées, captures ou logs. Vérifier un appel de lecture avec clé autorisée et un refus avec clé absente/invalide. Le connecteur applicatif reste hors périmètre.

## 11. Tests négatifs (à réaliser)

Secret absent : utiliser une copie temporaire ignorée du .env dans le même dossier, retirer MYSQL_PASSWORD de la copie et vérifier qu'aucune variable shell du même nom n'est définie. Lancer `docker compose --env-file .env.test config --quiet` ; attendre un code non nul et le nom du paramètre manquant, jamais sa valeur. Supprimer la copie temporaire. Ne pas démarrer cette configuration.

Erreur DB : sur une pile de test jetable, modifier uniquement la connexion du Core vers un hôte inexistant (ou un mot de passe incorrect côté Core), sans changer les secrets de la base persistante. Vérifier l'échec de connexion et le diagnostic expurgé, rétablir le paramètre puis vérifier la santé. Ne pas détruire les volumes du laboratoire principal.

## 12. Corpus US-004 (en attente)

Récupérer le corpus synthétique A et le script approuvés par l'équipe, exécuter le script contre A avec une clé autorisée, vérifier le nombre et les UUID des événements. B conserve son événement local distinct. Documenter ici la commande réelle et sa version lorsque US-004 est livré ; ne pas inventer un chemin de script. L'événement temporaire ne remplace pas le corpus.

## 13. Preuves et livraison

| Critère | État |
|---|---|
| CA1 — absence de visibilité A dans B | À tester après B |
| CA2 — persistance après redémarrage | A confirmé par l'opérateur ; B à tester |
| CA3 — diagnostic DB / secret absent | À tester |
| CA4 — guide, URL, ressources, chargement corpus | Guide et URL disponibles ; mesures et commande corpus en attente |

Collecter dans infra/misp/evidence les états des conteneurs, volumes, mesures CPU/RAM, preuves de persistance et isolation, tests négatifs et import du corpus. Ne pas publier de données sensibles. Faire relire par un autre membre avant clôture Jira. Vérifier `git status --short`, `git diff --cached --stat` et les fichiers suivis avant commit. Ne pas pousser .env, clés privées ni données runtime. Le guide et le script proposés doivent être revus et testés par le collègue avant de déclarer la reproductibilité validée.
