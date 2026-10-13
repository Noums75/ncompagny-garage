#!/usr/bin/env bash
set -euo pipefail
cd /workspace/ncompagny-garage
SETUP_ROOT=/workspace/cloud-setup
LUA_SOURCE="$SETUP_ROOT/cache/lua-5.4.7"
LUA_COMMIT=1ab3208a1fceb12fca8f24ba57d6e13c5bff15e3
MARIADB_IMAGE=mariadb@sha256:1292844148b311e4ed4300022a996d39083f415a963e970cf47cad1b3b18e3a6
MARIADB_ID=sha256:ab3dff582d246358b6f6a1f6212f29ac64609fad883eb3dcfb0a89f6f7d0700e
mkdir -p "$SETUP_ROOT/bin" "$SETUP_ROOT/cache" "$SETUP_ROOT/logs" "$SETUP_ROOT/python"
if [ ! -d "$LUA_SOURCE/.git" ]; then
    git clone --depth 1 --branch v5.4.7 https://github.com/lua/lua.git "$LUA_SOURCE"
fi
test "$(git -C "$LUA_SOURCE" rev-parse HEAD)" = "$LUA_COMMIT"
if [ ! -x "$SETUP_ROOT/bin/lua" ] || [ ! -f "$SETUP_ROOT/cache/lua-5.4.7-portable" ]; then
    make -C "$LUA_SOURCE" -B -j4 CFLAGS='-O2 -Wall -std=c99 -DLUA_USE_LINUX' MYLDFLAGS='-Wl,-E' MYLIBS=-ldl > "$SETUP_ROOT/logs/lua-build.log" 2>&1
    cp "$LUA_SOURCE/lua" "$SETUP_ROOT/bin/lua"
    touch "$SETUP_ROOT/cache/lua-5.4.7-portable"
fi
if ! PYTHONPATH="$SETUP_ROOT/python${PYTHONPATH:+:$PYTHONPATH}" python3 -c 'import pymysql; import importlib.metadata; assert importlib.metadata.version("PyMySQL") == "1.1.2"' 2>/dev/null; then
    python3 -m pip install --disable-pip-version-check --cache-dir "$SETUP_ROOT/cache/pip" --upgrade --target "$SETUP_ROOT/python" 'PyMySQL==1.1.2'
fi
python3 -c 'import playwright.sync_api'
test -x /usr/lib/chromium/chromium
node --check web/app.js
node --check web/preview.js
"$SETUP_ROOT/bin/lua" -e 'for _,p in ipairs({"fxmanifest.lua","shared/config.lua","server/database.lua","server/bridge.lua","server/main.lua","client/properties.lua","client/main.lua"}) do assert(loadfile(p),p) end'
if ! docker image inspect "$MARIADB_ID" >/dev/null 2>&1; then
    if [ -f "$SETUP_ROOT/cache/mariadb-11.4.tar" ]; then
        docker load -i "$SETUP_ROOT/cache/mariadb-11.4.tar"
    else
        docker pull "$MARIADB_IMAGE"
    fi
fi
docker image inspect "$MARIADB_ID" >/dev/null
if [ ! -f "$SETUP_ROOT/cache/mariadb-11.4.tar" ]; then
    docker save "$MARIADB_ID" -o "$SETUP_ROOT/cache/mariadb-11.4.tar"
fi
cat > "$SETUP_ROOT/env.sh" <<'ENV'
export PATH="/workspace/cloud-setup/bin:$PATH"
export PYTHONPATH="/workspace/cloud-setup/python${PYTHONPATH:+:$PYTHONPATH}"
export LUA=/workspace/cloud-setup/bin/lua
export CHROMIUM_PATH=/usr/lib/chromium/chromium
ENV
cat > "$SETUP_ROOT/start-db.sh" <<'DB'
#!/usr/bin/env bash
set -euo pipefail
MARIADB_ID=sha256:ab3dff582d246358b6f6a1f6212f29ac64609fad883eb3dcfb0a89f6f7d0700e
if ! docker image inspect "$MARIADB_ID" >/dev/null 2>&1; then
    docker load -i /workspace/cloud-setup/cache/mariadb-11.4.tar
fi
if docker container inspect aegis-dev-db >/dev/null 2>&1; then
    test "$(docker inspect --format '{{ index .Config.Labels "aegis.cloud-setup" }}' aegis-dev-db)" = true
    test "$(docker inspect --format '{{.Image}}' aegis-dev-db)" = "$MARIADB_ID"
    docker start aegis-dev-db >/dev/null
else
    docker run -d --name aegis-dev-db --label aegis.cloud-setup=true -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=1 -e MARIADB_DATABASE=aegis_dev --publish 127.0.0.1:3307:3306 "$MARIADB_ID" >/dev/null
fi
for attempt in {1..30}; do
    if docker exec aegis-dev-db mariadb --user=root --batch --skip-column-names --execute 'SELECT 1' >/dev/null 2>&1; then
        exit 0
    fi
    sleep 1
done
echo 'MariaDB did not become ready; inspect docker logs aegis-dev-db.' >&2
exit 1
DB
chmod +x "$SETUP_ROOT/start-db.sh"
echo 'Development dependencies installed; source /workspace/cloud-setup/env.sh.'

# Public FiveM prerequisites; do not change the application checkout.
clone_pinned() {
    local target="$1" remote="$2" commit="$3"
    if [ ! -d "$target/.git" ]; then
        test ! -e "$target"
        mkdir -p "$target"
        git -C "$target" init
        git -C "$target" remote add origin "$remote"
        git -C "$target" fetch --depth 1 origin "$commit"
        git -C "$target" checkout --detach FETCH_HEAD
    fi
    test "$(git -C "$target" rev-parse HEAD)" = "$commit"
    git -C "$target" diff --quiet HEAD --
}
mkdir -p "$SETUP_ROOT/fivem/cache"
clone_pinned "$SETUP_ROOT/fivem/cache/esx_core" https://github.com/esx-framework/esx_core.git 338ba0f45c197e8cb04b264b4c6a93124706f7aa
clone_pinned "$SETUP_ROOT/fivem/cache/oxmysql" https://github.com/overextended/oxmysql.git bae715c244d7ef8136a025c8a35ced3daff51738
clone_pinned "$SETUP_ROOT/fivem/server-data" https://github.com/citizenfx/cfx-server-data.git c6afa3909c763e3327ed76825e78453286c99f05
if [ ! -x "$SETUP_ROOT/bin/bun" ]; then
    npm install --prefix "$SETUP_ROOT/bun" --cache "$SETUP_ROOT/cache/npm" --no-audit --no-fund --save-exact @oven/bun-linux-x64-baseline@1.3.14
    ln -s "$SETUP_ROOT/bun/node_modules/@oven/bun-linux-x64-baseline/bin/bun" "$SETUP_ROOT/bin/bun"
fi
test "$("$SETUP_ROOT/bin/bun" --version)" = 1.3.14
export PATH="$SETUP_ROOT/bin:$PATH"
export BUN_INSTALL_CACHE_DIR="$SETUP_ROOT/cache/bun"
cd "$SETUP_ROOT/fivem/cache/oxmysql"
if [ ! -f dist/build.js ] || [ ! -f web/build/index.html ] || [ ! -f lib/MySQL.js ]; then
    bun install --frozen-lockfile
    unset TGT_RELEASE_VERSION
    bun run build
fi
test -f fxmanifest.lua
node --check dist/build.js
git diff --quiet HEAD --
for name in aegis_enterprise_garages es_extended esx_lib oxmysql; do
    case "$name" in
        aegis_enterprise_garages) target=/workspace/ncompagny-garage ;;
        es_extended|esx_lib) target="$SETUP_ROOT/fivem/cache/esx_core/[core]/$name" ;;
        oxmysql) target="$SETUP_ROOT/fivem/cache/oxmysql" ;;
    esac
    destination="$SETUP_ROOT/fivem/server-data/resources/[local]/$name"
    if [ -L "$destination" ]; then
        test "$(readlink "$destination")" = "$target"
    else
        test ! -e "$destination"
        ln -s "$target" "$destination"
    fi
done
cd /workspace/ncompagny-garage
echo 'ESX and oxmysql prepared. FXServer, license and Wasabi are still required for game validation.'
