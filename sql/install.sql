CREATE TABLE IF NOT EXISTS `aegis_enterprise_garages` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(60) NOT NULL,
  `job` VARCHAR(60) NOT NULL,
  `entrance` LONGTEXT NOT NULL,
  `spawn` LONGTEXT NOT NULL,
  `permissions` LONGTEXT NOT NULL,
  `interaction` LONGTEXT NULL,
  `created_by` VARCHAR(90) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX `idx_garage_job` (`job`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `aegis_enterprise_fleet` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `garage_id` INT UNSIGNED NOT NULL,
  `plate` VARCHAR(8) NOT NULL,
  `model` VARCHAR(60) NOT NULL,
  `vehicle_type` VARCHAR(20) NOT NULL DEFAULT 'automobile',
  `label` VARCHAR(60) NOT NULL,
  `props` LONGTEXT NULL,
  `stored` TINYINT(1) NOT NULL DEFAULT 1,
  `net_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_fleet_plate` (`plate`),
  INDEX `idx_fleet_garage` (`garage_id`),
  CONSTRAINT `fk_aegis_fleet_garage` FOREIGN KEY (`garage_id`)
    REFERENCES `aegis_enterprise_garages` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `aegis_enterprise_retired_keys` (
  `plate` VARCHAR(8) NOT NULL,
  `retired_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `aegis_enterprise_garage_points` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `garage_id` INT UNSIGNED NOT NULL,
  `kind` ENUM('store','spawn') NOT NULL,
  `label` VARCHAR(40) NOT NULL,
  `coords` LONGTEXT NOT NULL,
  PRIMARY KEY (`id`),
  INDEX `idx_aegis_points_garage_kind` (`garage_id`,`kind`),
  CONSTRAINT `fk_aegis_points_garage` FOREIGN KEY (`garage_id`)
    REFERENCES `aegis_enterprise_garages` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `aegis_enterprise_categories` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `garage_id` INT UNSIGNED NOT NULL,
  `name` VARCHAR(40) NOT NULL,
  `access_grade` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `withdraw_grade` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `store_grade` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `access_rules` LONGTEXT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_aegis_category_name` (`garage_id`,`name`),
  CONSTRAINT `fk_aegis_category_garage` FOREIGN KEY (`garage_id`)
    REFERENCES `aegis_enterprise_garages` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `aegis_enterprise_vehicle_categories` (
  `vehicle_id` INT UNSIGNED NOT NULL,
  `category_id` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`vehicle_id`),
  INDEX `idx_aegis_assigned_category` (`category_id`),
  CONSTRAINT `fk_aegis_assigned_vehicle` FOREIGN KEY (`vehicle_id`)
    REFERENCES `aegis_enterprise_fleet` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_aegis_assigned_category` FOREIGN KEY (`category_id`)
    REFERENCES `aegis_enterprise_categories` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET @aegis_sql = (
  SELECT IF(COUNT(*) = 0,
    'ALTER TABLE `aegis_enterprise_garages` ADD COLUMN `interaction` LONGTEXT NULL AFTER `permissions`',
    'SELECT 1')
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'aegis_enterprise_garages'
    AND COLUMN_NAME = 'interaction'
);
PREPARE aegis_stmt FROM @aegis_sql;
EXECUTE aegis_stmt;
DEALLOCATE PREPARE aegis_stmt;

SET @aegis_sql = (
  SELECT IF(COUNT(*) = 0,
    'ALTER TABLE `aegis_enterprise_categories` ADD COLUMN `access_rules` LONGTEXT NULL AFTER `store_grade`',
    'SELECT 1')
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'aegis_enterprise_categories'
    AND COLUMN_NAME = 'access_rules'
);
PREPARE aegis_stmt FROM @aegis_sql;
EXECUTE aegis_stmt;
DEALLOCATE PREPARE aegis_stmt;
SET @aegis_sql = NULL;

INSERT INTO `aegis_enterprise_garage_points` (`garage_id`, `kind`, `label`, `coords`)
SELECT g.id, 'store', 'Rangement principal', g.entrance
FROM `aegis_enterprise_garages` g
WHERE NOT EXISTS (
  SELECT 1 FROM `aegis_enterprise_garage_points` p
  WHERE p.garage_id = g.id AND p.kind = 'store'
);

INSERT INTO `aegis_enterprise_garage_points` (`garage_id`, `kind`, `label`, `coords`)
SELECT g.id, 'spawn', 'Sortie principale', g.spawn
FROM `aegis_enterprise_garages` g
WHERE NOT EXISTS (
  SELECT 1 FROM `aegis_enterprise_garage_points` p
  WHERE p.garage_id = g.id AND p.kind = 'spawn'
);

