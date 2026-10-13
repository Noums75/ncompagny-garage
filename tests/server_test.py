"""Integration runner: actual Lua server callbacks + isolated MariaDB schema.

Requires Lua 5.4 and PyMySQL; MYSQL_HOST/PORT/USER/PASSWORD select a test server.
Creates and drops a randomly named test database, never touches the app database.
"""
import datetime
import json
import os
from pathlib import Path
import subprocess
import uuid

import pymysql


def lua_value(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, (datetime.datetime, datetime.date)):
        value = str(value)
    if isinstance(value, bytes):
        value = value.decode()
    if isinstance(value, str):
        return '"' + ''.join(f'\\{ord(c):03d}' if ord(c) < 32 or c in '\\"' else c for c in value) + '"'
    if isinstance(value, list):
        return '{' + ','.join(lua_value(v) for v in value) + '}'
    return '{' + ','.join(f'[{lua_value(k)}]={lua_value(v)}' for k, v in value.items()) + '}'


def main():
    root = Path(__file__).resolve().parents[1]
    connection = pymysql.connect(host=os.getenv('MYSQL_HOST', '127.0.0.1'), port=int(os.getenv('MYSQL_PORT', '3307')),
                                 user=os.getenv('MYSQL_USER', 'root'), password=os.getenv('MYSQL_PASSWORD', ''),
                                 charset='utf8mb4', autocommit=True, cursorclass=pymysql.cursors.DictCursor)
    database = 'aegis_test_' + uuid.uuid4().hex
    process = None
    result = None
    try:
        with connection.cursor() as cursor:
            cursor.execute(f'CREATE DATABASE `{database}` CHARACTER SET utf8mb4')
            cursor.execute(f'USE `{database}`')
            cursor.execute('''CREATE TABLE owned_vehicles (
                id INT AUTO_INCREMENT PRIMARY KEY, owner VARCHAR(255), plate VARCHAR(8) UNIQUE,
                vehicle LONGTEXT, stored TINYINT DEFAULT 0, parking VARCHAR(60), impound INT DEFAULT 0,
                doorcondition VARCHAR(255), windowcondition VARCHAR(255), tyrecondition VARCHAR(255),
                favourite TINYINT DEFAULT 0, impoundTime VARCHAR(255), location VARCHAR(255), reason VARCHAR(255),
                sharedwith LONGTEXT DEFAULT '[]', vehiclename VARCHAR(23),
                custom_note VARCHAR(255), nullable_field VARCHAR(100))''')
        process = subprocess.Popen([os.getenv('LUA', '/workspace/cloud-setup/bin/lua'), 'tests/server_integration.lua'],
                                   cwd=root, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        for line in process.stdout:
            request = json.loads(line)
            method, payload = request['method'], request.get('payload')
            try:
                if method == 'decode':
                    value = json.loads(payload)
                elif method == 'result':
                    result = payload
                    value = True
                elif method == 'transaction':
                    connection.begin()
                    try:
                        with connection.cursor() as cursor:
                            for statement in payload:
                                cursor.execute(statement['query'].replace('%', '%%').replace('?', '%s'), statement.get('values') or [])
                        connection.commit()
                        value = True
                    except Exception:
                        connection.rollback()
                        raise
                else:
                    with connection.cursor() as cursor:
                        cursor.execute(payload['query'].replace('%', '%%').replace('?', '%s'), payload.get('values') or [])
                        if method == 'query':
                            value = list(cursor.fetchall())
                        elif method == 'single':
                            value = cursor.fetchone()
                        elif method == 'scalar':
                            row = cursor.fetchone()
                            value = next(iter(row.values())) if row else None
                        elif method == 'insert':
                            value = cursor.lastrowid
                        else:
                            value = cursor.rowcount
                response = {'value': value}
            except Exception as error:
                response = {'error': str(error)}
            process.stdin.write(lua_value(response) + '\n')
            process.stdin.flush()
        if process.wait() or result is None:
            raise SystemExit('Lua/MariaDB integration failed')
        print(f"Lua/MariaDB integration: {result['checks']} assertions passed")
    finally:
        if process and process.poll() is None:
            process.kill()
            process.wait()
        with connection.cursor() as cursor:
            cursor.execute(f'DROP DATABASE IF EXISTS `{database}`')
        connection.close()


if __name__ == '__main__':
    main()
