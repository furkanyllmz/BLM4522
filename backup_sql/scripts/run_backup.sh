#!/usr/bin/env bash
# ============================================================
# Otomatik Yedekleme Scripti
# Kullanım: ./run_backup.sh [full|diff]
#
# Bu script crontab veya pg_cron ile zamanlanarak otomatik
# yedekleme yapar. Her çalıştığında backup_history tablosuna
# kayıt düşer.
#
# Örnek crontab:
#   0 2 * * * /Users/furkanyilmaz/BLM4522_proje3/backup_sql/scripts/run_backup.sh full
# ============================================================

set -euo pipefail

# ---- Ayarlar ----
DB_NAME="backup_demo"
DB_USER="postgres"
PROJECT_DIR="/Users/furkanyilmaz/BLM4522_proje3/backup_sql"
BACKUP_DIR="${PROJECT_DIR}/backups"
WAL_ARCHIVE="${PROJECT_DIR}/wal_archive"
BACKUP_TYPE="${1:-full}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "${BACKUP_DIR}" "${WAL_ARCHIVE}"

echo "=========================================="
echo " Yedekleme baslatiliyor: ${BACKUP_TYPE}"
echo " Zaman: $(date)"
echo "=========================================="

# ---- Log: yedeği başlat ----
psql -U "${DB_USER}" -d "${DB_NAME}" -c \
  "CALL log_backup_run('${BACKUP_TYPE}', 'run_backup.sh ile otomatik calisti');" || true

case "${BACKUP_TYPE}" in
  full)
    # TAM YEDEK: custom format, sıkıştırılmış
    OUT_FILE="${BACKUP_DIR}/backup_demo_full_${TIMESTAMP}.dump"
    echo "Tam yedek aliniyor -> ${OUT_FILE}"
    pg_dump -U "${DB_USER}" -F c -b -v -f "${OUT_FILE}" "${DB_NAME}"
    ;;

  diff)
    # FARK YEDEK: WAL dosyalarını arşive kopyala (son tam yedekten beri)
    # PostgreSQL WAL switch ile mevcut segmenti kapatıp arşivlettirir
    echo "Fark yedek: WAL switch tetikleniyor..."
    psql -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT pg_switch_wal();"
    OUT_FILE="${WAL_ARCHIVE} (WAL arsivi)"
    ;;

  *)
    echo "HATA: Bilinmeyen yedek tipi '${BACKUP_TYPE}'. Kullanim: $0 [full|diff]"
    exit 1
    ;;
esac

# ---- Boyut hesapla (varsa) ----
if [[ -f "${OUT_FILE}" ]]; then
  SIZE_MB=$(du -m "${OUT_FILE}" | cut -f1)
else
  SIZE_MB=0
fi

# ---- Log: yedeği tamamla ----
psql -U "${DB_USER}" -d "${DB_NAME}" -c \
  "SELECT complete_backup((SELECT MAX(id) FROM backup_history), 'SUCCESS', '${OUT_FILE}', ${SIZE_MB});"

echo "=========================================="
echo " Yedekleme TAMAMLANDI: ${OUT_FILE} (${SIZE_MB} MB)"
echo "=========================================="
