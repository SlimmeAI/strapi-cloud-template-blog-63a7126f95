#!/bin/bash

# Script để fix các sequence bị lệch trong PostgreSQL

echo "=== Fixing sequences ==="

# Lấy danh sách tất cả các bảng có sequence
docker exec strapi-postgres psql -U strapi -d strapi -t -c "
SELECT 'SELECT setval(''' || sequence_name || ''', COALESCE((SELECT MAX(id) FROM ' || 
       REPLACE(sequence_name, '_id_seq', '') || '), 1) + 1, false);'
FROM information_schema.sequences 
WHERE sequence_schema = 'public' 
  AND sequence_name LIKE '%_id_seq'
ORDER BY sequence_name;
" | while read sql; do
  if [ ! -z "$sql" ]; then
    echo "Executing: $sql"
    docker exec strapi-postgres psql -U strapi -d strapi -c "$sql"
  fi
done

echo ""
echo "=== Fixed sequences ==="

