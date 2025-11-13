#!/bin/bash

# Script để fix các sequence bị lệch trong PostgreSQL

CONTAINER_NAME=${1:-strapi-postgres}

echo "=== Fixing sequences in container: $CONTAINER_NAME ==="

# Tạo file SQL tạm
TMPFILE=$(mktemp)
cat > "$TMPFILE" <<'SQL'
DO $$
DECLARE
    seq_record RECORD;
    table_name TEXT;
    max_id INTEGER;
    sql_stmt TEXT;
BEGIN
    FOR seq_record IN 
        SELECT sequence_name
        FROM information_schema.sequences 
        WHERE sequence_schema = 'public' 
          AND sequence_name LIKE '%_id_seq'
        ORDER BY sequence_name
    LOOP
        table_name := REPLACE(seq_record.sequence_name, '_id_seq', '');
        
        -- Lấy MAX(id) từ bảng
        EXECUTE format('SELECT COALESCE(MAX(id), 0) FROM %I', table_name) INTO max_id;
        
        -- Reset sequence
        sql_stmt := format('SELECT setval(%L, %s + 1, false)', seq_record.sequence_name, max_id);
        EXECUTE sql_stmt;
        
        RAISE NOTICE 'Fixed sequence: % (max_id: %)', seq_record.sequence_name, max_id;
    END LOOP;
END $$;
SQL

# Copy file vào container và chạy
docker cp "$TMPFILE" "$CONTAINER_NAME:/tmp/fix_sequences.sql"
docker exec "$CONTAINER_NAME" psql -U strapi -d strapi -f /tmp/fix_sequences.sql
docker exec "$CONTAINER_NAME" rm -f /tmp/fix_sequences.sql

# Xóa file tạm trên host
rm -f "$TMPFILE"

echo ""
echo "=== Fixed sequences ==="

