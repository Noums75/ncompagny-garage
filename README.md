# AEGIS Enterprise Garages

Garages d’entreprise pour FiveM et ESX Legacy : flotte de véhicules, catégories, permissions par grade ou employé et clés Wasabi Carlock.

## Dépendances

- OneSync
- `es_extended`
- `oxmysql`
- `wasabi_carlock` et ses dépendances
- `ox_target` pour les accès par PNJ (facultatif)

## Installation

1. Placer le dossier `aegis_enterprise_garages` dans les ressources du serveur.
2. Ajuster `shared/config.lua` : groupes staff, propriétaire société, permissions et distances.
3. Ajouter au `server.cfg` :

```cfg
set onesync on
ensure oxmysql
ensure es_extended
ensure wasabi_carlock
ensure aegis_enterprise_garages

add_ace group.admin enterprise_garage.admin allow
```

Démarrer les dépendances de Wasabi avant `wasabi_carlock`. Pour les accès par PNJ, démarrer aussi `ox_target` avant le garage.

Les sept tables de la ressource sont créées et mises à jour automatiquement au démarrage via oxmysql. Aucun import SQL manuel n’est nécessaire. Le compte MySQL doit pouvoir créer et modifier les tables dans la base ESX configurée pour oxmysql, ainsi que lire, insérer et supprimer des lignes dans `owned_vehicles` pour la passerelle.

## Utilisation

Le staff ouvre `/egarage` pour créer et configurer les garages : métier, entrée, sorties, rangements et accès par marqueur ou PNJ. Les droits staff sont définis par `Config.AdminGroups` ou `Config.AdminAce`.

Les employés utilisent l’entrée de leur garage. Leur métier doit correspondre à celui du garage. Les responsables autorisés peuvent gérer la flotte, les catégories et les permissions, sans modifier les emplacements.

Les permissions du garage et de la catégorie se cumulent. Une liste d’accès autorise les grades exacts sélectionnés ou les employés désignés. Les clés sont attribuées aux employés autorisés et révoquées au rangement ou à la perte d’accès.

Pour importer un véhicule, se placer au volant près du garage. Sa plaque et son modèle doivent correspondre à un véhicule possédé par la société, ou par le conducteur si les transferts personnels sont autorisés. Une plaque appartient à un seul garage. Le rangement s’effectue au volant, dans un point de rangement du même garage.

## Configuration

- `Config.SocietyOwnerFormats` : formats du propriétaire société dans `owned_vehicles`.
- `Config.DefaultPermissions` : grades requis pour chaque action.
- `Config.PedModelsAllowed` : modèles de PNJ autorisés.
- `Config.SyncOwnedVehicleStored` : synchronisation de `owned_vehicles.stored`. Mettre `false` si cette colonne n’existe pas dans votre schéma.

Les autres ressources de garage doivent exclure les plaques gérées par cette flotte.

## Passerelle okokGarage (ESX)

La passerelle est activée par défaut. Sortez un véhicule depuis okokGarage, conduisez-le jusqu’à un point de rangement du garage d’entreprise et utilisez **Ranger mon véhicule** (ou la touche de rangement en jeu). Si sa plaque n’est pas encore dans la flotte, la ressource vérifie la propriété, le modèle observé côté serveur, les droits `store` **et** `fleet_add`, la capacité et l’absence de doublon. L’import manuel permet aussi de choisir un nom et une catégorie.

Le véhicule est enregistré dans `aegis_enterprise_fleet` avec sa plaque normalisée, son modèle, sa personnalisation, son carburant, ses dégâts et son état de rangement. La ligne complète d’origine est sauvegardée dans `aegis_enterprise_vehicle_bridges.original_record`, puis retirée temporairement d’`owned_vehicles` dans la même transaction SQL. Les colonnes sont détectées automatiquement : propriétaire, `parking`, `garage`, fourrière et champs personnalisés restent dans la sauvegarde. Aucune colonne propre à une version d’okokGarage n’est supposée.

Ainsi, un okokGarage ESX qui relit `owned_vehicles` ne propose plus de seconde sortie du véhicule transféré. Les autres ressources qui recherchent sa propriété dans cette table ne le verront pas pendant son affectation à la flotte. **Retirer de la flotte**, ou supprimer un garage dont les véhicules sont tous rangés, restaure la ligne d’origine avec les propriétés à jour et `stored = 1` si cette colonne existe. Une erreur SQL ou un conflit de plaque annule le retour et conserve la sauvegarde. Ne supprimez pas la table de passerelle tant que des véhicules y sont réservés.

Le transfert d’un véhicule personnel le rend accessible aux employés autorisés de la flotte, sans changer son propriétaire d’origine. Pour limiter les transferts aux véhicules de société, utilisez `Config.OkokGarageBridge.AllowEmployeeOwnedVehicles = false`. `AutoImportOnStore = false` impose l’import manuel ; `Enabled = false` désactive les nouveaux transferts mais laisse possible le retour des véhicules déjà transférés.

Lors du transfert, `RevokeSourceKeys = true` déclenche l’événement serveur documenté `okokGarage:RemoveKeys` avec la plaque et l’identifiant de chaque joueur connecté, si la ressource source est démarrée. `ResourceName` doit correspondre au dossier de la ressource et `EventPrefix` à son `Config.EventPrefix`. La gestion des clés de la flotte reste assurée par Wasabi. Pour un serveur utilisant Wasabi comme système de clés commun, la configuration officielle okokGarage propose `Config.UseOkokVehicleKeys = false` afin de désactiver ses propres clés ; l’intégration Wasabi des véhicules hors flotte doit être configurée dans cette ressource. Les clés d’inventaire de joueurs hors ligne et les variantes utilisant un cache nécessitent une vérification sur la version réelle.

Les tests reproduisent les dix colonnes supplémentaires de la documentation ESX okokGarage : `parking`, `doorcondition`, `windowcondition`, `tyrecondition`, `favourite`, `impoundTime`, `location`, `reason`, `sharedwith`, `vehiclename`. Elles sont archivées et restituées dans leur format d’origine ; les propriétés ESX actuelles du véhicule sont enregistrées dans `props`, puis dans `owned_vehicles.vehicle` au retour. La passerelle conserve aussi les couleurs RGB et les propriétés de roues/vitres indexées à partir de zéro de la personnalisation ESX documentée. Les indices numériques sont rétablis côté client après le passage par JSON. Il n’est pas nécessaire de remplacer les fonctions de votre framework depuis cette ressource.

La compatibilité vise le stockage ESX commun `owned_vehicles` (`owner`, `plate`, `vehicle`). Pour une version utilisant un cache ou une autre table, ajoutez ce contrôle **côté serveur**, avant tout spawn, rangement ou récupération dans cette ressource :

```lua
if exports['aegis_enterprise_garages']:IsManagedPlate(plate) then
    -- Refuser l’opération : cette plaque est gérée par la flotte.
    return
end
```

Adaptez le nom de la ressource si vous l’avez renommée. Le compte SQL doit consulter `information_schema.COLUMNS` et les tables concernées doivent utiliser InnoDB pour garantir les transactions. L’intégration en jeu doit être vérifiée avec votre version réelle d’okokGarage, ESX, oxmysql et Wasabi Carlock.

### Références officielles vérifiées

- [Installation et API okokGarage](https://docs.okokscripts.io/scripts/okokgarage) : schéma ESX, événement serveur `RemoveKeys`, version minimale des artefacts 5181.
- [Configuration okokGarage](https://docs.okokscripts.io/scripts/okokgarage/config-file) : préfixe d’événements, clés, récupération de véhicules déjà présents, fourrière après suppression et réinitialisation des états au démarrage. Ces mécanismes motivent la réservation dans une table séparée plutôt qu’un simple changement de `stored`.
- [Couleurs RGB et propriétés ESX](https://docs.okokscripts.io/scripts/okokgarage/rgb-vehicle-colors) : couleurs `{r, g, b}`, état des pneus, vitres et portes, dont les indices commencent à zéro.
- [Métadonnées de clés d’inventaire](https://docs.okokscripts.io/scripts/okokgarage/inventories-metadata) : export `okokGarage.lockvehicle` pour les clés ox_inventory. Ce système est distinct des clés Wasabi de la flotte.
- [Installation FiveM, source officielle](https://github.com/citizenfx/fivem-docs/blob/master/content/docs/server-manual/setting-up-a-server-vanilla.md) : artefact officiel, dossier de données séparé, `server.cfg` et clé `sv_licenseKey`. Le minimum effectif doit aussi respecter les dépendances installées ; oxmysql préparé dans l’environnement demande un serveur au moins 12913.
- [Propriétés ESX, source officielle préparée](https://github.com/esx-framework/esx_core/blob/338ba0f45c197e8cb04b264b4c6a93124706f7aa/%5Bcore%5D/esx_lib/imports/game/client.lua) et [API oxmysql préparée](https://github.com/overextended/oxmysql/blob/bae715c244d7ef8136a025c8a35ced3daff51738/lib/MySQL.lua) : capture/restitution des propriétés, `MySQL.ready.await()` et transactions utilisées.

Les pages okokGarage ont été consultées directement. FiveM, ESX et oxmysql ont aussi été vérifiés dans leurs sources officielles GitHub. L’accès au site de documentation Wasabi reste refusé par le proxy de cet environnement : ses exports et sa configuration devront être confirmés quand cet accès et la ressource seront disponibles. La documentation ne fournit pas la clé de licence FiveM ni les fichiers d’une ressource Wasabi sous licence.

## Preview interactif

Depuis la racine du dépôt, servez le dossier `web`, puis ouvrez l’interface servie dans votre navigateur :

```sh
python3 -m http.server 8080 --bind 127.0.0.1 --directory web
```

Hors FiveM, le mode démonstration s’active automatiquement. Il présente les garages, la flotte, les filtres, les catégories, les permissions par grade et employé, les points, la création et la suppression. Les imports okokGarage, sorties, rangements, récupérations, renommages et retours au garage d’origine sont simulés. La barre supérieure permet de choisir le rôle (staff, responsable, employé), le véhicule au volant, de rouvrir l’interface ou de réinitialiser les données.

Les modifications de démonstration restent dans le stockage local du navigateur. Elles ne font aucune requête vers FiveM et n’écrivent pas dans MySQL. `?preview=0` désactive la démonstration dans un navigateur ; sous FiveM elle est toujours désactivée et les callbacks NUI réels restent utilisés.

## Vérifications de développement

La préparation réutilisable de l’environnement est décrite dans [docs/cloud-environment.md](docs/cloud-environment.md), avec le script [scripts/cloud-install.sh](scripts/cloud-install.sh).

Avec Lua 5.4, Python, PyMySQL, Playwright/Chromium et une base MariaDB de test :

```sh
python3 tests/preview_test.py
LUA=lua MYSQL_HOST=127.0.0.1 MYSQL_PORT=3307 python3 tests/server_test.py
```

Le test serveur crée une base au nom aléatoire et la supprime après exécution. Il exécute les vrais callbacks Lua avec des natives FiveM de test et des transactions MariaDB réelles. Les tests couvrent les transferts et retours, la conservation des colonnes personnalisées et des propriétés, les permissions, les modèles non conformes, les doublons, les erreurs de suppression physique, les conflits de propriété et les annulations SQL. Les tests navigateur couvrent les écrans et actions de démonstration, sa persistance, les rôles, le mobile et sa désactivation sous FiveM. Ils ne remplacent pas une validation en jeu.
