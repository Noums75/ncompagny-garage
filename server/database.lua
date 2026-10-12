EnterpriseGarageDatabase = {}

local initialized = false

function EnterpriseGarageDatabase.ensure()
    if initialized then return end

    local schema = LoadResourceFile(GetCurrentResourceName(), 'sql/install.sql')
    if not schema or schema == '' then error('Fichier sql/install.sql introuvable ou vide.') end

    local tables, migrations, seeds = {}, {}, {}
    for query in schema:gmatch('(CREATE TABLE IF NOT EXISTS.-;)') do
        tables[#tables + 1] = query
    end
    if #tables == 0 then error('Aucune table définie dans sql/install.sql.') end

    for query in schema:gmatch("'(ALTER TABLE.-)'") do
        local tableName, columnName = query:match('^ALTER TABLE `([%w_]+)` ADD COLUMN `([%w_]+)`')
        if not tableName or not columnName then error('Migration SQL non prise en charge : ' .. query) end
        migrations[#migrations + 1] = { query = query, tableName = tableName, columnName = columnName }
    end
    for query in schema:gmatch('(INSERT INTO.-;)') do
        seeds[#seeds + 1] = query
    end

    MySQL.ready.await()
    for _, query in ipairs(tables) do
        MySQL.query.await(query)
    end
    for _, migration in ipairs(migrations) do
        local count = MySQL.scalar.await([[
            SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
        ]], { migration.tableName, migration.columnName })
        if tonumber(count) == 0 then
            MySQL.query.await(migration.query)
        elseif not tonumber(count) then
            error('Impossible de vérifier la colonne ' .. migration.tableName .. '.' .. migration.columnName)
        end
    end
    for _, query in ipairs(seeds) do
        MySQL.query.await(query)
    end
    initialized = true
end
