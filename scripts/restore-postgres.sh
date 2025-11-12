#!/bin/bash
# PostgreSQL Restore Script for Strapi
# Usage: bash scripts/restore-postgres.sh <backup_file.dump> [options]

set -e

usage() {
    cat << EOF
PostgreSQL Restore Script for Strapi

Usage: $0 <BACKUP_FILE> [OPTIONS]

Arguments:
    BACKUP_FILE           Path to the .dump backup file

Options:
    --container NAME      Docker container name (default: strapi-postgres)
    --database NAME       Database name (default: strapi)
    --user NAME           Database user (default: strapi)
    --no-clean            Don't drop existing objects before restore
    --verbose             Verbose output
    --help                Show this help message

Environment Variables:
    PG_CONTAINER          Docker container name (default: strapi-postgres)
    DATABASE_NAME         Database name (default: strapi)
    DATABASE_USERNAME     Database user (default: strapi)

Examples:
    $0 ./backups/strapi_backup_20251112_141807.dump
    $0 ./backups/backup.dump --verbose
    $0 ./backups/backup.dump --no-clean
EOF
}

PG_CONTAINER="${PG_CONTAINER:-strapi-postgres}"
PG_DB="${DATABASE_NAME:-strapi}"
PG_USER="${DATABASE_USERNAME:-strapi}"
CLEAN_FLAG="-c"
VERBOSE_FLAG=""

if [ $# -eq 0 ]; then
    echo "❌ Error: Backup file is required"
    echo ""
    usage
    exit 1
fi

BACKUP_FILE="$1"
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        --container)
            PG_CONTAINER="$2"
            shift 2
            ;;
        --database)
            PG_DB="$2"
            shift 2
            ;;
        --user)
            PG_USER="$2"
            shift 2
            ;;
        --no-clean)
            CLEAN_FLAG=""
            shift
            ;;
        --verbose)
            VERBOSE_FLAG="-v"
            shift
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

if [ ! -f "$BACKUP_FILE" ]; then
    echo "❌ Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q "^${PG_CONTAINER}$"; then
    echo "❌ Container '$PG_CONTAINER' is not running."
    echo "   Start it with: docker-compose up -d postgres"
    exit 1
fi

echo "📦 Starting PostgreSQL restore..."
echo "   Container: $PG_CONTAINER"
echo "   Database: $PG_DB"
echo "   Backup file: $BACKUP_FILE"
if [ -n "$CLEAN_FLAG" ]; then
    echo "   Mode: Clean restore (will drop existing objects)"
else
    echo "   Mode: Incremental restore (will keep existing objects)"
fi
echo ""

TEMP_RESTORE="/tmp/restore_$(date +%Y%m%d_%H%M%S).dump"

echo "📋 Copying backup file to container..."
docker cp "$BACKUP_FILE" "${PG_CONTAINER}:${TEMP_RESTORE}"

if [ $? -ne 0 ]; then
    echo "❌ Failed to copy backup file to container"
    exit 1
fi

echo "✅ Backup file copied to container"
echo ""

echo "🔄 Restoring database..."
RESTORE_CMD="pg_restore -U $PG_USER -d $PG_DB"
if [ -n "$CLEAN_FLAG" ]; then
    RESTORE_CMD="$RESTORE_CMD $CLEAN_FLAG"
fi
if [ -n "$VERBOSE_FLAG" ]; then
    RESTORE_CMD="$RESTORE_CMD $VERBOSE_FLAG"
fi
RESTORE_CMD="$RESTORE_CMD $TEMP_RESTORE"

if docker exec "$PG_CONTAINER" $RESTORE_CMD; then
    echo ""
    echo "✅ Database restored successfully"
else
    echo ""
    echo "❌ Restore failed"
    docker exec "$PG_CONTAINER" rm -f "$TEMP_RESTORE"
    exit 1
fi

echo ""
echo "🧹 Cleaning up temporary files..."
docker exec "$PG_CONTAINER" rm -f "$TEMP_RESTORE"

echo ""
echo "🔍 Verifying restore..."
TABLE_COUNT=$(docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -tAc \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")

if [ "$TABLE_COUNT" -gt 0 ]; then
    echo "✅ Verification successful: Found $TABLE_COUNT table(s) in database"
else
    echo "⚠️  Warning: No tables found in database. Restore may have failed."
fi

echo ""
echo "✨ Restore process completed successfully!"

