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

Les six tables de la ressource sont créées et mises à jour automatiquement au démarrage via oxmysql. Aucun import SQL manuel n’est nécessaire. Le compte MySQL doit pouvoir créer et modifier les tables dans la base ESX configurée pour oxmysql.

## Utilisation

Le staff ouvre `/egarage` pour créer et configurer les garages : métier, entrée, sorties, rangements et accès par marqueur ou PNJ. Les droits staff sont définis par `Config.AdminGroups` ou `Config.AdminAce`.

Les employés utilisent l’entrée de leur garage. Leur métier doit correspondre à celui du garage. Les responsables autorisés peuvent gérer la flotte, les catégories et les permissions, sans modifier les emplacements.

Les permissions du garage et de la catégorie se cumulent. Une liste d’accès autorise les grades exacts sélectionnés ou les employés désignés. Les clés sont attribuées aux employés autorisés et révoquées au rangement ou à la perte d’accès.

Pour importer un véhicule, se placer au volant près du garage. Sa plaque et son modèle doivent correspondre à un véhicule possédé par la société dans `owned_vehicles`. Une plaque appartient à un seul garage. Le rangement s’effectue au volant, dans un point de rangement du même garage.

## Configuration

- `Config.SocietyOwnerFormats` : formats du propriétaire société dans `owned_vehicles`.
- `Config.DefaultPermissions` : grades requis pour chaque action.
- `Config.PedModelsAllowed` : modèles de PNJ autorisés.
- `Config.SyncOwnedVehicleStored` : synchronisation de `owned_vehicles.stored`. Mettre `false` si cette colonne n’existe pas dans votre schéma.

Les autres ressources de garage doivent exclure les plaques gérées par cette flotte.
