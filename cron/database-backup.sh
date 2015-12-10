#!/bin/bash

if [ "$DISABLE_BACKUP" == "1" ]; then
    exit 0
fi

# Remove backups older than RECYCLE_DAYS
RECYCLE_DAYS=${RECYCLE_DAYS:-7}

# Where to store backups
BACKUP_DIR="${BACKUP_DIR:-${OPENSHIFT_DATA_DIR}backup/}"

# Execute over every backup file
# Subtitute {} with file name (like find's -exec)
ACTION='scl enable python27 "$OPENSHIFT_REPO_DIR/.openshift/backup-dropbox-wrapper.sh $OPENSHIFT_REPO_DIR/.openshift/backup-dropbox.py put {}"'

# Don't need to touch below
#####################################################

set -eu

if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
fi

TIMESTAMP=`date +%s`
ISODATE=`date --rfc-3339=seconds "--date=@$TIMESTAMP" | tr -s ' ' _` # Format: 1970-01-01_00:00:00+00:00

function info() { echo -r "$*"; }
function error() { echo -r "\n[ERR] $*"; }

function remove_old_backup()
{
    if [ -d "$1" ]; then
        ( cd $1 && find . -maxdepth 1 -type f -mtime "+$RECYCLE_DAYS" -exec rm -f {} \; )
    fi
}

function do_action()
{
    bash -c "`echo "$ACTION" | sed -e "s|{}|$1|g"`"
}

function backup_database()
{
    local NAME="$1"
    shift
    local CMD="$*"

    cd "$BACKUP_DIR"
    local FILENAME="${NAME}-${ISODATE}.gz"
    local OUTPATH="${BACKUP_DIR}/$FILENAME"
    echo -n "$NAME --> "
    if $CMD | gzip > "$OUTPATH"; then
        if [ -n "$ACTION" ]; then
            do_action "$OUTPATH" || echo " failed"
        else
            echo "$FILENAME (local only)"
        fi
    fi
}

function backup_mysql()
{
    local DB_NAME="${BACKUP_MYSQL_DB_NAME:-$OPENSHIFT_APP_NAME}"
    local DB_PARAMS="${BACKUP_MYSQL_DB_PARAM:-}"
    backup_database mysql mysqldump $DB_PARAMS \
        -h "$OPENSHIFT_MYSQL_DB_HOST" \
        -P "$OPENSHIFT_MYSQL_DB_PORT" \
        -u "$OPENSHIFT_MYSQL_DB_USERNAME" \
        "-p$OPENSHIFT_MYSQL_DB_PASSWORD" \
        "$DB_NAME"
}

function backup_postgresql()
{
    local DB_NAME="${BACKUP_POSTGRESQL_DB_NAME:-$OPENSHIFT_APP_NAME}"
    local DB_PARAMS="${BACKUP_POSTGRESQL_DB_PARAMS:-}"
    backup_database postgresql pg_dump $DB_PARAMS \
        -h "$OPENSHIFT_POSTGRESQL_DB_HOST" \
        -p "$OPENSHIFT_POSTGRESQL_DB_PORT" \
        -U "$OPENSHIFT_POSTGRESQL_DB_USERNAME" \
        "$DB_NAME"
}

function mongodb_dump()
{
    local DB_NAME="${BACKUP_MONGODB_DB_NAME:-$OPENSHIFT_APP_NAME}"
    local DB_PARAMS="${BACKUP_MONGODB_DB_PARAMS:-}"
    local DUMPDIR="dump_$TIMESTAMP"
    mongodump $DB_PARAMS \
        --db "$DB_NAME" \
        --host "$OPENSHIFT_MONGODB_DB_HOST" \
        --port "$OPENSHIFT_MONGODB_DB_PORT" \
        --username "$OPENSHIFT_MONGODB_DB_USERNAME" \
        --password "$OPENSHIFT_MONGODB_DB_PASSWORD" \
        --out "$DUMPDIR" > /dev/null
    tar cf - "$DUMPDIR" && rm -rf "$DUMPDIR" >/dev/null || rm -rf "$DUMPDIR" >/dev/null
}

function backup_mongodb()
{
    backup_database mongodb mongodb_dump
}

if [ "${OPENSHIFT_MYSQL_DB_HOST}${OPENSHIFT_POSTGRESQL_DB_HOST}${OPENSHIFT_MONGODB_DB_HOST}" ]; then
    info "--- Backup start - [`date`]\n"
    remove_old_backup $BACKUP_DIR
    [ "${OPENSHIFT_MYSQL_DB_HOST}"      ] && backup_mysql || true
    [ "${OPENSHIFT_POSTGRESQL_DB_HOST}" ] && backup_postgresql || true
    [ "${OPENSHIFT_MONGODB_DB_HOST}"    ] && backup_mongodb || true
    info "\n--- Backup finished [`date`]"
fi
