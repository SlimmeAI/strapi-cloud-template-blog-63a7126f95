#!/bin/bash
# PostgreSQL Backup Script for Strapi
# Usage: bash scripts/backup-postgres.sh [options]

set -e

BACKUP_DIR="${BACKUP_DIR:-./backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
BACKUP_FORMAT="${BACKUP_FORMAT:-custom}"
COMPRESS="${COMPRESS:-true}"

PG_CONTAINER="${PG_CONTAINER:-strapi-postgres}"
PG_DB="${DATABASE_NAME:-strapi}"
PG_USER="${DATABASE_USERNAME:-strapi}"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/strapi_backup_${TIMESTAMP}"

usage() {
    cat << EOF
PostgreSQL Backup Script for Strapi

Usage: $0 [OPTIONS]

Options:
    --output DIR          Backup directory (default: ./backups)
    --retention DAYS      Number of days to keep backups (default: 30)
    --format FORMAT       Backup format: custom, sql, or tar (default: custom)
    --no-compress         Disable compression
    --container NAME      Docker container name (default: strapi-postgres)
    --help                Show this help message

Environment Variables:
    PG_CONTAINER          Docker container name (default: strapi-postgres)
    DATABASE_NAME         Database name (default: strapi)
    DATABASE_USERNAME     Database user (default: strapi)

Examples:
    $0
    $0 --output /backups --retention 7
    $0 --format sql --no-compress
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --output)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --retention)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        --format)
            BACKUP_FORMAT="$2"
            shift 2
            ;;
        --no-compress)
            COMPRESS="false"
            shift
            ;;
        --container)
            PG_CONTAINER="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please install Docker."
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q "^${PG_CONTAINER}$"; then
    echo "❌ Container '$PG_CONTAINER' is not running."
    echo "   Start it with: docker-compose up -d postgres"
    exit 1
fi

mkdir -p "$BACKUP_DIR"

echo "📦 Starting PostgreSQL backup via Docker..."
echo "   Container: $PG_CONTAINER"
echo "   Database: $PG_DB"
echo "   Format: $BACKUP_FORMAT"
echo ""

TEMP_BACKUP="/tmp/strapi_backup_${TIMESTAMP}"

case $BACKUP_FORMAT in
    custom)
        BACKUP_FILE="${BACKUP_FILE}.dump"
        TEMP_BACKUP="${TEMP_BACKUP}.dump"
        docker exec "$PG_CONTAINER" pg_dump -U "$PG_USER" -d "$PG_DB" \
            -F c -f "$TEMP_BACKUP"
        docker cp "${PG_CONTAINER}:${TEMP_BACKUP}" "$BACKUP_FILE"
        docker exec "$PG_CONTAINER" rm -f "$TEMP_BACKUP"
        ;;
    sql)
        BACKUP_FILE="${BACKUP_FILE}.sql"
        TEMP_BACKUP="${TEMP_BACKUP}.sql"
        docker exec "$PG_CONTAINER" pg_dump -U "$PG_USER" -d "$PG_DB" \
            -F p -f "$TEMP_BACKUP"
        docker cp "${PG_CONTAINER}:${TEMP_BACKUP}" "$BACKUP_FILE"
        docker exec "$PG_CONTAINER" rm -f "$TEMP_BACKUP"
        ;;
    tar)
        BACKUP_FILE="${BACKUP_FILE}.tar"
        TEMP_BACKUP="${TEMP_BACKUP}.tar"
        docker exec "$PG_CONTAINER" pg_dump -U "$PG_USER" -d "$PG_DB" \
            -F t -f "$TEMP_BACKUP"
        docker cp "${PG_CONTAINER}:${TEMP_BACKUP}" "$BACKUP_FILE"
        docker exec "$PG_CONTAINER" rm -f "$TEMP_BACKUP"
        ;;
    *)
        echo "❌ Invalid format: $BACKUP_FORMAT"
        echo "   Supported formats: custom, sql, tar"
        exit 1
        ;;
esac

if [ ! -f "$BACKUP_FILE" ]; then
    echo "❌ Backup failed: file not created"
    exit 1
fi

BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo "✅ Backup created successfully"
echo "   File: $BACKUP_FILE"
echo "   Size: $BACKUP_SIZE"

if [ "$COMPRESS" = "true" ] && [ "$BACKUP_FORMAT" != "custom" ]; then
    echo ""
    echo "🗜️  Compressing backup..."
    gzip "$BACKUP_FILE"
    BACKUP_FILE="${BACKUP_FILE}.gz"
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo "✅ Compression complete"
    echo "   File: $BACKUP_FILE"
    echo "   Size: $BACKUP_SIZE"
fi

if [ "$RETENTION_DAYS" -gt 0 ]; then
    echo ""
    echo "🧹 Cleaning up old backups (keeping last $RETENTION_DAYS days)..."
    
    if [ "$COMPRESS" = "true" ] && [ "$BACKUP_FORMAT" != "custom" ]; then
        find "$BACKUP_DIR" -name "strapi_backup_*.${BACKUP_FORMAT}.gz" -type f -mtime +$RETENTION_DAYS -delete
    else
        find "$BACKUP_DIR" -name "strapi_backup_*.${BACKUP_FORMAT}" -type f -mtime +$RETENTION_DAYS -delete
    fi
    
    REMAINING=$(find "$BACKUP_DIR" -name "strapi_backup_*" -type f | wc -l | tr -d ' ')
    echo "✅ Cleanup complete. $REMAINING backup(s) remaining"
fi

echo ""
echo "✨ Backup process completed successfully!"

