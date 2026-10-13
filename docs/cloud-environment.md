# Environnement cloud de développement

Utiliser le checkout existant `/workspace/ncompagny-garage`. Chaque tâche cloud est déjà isolée ; créer un Git worktree uniquement sur demande explicite. Lire les éventuels `AGENTS.md` et préserver les changements locaux avant toute intervention.

## Installation réutilisable

```sh
cd /workspace/ncompagny-garage
bash scripts/cloud-install.sh
source /workspace/cloud-setup/env.sh
```

Le script prépare Lua 5.4.7, PyMySQL 1.1.2, Bun 1.3.14 et une image MariaDB 11.4 fixée par son empreinte. Il suppose que Node.js, Python avec Playwright, Chromium, GCC/make et Docker sont déjà fournis par l’image cloud. Il compile Lua avec des options portables et réutilise les sorties valides. Les installations respectent TLS, les sommes de contrôle des gestionnaires de paquets et le lockfile figé d’oxmysql.

Les dépendances et caches restent sous `/workspace/cloud-setup`. Le script n’altère pas les sources ou lockfiles du dépôt applicatif. Il prépare les checkouts publics suivants comme dépendances :

| Dépendance | Commit fixé |
| --- | --- |
| ESX core | `338ba0f45c197e8cb04b264b4c6a93124706f7aa` |
| oxmysql | `bae715c244d7ef8136a025c8a35ced3daff51738` |
| cfx-server-data | `c6afa3909c763e3327ed76825e78453286c99f05` |

ESX, esx_lib, oxmysql et le dépôt sont liés dans `fivem/server-data/resources/[local]`. Ces caches ne constituent pas de nouveaux projets utilisateur.

## Démarrage

Les fichiers et dépendances peuvent être conservés par une publication de l’environnement ; les processus doivent être redémarrés. Dans chaque nouveau shell, activer les outils avec `source /workspace/cloud-setup/env.sh`.

Pour démarrer MariaDB et préparer le schéma applicatif local :

```sh
bash /workspace/cloud-setup/start-db.sh
docker exec -i aegis-dev-db mariadb --user=root aegis_dev < sql/install.sql
```

Le helper vérifie le label `aegis.cloud-setup=true`, l’image du conteneur et la réponse à `SELECT 1`. La base de test écoute sur `127.0.0.1:3307`. Le compte root sans mot de passe est réservé à ce conteneur local de développement. Ne pas appliquer ces paramètres à une base de production. L’import SQL est répétable et crée les sept tables applicatives.

Pour démarrer le preview interactif depuis la racine du dépôt :

```sh
python3 -m http.server 8080 --bind 127.0.0.1 --directory web
```

Si le port est occupé, identifier le service et le réutiliser ou choisir un port libre. Ne pas arrêter un processus inconnu. Le preview utilise des données fictives et le stockage local du navigateur ; aucune écriture MySQL ou requête NUI n’y est effectuée. Il est toujours désactivé dans FiveM. Voir le [README](../README.md#preview-interactif) pour les commandes de démonstration.

## Validation

```sh
source /workspace/cloud-setup/env.sh
lua -e 'for _,p in ipairs({"fxmanifest.lua","shared/config.lua","server/database.lua","server/bridge.lua","server/main.lua","client/properties.lua","client/main.lua"}) do assert(loadfile(p),p) end'
node --check web/app.js
node --check web/preview.js
python3 tests/server_test.py
python3 tests/preview_test.py
git -c core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol diff --check
```

Les contrôles de référence ont passé **54 assertions Lua/MariaDB** et **8 tests navigateur**. Les tests serveur utilisent les vrais callbacks Lua, des natives FiveM de test et une base MariaDB au nom aléatoire créée puis supprimée par le runner. Ils vérifient notamment le schéma ESX documenté par okokGarage, la réservation et le retour, les propriétés RGB et indices zéro, les droits, la révocation des clés source, les conflits et les annulations SQL. Ces contrôles ne constituent pas une validation en jeu.

Le dépôt existant utilise CRLF ; conserver ses fins de ligne. Un sandbox réseau peut aussi bloquer les sockets locales des tests : utiliser le mécanisme d’autorisation de l’outil d’exécution si nécessaire, sans modifier le proxy ou contourner la politique réseau.

## Prérequis FiveM restants

FXServer, une clé serveur valide et les ressources Wasabi Carlock avec leurs dépendances sont nécessaires aux essais en jeu. ESX et oxmysql sont préparés, mais aucun démarrage FiveM n’a été validé. L’artefact FXServer choisi doit respecter le minimum effectif des dépendances : la version d’oxmysql préparée demande au moins le serveur 12913.

L’ordre de démarrage inclut OneSync, oxmysql, esx_lib, es_extended, les dépendances Wasabi, wasabi_carlock puis aegis_enterprise_garages. ox_target est facultatif pour les accès par PNJ. La base ESX réelle doit fournir `owned_vehicles` avec `owner`, `plate` et `vehicle` ; la passerelle exige InnoDB.

Les destinations réseau nécessaires à cette préparation sont :

- `github.com`, `raw.githubusercontent.com` et les domaines des gestionnaires de paquets configurés par l’environnement ;
- `runtime.fivem.net`, `keymaster.fivem.net` ;
- `docs.okokscripts.io`, `docs.wasabiscripts.com`, `docs.fivem.net`, `docs.esx-framework.org`, `overextended.dev`.

Conserver les règles réseau existantes lors de l’ajout de ces domaines. Dans l’environnement d’onboarding, les exigences réseau et `FIVEM_LICENSE_KEY` sont enregistrées dans le brouillon ; elles ne prouvent pas leur application au runtime. Saisir la clé dans les paramètres sécurisés, jamais dans le dépôt, les logs ou le chat. La documentation ne remplace pas les credentials ou les fichiers de ressources manquants.

Les instructions d’installation et de démarrage sont aussi enregistrées dans la configuration cloud. Réviser et enregistrer cette configuration puis publier l’environnement pour activer une nouvelle version. Un push GitHub ne publie pas à lui seul cette configuration ni un snapshot cloud.
