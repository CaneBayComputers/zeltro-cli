#!/usr/bin/env python3
"""Which shared-service databases and users does a project use?

Usage: project_db_refs.py <projects_dir> <project> <installers_dir>

`zeltro remove --force-db-delete` used to drop the database named after the
project (t-freescout -> t_freescout). Installers name theirs after the app
(freescout, mastodon_production, tooljet_db), so the real database survived
every removal -- and so did the dedicated users some installers create
(FreeScout, Moodle, Mautic ...), which is how a reinstall ended up fighting a
stale password.

This reads what the project itself says it uses:

  * DB-name and DB-user settings in its compose file and env/config files
    (DB_DATABASE, POSTGRES_DB, MYSQL_USER, GITEA__database__NAME, ...);
  * connection URLs (postgresql://user:pass@host:5432/db, mysql://..., mongodb://...);
  * the installer that created it -- `installer:` in the compose x-metadata,
    written by `zeltro install` -- whose pre_install names what it CREATEs;
  * the snake-cased project name, which `zeltro setup` creates for frameworks.

and then removes every name that ANOTHER project also refers to (by the same
rules), so a database two projects share is never dropped from under one of
them. The caller still checks each name against what actually exists on the
server, which is what keeps a loose match here harmless.

Output, one per line:  db <name> | user <name> | engine <mariadb|postgres|mongo>
                       | shared-db <name> | shared-user <name>
Standard library only (macOS's python3 has no yaml).
"""
import os
import re
import sys

MAX_BYTES = 512 * 1024
SKIP_DIRS = {".git", "node_modules", "vendor", ".venv", "venv", "__pycache__",
             "storage", "public", "static", "dist", "build", "src", "app", "resources"}
CONFIG_EXT = (".yaml", ".yml", ".env", ".toml", ".ini", ".conf", ".cfg", ".json", ".php", ".sh")

SYSTEM_DBS = {"mysql", "information_schema", "performance_schema", "sys", "postgres",
              "template0", "template1", "admin", "local", "config", "test"}
SYSTEM_USERS = {"root", "postgres", "mariadb.sys", "healthcheck", "mysql", "admin", "pg_monitor"}

NOT_SQL = re.compile(r"^(REDIS|CLICKHOUSE|VECTOR|RABBITMQ|SMTP|EMAIL|MAIL|MINIO|S3|AWS|"
                     r"ELASTIC|MEILI|QDRANT|INFLUX|KAFKA|NATS|LDAP|OIDC|OAUTH)")
DB_KEY = re.compile(r"(^|[_.])(DB|DATABASE|DBNAME|DB_?NAME|DATABASE_?NAME|DATABASE_DATABASE|PGDATABASE)$")
DB_KEY_NESTED = re.compile(r"(DATABASE|POSTGRES|POSTGRESQL|MYSQL|MARIADB|DB)__NAME$")
USER_KEY = re.compile(r"(^|[_.])(DB|DATABASE|POSTGRES|POSTGRESQL|MYSQL|MARIADB|PG)"
                      r"([_.][A-Z]+)*?[_.]?(USER|USERNAME|DBUSER)$|^PGUSER$")
USER_KEY_NESTED = re.compile(r"(DATABASE|POSTGRES|POSTGRESQL|MYSQL|MARIADB|DB)__(USER|USERNAME)$")
KV = re.compile(r"""^\s*(?:-\s*)?["']?([A-Za-z0-9_.]+)["']?\s*[:=]\s*["']?([^"'\s#,;]*)""")
URL = re.compile(r"""\b(?:postgres(?:ql)?|mysql|mariadb|mongodb(?:\+srv)?)(?:\+[a-z0-9]+)?://"""
                 r"""(?:([^:@/\s"']+)(?::[^@/\s"']*)?@)?[^/\s"']+/([A-Za-z0-9_-]+)""")
FLAG = re.compile(r"--(dbname|dbuser|database-name|database-user)[= ]+[\"']?([A-Za-z0-9_-]+)")
CREATE_DB = re.compile(r"CREATE\s+DATABASE\s+(?:IF\s+NOT\s+EXISTS\s+)?[\\`\"']*([A-Za-z0-9_$]+)", re.I)
CREATE_USER = re.compile(r"CREATE\s+(?:USER|ROLE)\s+(?:IF\s+NOT\s+EXISTS\s+)?[\\`\"']*([A-Za-z0-9_$]+)", re.I)
PLAIN = re.compile(r"^[A-Za-z0-9_-]+$")


def config_files(root):
    for dirpath, dirnames, filenames in os.walk(root):
        rel = os.path.relpath(dirpath, root)
        depth = 0 if rel == "." else rel.count(os.sep) + 1
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and depth < 2]
        for f in filenames:
            if not (f.startswith(".env") or f.endswith(CONFIG_EXT) or f == "env"):
                continue
            if depth > 0 and not (f.startswith(".env") or f.endswith((".yaml", ".yml", ".env", ".toml", ".conf", ".ini"))):
                continue
            path = os.path.join(dirpath, f)
            try:
                if os.path.isfile(path) and os.path.getsize(path) <= MAX_BYTES:
                    yield path
            except OSError:
                pass


def installer_of(root):
    for fname in ("docker-compose.yaml", "docker-compose.yml"):
        path = os.path.join(root, fname)
        if not os.path.isfile(path):
            continue
        lines = open(path, errors="replace").read().split("\n")
        inside, indent = False, 0
        for line in lines:
            m = re.match(r"^(\s*)x-metadata:\s*$", line)
            if m:
                inside, indent = True, len(m.group(1))
                continue
            if inside:
                if line.strip() and len(line) - len(line.lstrip()) <= indent:
                    inside = False
                    continue
                m = re.match(r"""^\s*installer:\s*["']?([A-Za-z0-9._-]+)""", line)
                if m:
                    return m.group(1)
    return ""


def refs(root, project, installers_dir, service_names):
    dbs, users, engines = set(), set(), set()
    dbs.add(project.replace("-", "_"))
    for path in config_files(root):
        try:
            text = open(path, errors="replace").read()
        except OSError:
            continue
        for eng, pat in service_names.items():
            if pat.search(text):
                engines.add(eng)
        for line in text.split("\n"):
            m = KV.match(line)
            if m:
                key, val = m.group(1).upper(), m.group(2)
                if val and PLAIN.match(val) and not NOT_SQL.match(key):
                    if DB_KEY.search(key) or DB_KEY_NESTED.search(key):
                        dbs.add(val)
                    elif USER_KEY.search(key) or USER_KEY_NESTED.search(key):
                        users.add(val)
            for m in URL.finditer(line):
                if m.group(1) and PLAIN.match(m.group(1)):
                    users.add(m.group(1))
                dbs.add(m.group(2))
            for m in FLAG.finditer(line):
                (users if "user" in m.group(1) else dbs).add(m.group(2))
    slug = installer_of(root)
    if slug and PLAIN.match(slug):
        path = os.path.join(installers_dir, slug + ".sh")
        if os.path.isfile(path):
            text = open(path, errors="replace").read()
            snake = project.replace("-", "_")
            for pat, bucket in ((CREATE_DB, dbs), (CREATE_USER, users)):
                for m in pat.finditer(text):
                    name = m.group(1)
                    name = name.replace("${PROJECT_NAME}", project).replace("$PROJECT_NAME", project)
                    name = name.replace("${DB_NAME}", snake).replace("$DB_NAME", snake)
                    if PLAIN.match(name):
                        bucket.add(name)
    return dbs - SYSTEM_DBS, users - SYSTEM_USERS, engines


def main():
    if len(sys.argv) < 4:
        sys.stderr.write("usage: project_db_refs.py <projects_dir> <project> <installers_dir>\n")
        sys.exit(2)
    projects_dir, project, installers_dir = sys.argv[1:4]
    # Container names this machine uses (podium-* on a pre-rename box), plus
    # both stock prefixes, so detection never depends on which one is running.
    service_names = {}
    for eng, env, stock in (("mariadb", "ZELTRO_MARIADB", "mariadb|mysql"),
                            ("postgres", "ZELTRO_POSTGRES", "postgres"),
                            ("mongo", "ZELTRO_MONGO", "mongo")):
        alts = [r"(?:zeltro|podium)-(?:%s)" % stock]
        if os.environ.get(env):
            alts.append(re.escape(os.environ[env]))
        service_names[eng] = re.compile(r"(?<![A-Za-z0-9_-])(?:%s)(?![A-Za-z0-9_-])" % "|".join(alts))

    root = os.path.join(projects_dir, project)
    if not os.path.isdir(root):
        return
    dbs, users, engines = refs(root, project, installers_dir, service_names)

    other_dbs, other_users = set(), set()
    for other in sorted(os.listdir(projects_dir)):
        path = os.path.join(projects_dir, other)
        if other == project or not os.path.isdir(path) or other.startswith("."):
            continue
        d, u, _ = refs(path, other, installers_dir, service_names)
        other_dbs |= d
        other_users |= u

    for e in sorted(engines):
        print("engine", e)
    for n in sorted(dbs):
        print("shared-db" if n in other_dbs else "db", n)
    for n in sorted(users):
        print("shared-user" if n in other_users else "user", n)


if __name__ == "__main__":
    main()
