#!/usr/bin/env python3
"""
Script migrate SQLite database sang PostgreSQL
Sử dụng: python3 scripts/migrate-sqlite-to-postgres.py
"""

import sqlite3
import os
import sys
import json
from datetime import datetime
from pathlib import Path

try:
    import psycopg2
    from psycopg2.extras import execute_values
except ImportError:
    print("❌ Cần cài đặt psycopg2: pip install psycopg2-binary")
    sys.exit(1)

SQLITE_DB_PATH = Path(__file__).parent.parent / '.tmp' / 'data.db'

POSTGRES_CONFIG = {
    'host': os.getenv('DATABASE_HOST', 'localhost'),
    'port': int(os.getenv('DATABASE_PORT', '5433')),
    'database': os.getenv('DATABASE_NAME', 'strapi'),
    'user': os.getenv('DATABASE_USERNAME', 'strapi'),
    'password': os.getenv('DATABASE_PASSWORD', 'strapi'),
}

def escape_column_name(name):
    reserved_keywords = {'order', 'user', 'group', 'select', 'table', 'where'}
    if name.lower() in reserved_keywords:
        return f'"{name}"'
    return name

def get_pg_column_types(pg_cursor, table_name):
    pg_cursor.execute("""
        SELECT column_name, data_type 
        FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = %s
    """, (table_name,))
    return {row[0]: row[1] for row in pg_cursor.fetchall()}

def convert_value(value, sqlite_type, pg_type=None):
    if value is None:
        return None
    
    if pg_type:
        if 'timestamp' in pg_type.lower():
            if isinstance(value, (int, float)) and value > 0:
                return datetime.fromtimestamp(value / 1000.0 if value > 1e10 else value)
            elif isinstance(value, str) and value.isdigit():
                val = int(value)
                return datetime.fromtimestamp(val / 1000.0 if val > 1e10 else val)
        
        if pg_type.lower() == 'boolean':
            if isinstance(value, bool):
                return value
            if isinstance(value, int):
                return bool(value)
            if isinstance(value, str):
                return value.lower() in ('true', '1', 'yes', 'on')
    
    if sqlite_type.upper() == 'BLOB':
        return value
    
    if isinstance(value, bool):
        return value
    
    if isinstance(value, (int, float)):
        return value
    
    if isinstance(value, str):
        if value.lower() in ('true', 'false'):
            return value.lower() == 'true'
        return value
    
    if isinstance(value, bytes):
        return value
    
    if isinstance(value, (dict, list)):
        return json.dumps(value)
    
    return value

def check_table_exists(pg_cursor, table_name):
    pg_cursor.execute("""
        SELECT EXISTS (
            SELECT FROM information_schema.tables 
            WHERE table_schema = 'public' 
            AND table_name = %s
        )
    """, (table_name,))
    return pg_cursor.fetchone()[0]

def migrate_database():
    if not SQLITE_DB_PATH.exists():
        print(f"❌ Không tìm thấy SQLite database tại: {SQLITE_DB_PATH}")
        sys.exit(1)
    
    print('📦 Đang kết nối SQLite database...')
    sqlite_conn = sqlite3.connect(str(SQLITE_DB_PATH))
    sqlite_conn.row_factory = sqlite3.Row
    sqlite_cursor = sqlite_conn.cursor()
    
    print('🐘 Đang kết nối PostgreSQL database...')
    try:
        pg_conn = psycopg2.connect(**POSTGRES_CONFIG)
        pg_conn.autocommit = True
        pg_cursor = pg_conn.cursor()
        print('✅ Đã kết nối PostgreSQL\n')
    except Exception as e:
        print(f'❌ Lỗi kết nối PostgreSQL: {e}')
        sqlite_conn.close()
        sys.exit(1)
    
    try:
        sqlite_cursor.execute("""
            SELECT name FROM sqlite_master 
            WHERE type='table' AND name NOT LIKE 'sqlite_%' 
            ORDER BY name
        """)
        tables = sqlite_cursor.fetchall()
        
        print(f'📋 Tìm thấy {len(tables)} bảng cần migrate\n')
        
        total_migrated = 0
        total_skipped = 0
        
        for (table_name,) in tables:
            print(f'🔄 Đang migrate bảng: {table_name}')
            
            if not check_table_exists(pg_cursor, table_name):
                print(f'   ⚠️  Bảng {table_name} không tồn tại trong PostgreSQL.')
                print(f'   💡 Gợi ý: Chạy Strapi một lần với PostgreSQL để tạo schema trước.\n')
                total_skipped += 1
                continue
            
            sqlite_cursor.execute(f"PRAGMA table_info({table_name})")
            columns = sqlite_cursor.fetchall()
            
            if len(columns) == 0:
                print(f'   ⚠️  Không tìm thấy cột, bỏ qua...\n')
                continue
            
            column_names = [col[1] for col in columns]
            sqlite_column_types = {col[1]: col[2] for col in columns}
            
            pg_column_types = get_pg_column_types(pg_cursor, table_name)
            
            escaped_column_names = [escape_column_name(name) for name in column_names]
            
            sqlite_cursor.execute(f"SELECT * FROM {table_name}")
            rows = sqlite_cursor.fetchall()
            
            if len(rows) == 0:
                print(f'   ⚠️  Bảng trống, bỏ qua...\n')
                continue
            
            inserted = 0
            errors = 0
            
            for row in rows:
                pg_conn.autocommit = True
                try:
                    values = []
                    for col_name in column_names:
                        sqlite_type = sqlite_column_types.get(col_name, 'TEXT')
                        pg_type = pg_column_types.get(col_name)
                        value = row[col_name]
                        converted_value = convert_value(value, sqlite_type, pg_type)
                        values.append(converted_value)
                    
                    placeholders = ', '.join(['%s'] * len(values))
                    insert_query = f"""
                        INSERT INTO {table_name} ({', '.join(escaped_column_names)}) 
                        VALUES ({placeholders}) 
                        ON CONFLICT DO NOTHING
                    """
                    pg_cursor.execute(insert_query, values)
                    if pg_cursor.rowcount > 0:
                        inserted += 1
                except psycopg2.IntegrityError:
                    continue
                except Exception as error:
                    errors += 1
                    if errors <= 3:
                        print(f'   ⚠️  Lỗi: {error}')
            
            print(f'   ✅ Đã migrate {inserted}/{len(rows)} dòng')
            if errors > 0:
                print(f'   ⚠️  {errors} dòng có lỗi')
            total_migrated += inserted
            
            print('')
        
        print('✨ Migration hoàn tất!')
        print(f'   📊 Tổng số dòng đã migrate: {total_migrated}')
        if total_skipped > 0:
            print(f'   ⚠️  {total_skipped} bảng đã bỏ qua (không tìm thấy schema)')
    
    except Exception as error:
        print(f'❌ Migration thất bại: {error}')
        pg_conn.rollback()
        sys.exit(1)
    finally:
        sqlite_conn.close()
        pg_cursor.close()
        pg_conn.close()

if __name__ == '__main__':
    migrate_database()

