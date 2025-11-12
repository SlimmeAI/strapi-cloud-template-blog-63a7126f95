# Strapi Setup Guide

This guide covers the setup, database restore from .dump files, and backup procedures for the Strapi application.

## Table of Contents

1. [Initial Setup](#initial-setup)
2. [Database Restore from .dump File](#database-restore-from-dump-file)
3. [Production Deployment](#production-deployment)
4. [Backup Procedures](#backup-procedures)

## Initial Setup

### Prerequisites

- Node.js (>=18.0.0 <=22.x.x)
- npm (>=6.0.0)
- Docker and Docker Compose (for PostgreSQL)

### Installation Steps

1. **Install dependencies:**
   ```bash
   npm install
   ```

2. **Set up environment variables:**
   Create a `.env` file in the root directory with the following variables:
   ```env
   DATABASE_CLIENT=postgres
   DATABASE_HOST=localhost
   DATABASE_PORT=5433
   DATABASE_NAME=strapi
   DATABASE_USERNAME=strapi
   DATABASE_PASSWORD=strapi
   DATABASE_SSL=false
   
   APP_KEYS=your-app-keys-here
   ADMIN_JWT_SECRET=your-admin-jwt-secret
   API_TOKEN_SALT=your-api-token-salt
   TRANSFER_TOKEN_SALT=your-transfer-token-salt
   ```

3. **Start PostgreSQL with Docker:**
   ```bash
   docker-compose up -d postgres
   ```

4. **Run Strapi to create database schema (if restoring from .dump, skip this step):**
   ```bash
   npm run develop
   ```
   This will create all necessary tables in PostgreSQL. Stop the server after the schema is created (Ctrl+C).

## Database Restore from .dump File

### Overview

This section covers restoring a PostgreSQL database from a `.dump` file. This is useful when:
- Setting up a new environment with existing data
- Restoring from a backup
- Migrating data between environments

All restore operations use Docker, so you don't need PostgreSQL client tools installed on your host machine.

### Prerequisites

1. **Ensure PostgreSQL container is running:**
   ```bash
   docker-compose up -d postgres
   ```

2. **Verify container is running:**
   ```bash
   docker ps | grep strapi-postgres
   ```

3. **Have your .dump file ready:**
   - The backup file should be in `.dump` format (custom format)
   - Place it in an accessible location (e.g., `./backups/` directory)

### Automated Restore Script

The easiest way to restore is using the provided restore script:

```bash
bash scripts/restore-postgres.sh ./backups/strapi_backup_20251112_141807.dump
```

Or with options:

```bash
bash scripts/restore-postgres.sh ./backups/backup.dump --verbose --no-clean
```

**Script Options:**
- `--container NAME`: Docker container name (default: `strapi-postgres`)
- `--database NAME`: Database name (default: `strapi`)
- `--user NAME`: Database user (default: `strapi`)
- `--no-clean`: Don't drop existing objects before restore (incremental restore)
- `--verbose`: Show detailed restore output

### Manual Restore Steps

If you prefer to restore manually:

1. **Ensure the database exists:**
   The database `strapi` should already exist (created by docker-compose). If not, create it:
   ```bash
   docker exec strapi-postgres psql -U strapi -c "CREATE DATABASE strapi;" || true
   ```

2. **Copy the .dump file into the container:**
   ```bash
   docker cp /path/to/your/backup.dump strapi-postgres:/tmp/restore.dump
   ```
   
   Example if backup is in `./backups/`:
   ```bash
   docker cp ./backups/strapi_backup_20251112_141807.dump strapi-postgres:/tmp/restore.dump
   ```

3. **Restore the database:**
   ```bash
   docker exec strapi-postgres pg_restore -U strapi -d strapi -c /tmp/restore.dump
   ```
   
   **Options explained:**
   - `-U strapi`: PostgreSQL username
   - `-d strapi`: Database name
   - `-c`: Clean (drop) database objects before recreating them
   - `-v`: Verbose mode (optional, for detailed output)

4. **Clean up temporary file:**
   ```bash
   docker exec strapi-postgres rm -f /tmp/restore.dump
   ```

5. **Verify the restore:**
   ```bash
   docker exec strapi-postgres psql -U strapi -d strapi -c "\dt"
   ```
   This will list all tables in the database.

### Complete Restore Example

Here's a complete example restoring from a backup file:

```bash
# 1. Start PostgreSQL
docker-compose up -d postgres

# 2. Wait a few seconds for PostgreSQL to be ready
sleep 5

# 3. Copy backup file to container
docker cp ./backups/strapi_backup_20251112_141807.dump strapi-postgres:/tmp/restore.dump

# 4. Restore database
docker exec strapi-postgres pg_restore -U strapi -d strapi -c -v /tmp/restore.dump

# 5. Clean up
docker exec strapi-postgres rm -f /tmp/restore.dump

# 6. Verify (optional)
docker exec strapi-postgres psql -U strapi -d strapi -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';"
```

### Restore Options

The `pg_restore` command supports various options:

- **`-c, --clean`**: Clean (drop) database objects before recreating
- **`-v, --verbose`**: Verbose mode
- **`-a, --data-only`**: Restore only the data, not the schema
- **`-s, --schema-only`**: Restore only the schema, not the data
- **`-t, --table=TABLE`**: Restore only specific table(s)
- **`-e, --exit-on-error`**: Exit on error (default is to continue)

Example with verbose output:
```bash
docker exec strapi-postgres pg_restore -U strapi -d strapi -c -v /tmp/restore.dump
```

### Troubleshooting

**Issue: "database does not exist"**
- Solution: Create the database first:
  ```bash
  docker exec strapi-postgres psql -U strapi -c "CREATE DATABASE strapi;"
  ```

**Issue: "permission denied" or "authentication failed"**
- Solution: Verify the database credentials match your docker-compose.yml settings
- Default: user=`strapi`, password=`strapi`, database=`strapi`

**Issue: "connection refused"**
- Solution: Ensure PostgreSQL container is running:
  ```bash
  docker-compose ps
  docker-compose up -d postgres
  ```

**Issue: "duplicate key value violates unique constraint"**
- Solution: Use the `-c` (clean) flag to drop existing objects first, or restore to an empty database

**Issue: "file not found" in container**
- Solution: Verify the file was copied correctly:
  ```bash
  docker exec strapi-postgres ls -lh /tmp/restore.dump
  ```

### Restoring Without Clean (-c flag)

If you want to restore data without dropping existing objects (useful for incremental restores):

```bash
docker exec strapi-postgres pg_restore -U strapi -d strapi /tmp/restore.dump
```

Note: This may fail if objects already exist. Use `-c` flag for a clean restore.

## Production Deployment

### Overview

This section covers deploying Strapi to production using Docker Compose with optimized settings for production environments.

### Prerequisites

- Docker and Docker Compose installed
- Production environment variables configured
- Database backup ready (if restoring from backup)

### Production Setup Steps

1. **Create production environment file:**
   ```bash
   cp env.prod.example .env.prod
   ```

2. **Edit `.env.prod` with your production values:**
   - Set secure passwords for PostgreSQL
   - Generate secure random strings for all security keys:
     - `APP_KEYS` (comma-separated, at least 4 keys)
     - `ADMIN_JWT_SECRET`
     - `API_TOKEN_SALT`
     - `TRANSFER_TOKEN_SALT`
     - `JWT_SECRET`
   
   **Generate secure keys:**
   ```bash
   # Generate random strings (run multiple times for APP_KEYS)
   openssl rand -base64 32
   ```

3. **Build and start production services:**
   ```bash
   docker-compose -f docker-compose.prod.yml up -d --build
   ```

4. **Restore database (if needed):**
   ```bash
   bash scripts/restore-postgres.sh ./backups/your-backup.dump --container strapi-postgres-prod
   ```

5. **Check service status:**
   ```bash
   docker-compose -f docker-compose.prod.yml ps
   docker-compose -f docker-compose.prod.yml logs -f strapi
   ```

### Production Configuration

The production setup includes:

- **Optimized Dockerfile**: Uses `npm ci --only=production` and builds with `NODE_ENV=production`
- **Health checks**: Both PostgreSQL and Strapi have health checks configured
- **Separate networks and volumes**: Isolated from development environment
- **No source code volumes**: Production runs from built image, not mounted volumes
- **Persistent uploads**: Only upload directories are mounted as volumes

### Production Commands

**Start services:**
```bash
docker-compose -f docker-compose.prod.yml up -d
```

**Stop services:**
```bash
docker-compose -f docker-compose.prod.yml down
```

**View logs:**
```bash
docker-compose -f docker-compose.prod.yml logs -f
```

**Rebuild and restart:**
```bash
docker-compose -f docker-compose.prod.yml up -d --build
```

**Backup database:**
```bash
bash scripts/backup-postgres.sh --container strapi-postgres-prod --output ./backups
```

### Production Features

- **NODE_ENV=production**: Optimized for production performance
- **Health checks**: Automatic container health monitoring
- **Service dependencies**: Strapi waits for PostgreSQL to be healthy
- **Separate volumes**: `postgres_data_prod` for production data isolation
- **Environment variables**: All sensitive data via `.env.prod` file

### Security Considerations

1. **Never commit `.env.prod`** to version control
2. **Use strong passwords** for PostgreSQL
3. **Generate secure random strings** for all security keys
4. **Enable SSL** for database connections in production (`DATABASE_SSL=true`)
5. **Use reverse proxy** (nginx/traefik) for HTTPS termination
6. **Limit port exposure** - consider removing port mappings and using internal networking only

### Troubleshooting

**Issue: "Build fails"**
- Solution: Ensure all dependencies are in `package.json`, not `devDependencies`

**Issue: "Container exits immediately"**
- Solution: Check logs: `docker-compose -f docker-compose.prod.yml logs strapi`
- Verify environment variables are set correctly

**Issue: "Database connection fails"**
- Solution: Verify PostgreSQL is healthy: `docker-compose -f docker-compose.prod.yml ps`
- Check database credentials in `.env.prod`

**Issue: "Health check fails"**
- Solution: Strapi may need more time to start. Increase `start_period` in healthcheck

## Backup Procedures

### PostgreSQL Backup

The backup script uses Docker to access PostgreSQL, so you don't need to install PostgreSQL client tools on your host machine.

#### Automated Backup Script

Use the provided backup script (requires Docker):

```bash
bash scripts/backup-postgres.sh
```

Or with custom options:

```bash
bash scripts/backup-postgres.sh --output ./backups --retention 7 --format sql
```

**Script Options:**
- `--output DIR`: Backup directory (default: `./backups`)
- `--retention DAYS`: Number of days to keep backups (default: 30)
- `--format FORMAT`: Backup format: `custom`, `sql`, or `tar` (default: `custom`)
- `--no-compress`: Disable compression
- `--container NAME`: Docker container name (default: `strapi-postgres`)

#### Manual Backup Using Docker

1. **Custom format (recommended):**
   ```bash
   docker exec strapi-postgres pg_dump -U strapi -d strapi -F c -f /tmp/backup.dump
   docker cp strapi-postgres:/tmp/backup.dump ./backup_$(date +%Y%m%d_%H%M%S).dump
   docker exec strapi-postgres rm -f /tmp/backup.dump
   ```

2. **SQL format:**
   ```bash
   docker exec strapi-postgres pg_dump -U strapi -d strapi -F p > backup_$(date +%Y%m%d_%H%M%S).sql
   ```

#### Restore from Backup

All restore operations use Docker (no PostgreSQL client tools required):

1. **From custom format (.dump):**
   ```bash
   docker cp backup_file.dump strapi-postgres:/tmp/restore.dump
   docker exec strapi-postgres pg_restore -U strapi -d strapi -c /tmp/restore.dump
   docker exec strapi-postgres rm -f /tmp/restore.dump
   ```

2. **From SQL file:**
   ```bash
   docker exec -i strapi-postgres psql -U strapi -d strapi < backup_file.sql
   ```

3. **From compressed SQL file:**
   ```bash
   gunzip -c backup_file.sql.gz | docker exec -i strapi-postgres psql -U strapi -d strapi
   ```

### SQLite Backup

If you still have the original SQLite database:

```bash
cp .tmp/data.db backups/data_backup_$(date +%Y%m%d_%H%M%S).db
```

### Backup Best Practices

1. **Regular backups:**
   - Daily backups for production
   - Before major updates or migrations
   - Before schema changes

2. **Backup storage:**
   - Store backups in a separate location
   - Use version control for configuration files only (not database dumps)
   - Consider cloud storage for important backups

3. **Backup verification:**
   - Test restore procedures periodically
   - Verify backup file integrity
   - Keep multiple backup versions

4. **Automation:**
   - Set up cron jobs for automated backups
   - Use the provided backup script with retention policies
   - Monitor backup success/failure

### Backup Script Features

The backup script (`scripts/backup-postgres.sh`) uses Docker and supports:

- **No PostgreSQL client tools required** - Uses Docker container
- **Multiple formats**: `custom` (recommended), `sql`, or `tar`
- **Automatic compression**: Gzip for SQL/TAR formats
- **Retention policy**: Automatically removes old backups
- **Error handling**: Checks if container is running before backup

Example cron job for daily backups at 2 AM:

```cron
0 2 * * * cd /path/to/project && bash scripts/backup-postgres.sh --retention 30
```

## Additional Resources

- [Strapi Documentation](https://docs.strapi.io)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review error logs
3. Consult Strapi and PostgreSQL documentation

