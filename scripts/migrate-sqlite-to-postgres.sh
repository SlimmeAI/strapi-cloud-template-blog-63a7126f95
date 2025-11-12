#!/bin/bash
# Script migrate SQLite database sang PostgreSQL sử dụng command-line tools
# Sử dụng: bash scripts/migrate-sqlite-to-postgres.sh

set -e

SQLITE_DB_PATH=".tmp/data.db"
PG_HOST="${DATABASE_HOST:-localhost}"
PG_PORT="${DATABASE_PORT:-5432}"
PG_DB="${DATABASE_NAME:-strapi}"
PG_USER="${DATABASE_USERNAME:-strapi}"
PG_PASSWORD="${DATABASE_PASSWORD:-strapi}"

if [ ! -f "$SQLITE_DB_PATH" ]; then
    echo "❌ Không tìm thấy SQLite database tại: $SQLITE_DB_PATH"
    exit 1
fi

if ! command -v sqlite3 &> /dev/null; then
    echo "❌ Cần cài đặt sqlite3"
    exit 1
fi

if ! command -v psql &> /dev/null; then
    echo "❌ Cần cài đặt psql (PostgreSQL client)"
    exit 1
fi

export PGPASSWORD="$PG_PASSWORD"

echo "📦 Đang đọc danh sách bảng từ SQLite..."
TABLES=$(sqlite3 "$SQLITE_DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")

if [ -z "$TABLES" ]; then
    echo "⚠️  Không tìm thấy bảng nào"
    exit 0
fi

TABLE_COUNT=$(echo "$TABLES" | wc -l | tr -d ' ')
echo "📋 Tìm thấy $TABLE_COUNT bảng cần migrate"
echo ""

TOTAL_MIGRATED=0
TOTAL_SKIPPED=0

while IFS= read -r TABLE_NAME; do
    [ -z "$TABLE_NAME" ] && continue
    
    echo "🔄 Đang migrate bảng: $TABLE_NAME"
    
    TABLE_EXISTS=$(psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -tAc \
        "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '$TABLE_NAME')")
    
    if [ "$TABLE_EXISTS" != "t" ]; then
        echo "   ⚠️  Bảng $TABLE_NAME không tồn tại trong PostgreSQL."
        echo "   💡 Gợi ý: Chạy Strapi một lần với PostgreSQL để tạo schema trước."
        echo ""
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
        continue
    fi
    
    ROW_COUNT=$(sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM $TABLE_NAME")
    
    if [ "$ROW_COUNT" -eq 0 ]; then
        echo "   ⚠️  Bảng trống, bỏ qua..."
        echo ""
        continue
    fi
    
    COLUMNS=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA table_info($TABLE_NAME)" | cut -d'|' -f2 | tr '\n' ',' | sed 's/,$//')
    
    if [ -z "$COLUMNS" ]; then
        echo "   ⚠️  Không tìm thấy cột, bỏ qua..."
        echo ""
        continue
    fi
    
    TEMP_FILE=$(mktemp)
    sqlite3 -header -csv "$SQLITE_DB_PATH" "SELECT * FROM $TABLE_NAME" > "$TEMP_FILE"
    
    INSERTED=0
    ERRORS=0
    
    while IFS= read -r LINE; do
        [ -z "$LINE" ] && continue
        
        VALUES=$(echo "$LINE" | sed "s/'/''/g" | sed "s/^/'/;s/$/'/" | sed "s/,/','/g")
        VALUES="($VALUES)"
        
        INSERT_QUERY="INSERT INTO $TABLE_NAME ($COLUMNS) VALUES $VALUES ON CONFLICT DO NOTHING;"
        
        if psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "$INSERT_QUERY" > /dev/null 2>&1; then
            INSERTED=$((INSERTED + 1))
        else
            ERRORS=$((ERRORS + 1))
            if [ "$ERRORS" -le 3 ]; then
                echo "   ⚠️  Lỗi khi insert dòng"
            fi
        fi
    done < <(tail -n +2 "$TEMP_FILE")
    
    rm -f "$TEMP_FILE"
    
    echo "   ✅ Đã migrate $INSERTED/$ROW_COUNT dòng"
    if [ "$ERRORS" -gt 0 ]; then
        echo "   ⚠️  $ERRORS dòng có lỗi"
    fi
    echo ""
    
    TOTAL_MIGRATED=$((TOTAL_MIGRATED + INSERTED))
done <<< "$TABLES"

unset PGPASSWORD

echo "✨ Migration hoàn tất!"
echo "   📊 Tổng số dòng đã migrate: $TOTAL_MIGRATED"
if [ "$TOTAL_SKIPPED" -gt 0 ]; then
    echo "   ⚠️  $TOTAL_SKIPPED bảng đã bỏ qua (không tìm thấy schema)"
fi

