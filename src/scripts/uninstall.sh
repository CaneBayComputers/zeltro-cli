#!/bin/bash

# Zeltro Uninstall Script
# Selectively removes Zeltro-related Docker resources

# Source functions for colored output
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/functions.sh"

# Initialize variables
DELETE_IMAGES=""

# Capture original arguments for debug logging
ORIGINAL_ARGS="$*"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json-output)
            JSON_OUTPUT=1
            shift
            ;;
        --debug)
            DEBUG=1
            shift
            ;;
        --delete-images)
            DELETE_IMAGES="yes"
            shift
            ;;
        --help)
            echo-white "Usage: ${ZELTRO_CMD:-$0} [options]"
            echo-white "Selectively removes Zeltro-related Docker resources"
            echo-white ""
            echo-white "Options:"
            echo-white "  --json-output      Output JSON responses (for programmatic use)"
            echo-white "  --debug            Enable debug logging to /tmp/zeltro-cli-debug.log"
            echo-white "  --delete-images    Also remove Docker images (default: keep images)"
            echo-white "  --help            Show this help message"
            exit 0
            ;;
        -*)
            error "Unknown option: $1. Use --help for usage information"
            ;;
        *)
            error "Unexpected argument: $1. Use --help for usage information"
            ;;
    esac
done

# Initialize debug logging
debug "Script started: uninstall.sh with args: $ORIGINAL_ARGS"

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    error "Docker is not running or not accessible. Please start Docker and try again"
fi

echo-cyan "🧹 Zeltro Uninstall - Selective Docker Cleanup"
echo-return

# Load configuration to find compose file
COMPOSE_FILE=""
if [ -f "/etc/zeltro-cli/docker-compose.yaml" ]; then
    COMPOSE_FILE="/etc/zeltro-cli/docker-compose.yaml"
    echo-white "Using compose file: $COMPOSE_FILE"
elif [ -f "$SCRIPT_DIR/../docker-stack/docker-compose.services.yaml" ]; then
    COMPOSE_FILE="$SCRIPT_DIR/../docker-stack/docker-compose.services.yaml"
    echo-white "Using compose file: $COMPOSE_FILE"
else
    echo-yellow "Warning: No docker-compose.yaml found, will clean up any zeltro-cli* resources"
fi

echo-return

# 1. Stop and remove containers first
echo-white "🛑 Stopping Zeltro containers..."

# Get container names from docker-compose file
CONTAINERS=""
if [ -f "$COMPOSE_FILE" ]; then
    CONTAINERS=$(grep -E "^\s*container_name:" "$COMPOSE_FILE" | sed 's/.*container_name:\s*\([^[:space:]]*\).*/\1/' | tr '\n' ' ')
fi

if [ -n "$CONTAINERS" ]; then
    echo "Found containers from compose: $CONTAINERS"
    for container in $CONTAINERS; do
        if docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
            echo "  Stopping and removing: $container"
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
        else
            echo "  Container not found in Docker: $container"
        fi
    done
    echo-green "✅ Containers processed"
else
    echo "No containers found in compose file"
    echo "Searching for Zeltro containers by name pattern..."
    
    # Fallback: find containers by common Zeltro names
    # Exact Zeltro shared-service names only (either product prefix). The old
    # pattern matched any container whose name merely CONTAINED "redis",
    # "postgres" and so on, so uninstalling Zeltro could delete other people's
    # containers on the same machine.
FALLBACK_CONTAINERS=$(docker ps -a --format "{{.Names}}" | grep -E "^(zeltro|podium)-(mariadb|redis|postgres|mongo|memcached|phpmyadmin|mailhog|minio|meilisearch|adminer|mongo-express|redisinsight)$" 2>/dev/null || true)
    
    if [ -n "$FALLBACK_CONTAINERS" ]; then
        echo "Found containers by pattern: $FALLBACK_CONTAINERS"
        for container in $FALLBACK_CONTAINERS; do
            echo "  Stopping and removing: $container"
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
        done
        echo-green "✅ Fallback containers processed"
    else
        echo "  No Zeltro containers found"
    fi
fi

echo-return

# 1b. Stop and remove project containers
echo-white "🛑 Stopping project containers..."

# Load the get_projects_dir function
source "$SCRIPT_DIR/functions.sh"

PROJECT_CONTAINERS_REMOVED=0
PROJECTS_DIR=""

# Try to get projects directory
if [ -f "/etc/zeltro-cli/.env" ]; then
    PROJECTS_DIR=$(get_projects_dir 2>/dev/null || true)
fi

if [ -n "$PROJECTS_DIR" ] && [ -d "$PROJECTS_DIR" ]; then
    echo "Checking projects directory for containers: $PROJECTS_DIR"
    
    # Iterate through project folders
    for project_dir in "$PROJECTS_DIR"/*; do
        if [ -d "$project_dir" ]; then
            PROJECT_NAME=$(basename "$project_dir")
            
            # Check if project container exists and remove it
            if docker ps -a --format "{{.Names}}" | grep -q "^${PROJECT_NAME}$"; then
                echo "  Stopping and removing project container: $PROJECT_NAME"
                docker stop "$PROJECT_NAME" 2>/dev/null || true
                docker rm "$PROJECT_NAME" 2>/dev/null || true
                ((PROJECT_CONTAINERS_REMOVED++))
            fi
        fi
    done
else
    echo "Projects directory not found - checking for any project-like containers"
    
    # Fallback: find containers that aren't service containers
    ALL_CONTAINERS=$(docker ps -a --format "{{.Names}}")
SERVICE_CONTAINERS="$MARIADB_CONTAINER_NAME $REDIS_CONTAINER_NAME postgres mongo memcached phpmyadmin mailhog"
    
    for container in $ALL_CONTAINERS; do
        # Skip if it's a known service container
        if echo "$SERVICE_CONTAINERS" | grep -q "\b$container\b"; then
            continue
        fi
        
        # Check if it looks like a Zeltro project (has zeltro-project metadata)
        if docker inspect "$container" --format '{{json .Config.Labels}}' 2>/dev/null | grep -q "zeltro-project" 2>/dev/null; then
            echo "  Stopping and removing project container: $container"
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
            ((PROJECT_CONTAINERS_REMOVED++))
        fi
    done
fi

if [ $PROJECT_CONTAINERS_REMOVED -gt 0 ]; then
    echo-green "✅ Removed $PROJECT_CONTAINERS_REMOVED project containers"
else
    echo "No project containers found"
fi

echo-return

# Interactive prompt for image deletion (only in interactive mode)
if [[ "$JSON_OUTPUT" != "1" ]] && [ -z "$DELETE_IMAGES" ]; then
    echo-cyan "Would you like to remove Docker images as well?"
    echo-white "This will remove images like mariadb, redis, postgres, etc."
    echo-white "Images can be large and take time to re-download if you reinstall."
    echo-return
    echo-yellow -n "Remove Docker images? (y/N): "
    read REMOVE_IMAGES_RESPONSE
    if [[ "$REMOVE_IMAGES_RESPONSE" =~ ^[Yy]$ ]]; then
        DELETE_IMAGES="yes"
    else
        DELETE_IMAGES="no"
    fi
    echo-return
fi

# Default to "no" if not specified
if [ -z "$DELETE_IMAGES" ]; then
    DELETE_IMAGES="no"
fi

# 2. Remove specific images by name (if requested)
if [ "$DELETE_IMAGES" = "yes" ]; then
    echo-white "🗑️ Removing Zeltro images..."

    # Get image names from docker-compose file
    IMAGES=""
    if [ -f "$COMPOSE_FILE" ]; then
        IMAGES=$(grep -E "^\s*image:" "$COMPOSE_FILE" | sed 's/.*image:\s*\([^[:space:]]*\).*/\1/' | sort | uniq)
    fi

    REMOVED_IMAGES=0
    if [ -n "$IMAGES" ]; then
        for image in $IMAGES; do
            # Check if image exists (with or without :latest tag)
            if docker image inspect "$image" >/dev/null 2>&1 || docker image inspect "$image:latest" >/dev/null 2>&1; then
                echo "Removing image: $image"
                docker rmi "$image" 2>/dev/null || docker rmi "$image:latest" 2>/dev/null || true
                ((REMOVED_IMAGES++))
            fi
        done
    fi

    if [ $REMOVED_IMAGES -gt 0 ]; then
        echo-green "✅ Removed $REMOVED_IMAGES images"
    else
        echo "No Zeltro images found to remove"
    fi
else
    echo-white "🗑️ Skipping image removal (keeping Docker images)"
    echo-green "✅ Docker images preserved"
fi

echo-return

# 3. Remove volumes and networks with zeltro-cli prefix
echo-white "📦 Removing Zeltro volumes..."

# Always use zeltro-cli prefix to catch all Zeltro resources
VOLUME_PATTERN="zeltro-cli"
NETWORK_PATTERN="zeltro-cli"

# Remove volumes
VOLUMES=$(docker volume ls --filter "name=${VOLUME_PATTERN}" --format "{{.Name}}" 2>/dev/null || true)
if [ -n "$VOLUMES" ]; then
    echo "Found volumes: $VOLUMES"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # Mac: xargs doesn't have -r flag, use different approach
        echo "$VOLUMES" | tr ' ' '\n' | while read -r volume; do
            [ -n "$volume" ] && docker volume rm "$volume" 2>/dev/null || true
        done
    else
        # Linux: use xargs -r
        echo "$VOLUMES" | xargs -r docker volume rm 2>/dev/null || true
    fi
    echo-green "✅ Volumes removed"
else
    echo "No Zeltro volumes found"
fi

echo-return

# 4. Remove networks
echo-white "🌐 Removing Zeltro networks..."

NETWORKS=$(docker network ls --filter "name=${NETWORK_PATTERN}" --format "{{.Name}}" 2>/dev/null || true)
if [ -n "$NETWORKS" ]; then
    echo "Found networks: $NETWORKS"
    
    # Process each network individually to handle disconnection if needed
    for network in $NETWORKS; do
        echo "Processing network: $network"
        
        # Check if network has connected containers
        CONNECTED_CONTAINERS=$(docker network inspect "$network" --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || true)
        
        if [ -n "$CONNECTED_CONTAINERS" ]; then
            echo "  Disconnecting containers from $network: $CONNECTED_CONTAINERS"
            for container in $CONNECTED_CONTAINERS; do
                docker network disconnect "$network" "$container" 2>/dev/null || true
            done
        fi
        
        # Now remove the network
        echo "  Removing network: $network"
        if docker network rm "$network" 2>/dev/null; then
            echo "  ✅ Successfully removed network: $network"
        else
            echo "  ⚠️  Failed to remove network: $network (may still be in use)"
        fi
    done
    echo-green "✅ Network removal completed"
else
    echo "No Zeltro networks found"
fi

echo-return


# 7. Backup project docker-compose.yaml files
echo-white "💾 Backing up project docker-compose.yaml files..."

PROJECT_COMPOSE_BACKED_UP=0

if [ -n "$PROJECTS_DIR" ] && [ -d "$PROJECTS_DIR" ]; then
    echo "Checking projects directory for docker-compose.yaml files: $PROJECTS_DIR"
    
    # Iterate through project folders
    for project_dir in "$PROJECTS_DIR"/*; do
        if [ -d "$project_dir" ]; then
            PROJECT_NAME=$(basename "$project_dir")
            COMPOSE_FILE_PATH="$project_dir/docker-compose.yaml"
            
            # Check if docker-compose.yaml exists in this project
            if [ -f "$COMPOSE_FILE_PATH" ]; then
                BACKUP_PATH="$project_dir/docker-compose.yaml.backup"
                echo "Backing up: $PROJECT_NAME/docker-compose.yaml → docker-compose.yaml.backup"
                
                # Remove existing backup if it exists
                [ -f "$BACKUP_PATH" ] && rm -f "$BACKUP_PATH"
                
                # Rename the file
                mv "$COMPOSE_FILE_PATH" "$BACKUP_PATH"
                ((PROJECT_COMPOSE_BACKED_UP++))
            fi
        fi
    done
else
    echo "Projects directory not found - skipping docker-compose.yaml backup"
fi

if [ $PROJECT_COMPOSE_BACKED_UP -gt 0 ]; then
    echo-green "✅ Backed up $PROJECT_COMPOSE_BACKED_UP project docker-compose.yaml files"
    echo-yellow "⚠️  Project docker-compose.yaml files have been renamed to .backup"
    echo-yellow "   These files will not work without Zeltro services running"
else
    echo "No project docker-compose.yaml files found"
fi

echo-return

# 8. Clean up any orphaned resources
echo-white "🧽 Cleaning up orphaned resources..."
docker system prune -f >/dev/null 2>&1 || true
echo-green "✅ Orphaned resources cleaned"

echo-return
echo-green "🎉 Zeltro Docker resources have been selectively removed!"
echo-return
echo-white "What was removed:"
echo "  • Zeltro service containers (mariadb, phpmyadmin, redis, etc.)"
echo "  • Individual project containers"
if [ "$DELETE_IMAGES" = "yes" ]; then
    echo "  • Zeltro Docker images (mariadb, redis, postgres, etc.)"
fi
echo "  • Volumes with prefix: zeltro-cli_*"
echo "  • Networks with prefix: zeltro-cli_*"
echo "  • Zeltro CLI binary and source files"
echo-return
echo-white "What was kept:"
echo "  • Your projects folder and all project code"
echo "  • /etc/zeltro-cli configuration (reinstall will pick it up automatically)"
if [ "$DELETE_IMAGES" = "no" ]; then
    echo "  • Zeltro Docker images (will speed up reinstall)"
fi
echo "  • Docker itself"
echo-return
echo-cyan "To reinstall Zeltro:"
echo "  https://github.com/CaneBayComputers/zeltro-cli"
echo-return

# Remove CLI binary and source files last (script is already in memory so this is safe)
echo-white "🗑️  Removing Zeltro CLI files..."
sudo rm -f /usr/local/bin/zeltro
sudo rm -rf /usr/local/share/zeltro-cli
echo-green "✅ Zeltro CLI removed"
echo-white "  Your projects folder and /etc/zeltro-cli configuration have been kept."
echo-white "  If you reinstall Zeltro your projects and settings will still be there."
echo-return
