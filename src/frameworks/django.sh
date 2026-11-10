#!/bin/bash
# Django framework hooks

FRAMEWORK_SQLITE_PATH="db.sqlite3"   # Django convention
FRAMEWORK_IS_PYTHON=1
FRAMEWORK_DOCKER_TEMPLATE="python3-project"

framework_scaffold() {
    echo-return; echo-cyan "Django project selected!"

    PROJECT_NAME_SNAKE=$(echo "$PROJECT_NAME" | sed 's/-/_/g')

    mkdir -p "${PROJECT_NAME_SNAKE}"

    cat > manage.py << PYEOF
#!/usr/bin/env python3
import os
import sys

def main():
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', '${PROJECT_NAME_SNAKE}.settings')
    try:
        from django.core.management import execute_from_command_line
    except ImportError as exc:
        raise ImportError(
            "Couldn't import Django. Are you sure it's installed?"
        ) from exc
    execute_from_command_line(sys.argv)

if __name__ == '__main__':
    main()
PYEOF
    chmod +x manage.py

    touch "${PROJECT_NAME_SNAKE}/__init__.py"

    cat > "${PROJECT_NAME_SNAKE}/settings.py" << PYEOF
from dotenv import load_dotenv
from pathlib import Path
import os
import pymysql
pymysql.install_as_MySQLdb()
load_dotenv(Path(__file__).resolve().parent.parent / ".env")

BASE_DIR = Path(__file__).resolve().parent.parent
SECRET_KEY = 'django-insecure-zeltro-dev-key-change-in-production'
DEBUG = os.getenv('APP_DEBUG', 'true').lower() == 'true'
ALLOWED_HOSTS = ['*']

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    # Serves /static/ (the admin's CSS too) from gunicorn: the container's
    # nginx proxies everything to it, and gunicorn serves no static files.
    'whitenoise.middleware.WhiteNoiseMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = '${PROJECT_NAME_SNAKE}.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / 'templates'],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = '${PROJECT_NAME_SNAKE}.wsgi.application'

_db_engine = os.getenv('DB_CONNECTION', 'mysql')
if _db_engine in ('postgresql', 'pgsql', 'postgres'):
    _db_engine = 'postgresql'
elif _db_engine in ('sqlite', 'sqlite3'):
    _db_engine = 'sqlite3'
elif _db_engine == 'mongodb':
    _db_engine = 'mysql'  # mongo not natively supported in DATABASES; use separate lib
else:
    _db_engine = 'mysql'

if _db_engine == 'sqlite3':
    # SQLite takes only a file path — USER/PASSWORD/HOST/PORT are meaningless
    # and Django rejects some of them. The default lives in the project
    # directory, the only path bind-mounted into the container.
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.sqlite3',
            'NAME': os.getenv('DB_DATABASE') or str(BASE_DIR / 'db.sqlite3'),
        }
    }
else:
    DATABASES = {
        'default': {
            'ENGINE': f'django.db.backends.{_db_engine}',
            'NAME': os.getenv('DB_DATABASE', '${DB_NAME}'),
            'USER': os.getenv('DB_USERNAME', 'root'),
            'PASSWORD': os.getenv('DB_PASSWORD', ''),
            'HOST': os.getenv('DB_HOST', ''),
            'PORT': os.getenv('DB_PORT', '3306'),
        }
    }

LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True

STATIC_URL = '/static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
# Find files in each app's static/ folder directly, so new and changed files
# show up without re-running collectstatic. Turn off for production builds.
WHITENOISE_USE_FINDERS = True
WHITENOISE_AUTOREFRESH = DEBUG

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'
PYEOF

    cat > "${PROJECT_NAME_SNAKE}/urls.py" << 'PYEOF'
from django.contrib import admin
from django.urls import path
from django.http import JsonResponse

def home(request):
    return JsonResponse({"message": "Hello from Django!", "status": "ok"})

urlpatterns = [
    path('admin/', admin.site.urls),
    path('', home),
]
PYEOF

    cat > "${PROJECT_NAME_SNAKE}/wsgi.py" << PYEOF
import os
from django.core.wsgi import get_wsgi_application
os.environ.setdefault('DJANGO_SETTINGS_MODULE', '${PROJECT_NAME_SNAKE}.settings')
application = get_wsgi_application()
PYEOF

    cat > "${PROJECT_NAME_SNAKE}/asgi.py" << PYEOF
import os
from django.core.asgi import get_asgi_application
os.environ.setdefault('DJANGO_SETTINGS_MODULE', '${PROJECT_NAME_SNAKE}.settings')
application = get_asgi_application()
PYEOF

    cat > requirements.txt << 'EOF'
django
gunicorn
whitenoise
python-dotenv
pymysql
psycopg2-binary
pymongo
redis
EOF

    if [[ "$JSON_OUTPUT" == "1" ]]; then
        git init > /dev/null 2>&1
        git add . > /dev/null 2>&1
        git commit -m "Initial Django project setup" > /dev/null 2>&1
    else
        git init; git add .; git commit -m "Initial Django project setup"
    fi

    echo-green "Django project structure created!"
}

framework_python_start_command() {
    local snake
    snake=$(echo "$PROJECT_NAME" | sed 's/-/_/g')
    echo "gunicorn ${snake}.wsgi:application --bind 127.0.0.1:8000 --workers 2"
}

framework_setup_env() {
    should_write_env ".env" || return 0
    echo-cyan "Setting up .env file ..."; echo-white

    local db_connection db_host db_port db_username db_password
    # SQLite overrides this with a FILE PATH; every server engine uses the name.
    local db_database="$DB_NAME"
    case $DATABASE_ENGINE in
        "sqlite"|"sqlite3")
            # The file MUST sit in the project directory: that is the only path
            # bind-mounted into the container, so a database anywhere else is
            # destroyed when the container is recreated on `zeltro up`.
            db_connection="sqlite3"; db_host=""; db_port=""
            db_username=""; db_password=""
            db_database="/usr/share/nginx/html/${FRAMEWORK_SQLITE_PATH:-database.sqlite}"
            ;;
        "postgres"|"postgresql"|"pgsql")
            db_connection="postgresql"; db_host="$POSTGRES_CONTAINER_NAME"; db_port="5432"
            db_username="root"; db_password="password"
            ;;
        "mongo"|"mongodb")
            db_connection="mongodb"; db_host="$MONGO_CONTAINER_NAME"; db_port="27017"
            db_username="root"; db_password="password"
            ;;
        *)
            db_connection="mysql"; db_host="$MARIADB_CONTAINER_NAME"; db_port="3306"
            db_username="root"; db_password=""
            ;;
    esac

    cat > .env << EOF
APP_NAME=$PROJECT_NAME
APP_ENV=local
APP_DEBUG=true
APP_URL=http://$PROJECT_NAME
DB_CONNECTION=$db_connection
DB_HOST=$db_host
DB_PORT=$db_port
DB_DATABASE=$db_database
DB_USERNAME=$db_username
DB_PASSWORD=$db_password
REDIS_HOST=$REDIS_CONTAINER_NAME
REDIS_PORT=6379
MAIL_HOST=$MAILHOG_CONTAINER_NAME
MAIL_PORT=1025
EOF

    echo-green "The .env file has been created!"; echo-white
}

framework_run_migrations() {
    [ ! -f "manage.py" ] && return
    echo-cyan 'Running Django initial migrations ...'; echo-white

    if [[ "$JSON_OUTPUT" == "1" ]]; then
        docker exec "$PROJECT_NAME" bash -c "cd /usr/share/nginx/html && python3 manage.py migrate" > /dev/null 2>&1
    else
        docker exec "$PROJECT_NAME" bash -c "cd /usr/share/nginx/html && python3 manage.py migrate"
    fi

    echo-green 'Django migrations complete!'; echo-white
}

framework_setup_gitignore() {
    [ -f ".gitignore" ] && {
        if ! grep -q "docker-compose.yaml" .gitignore; then
            printf '\n# Docker infrastructure\ndocker-compose.yaml\n' >> .gitignore
        fi
        return
    }

    cat > .gitignore << 'GITEOF'
docker-compose.yaml
*.sqlite
*.sqlite3
__pycache__/
*.py[cod]
*.egg-info/
.env
.venv/
venv/
*.log
.DS_Store
staticfiles/
media/
GITEOF

    echo-green ".gitignore created for Django project!"
}
