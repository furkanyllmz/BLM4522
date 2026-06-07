#!/usr/bin/env bash
# ============================================================
# Otomatik Yedekleme Job Runner (PowerShell scriptinin bash karşılığı)
# Kullanım: ./backup_runner.sh <job_id>
#
# crontab bu scripti çağırır; script de:
#   1) Veritabanındaki job prosedürünü çağırır (sp_run_backup_job)
#   2) GERÇEK pg_dump yedeği alır
#   3) Sonucu backup_history'e işler (başarı/başarısızlık)
#   4) Başarısızlıkta trigger otomatik uyarı üretir
#
# Örnek crontab:
#   0 2 * * * /.../automation_sql/scripts/backup_runner.sh 1
# ============================================================

set -uo pipefail

DB_NAME="backup_demo"
DB_USER="postgres"
JOB_ID="${1:?Kullanim: backup_runner.sh <job_id>}"
BACKUP_DIR="/Users/furkanyilmaz/BLM4522_proje3/backup_sql/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "${BACKUP_DIR}"

echo "=========================================="
echo " Job #${JOB_ID} calistiriliyor: $(date)"
echo "=========================================="

# 1) Job bilgisini al (tip)
BACKUP_TYPE=$(psql -U "${DB_USER}" -d "${DB_NAME}" -tAc \
    "SELECT backup_type FROM backup_job WHERE job_id=${JOB_ID} AND is_enabled;")

if [[ -z "${BACKUP_TYPE}" ]]; then
    echo "Job #${JOB_ID} bulunamadi veya pasif. Cikiliyor."
    exit 1
fi

# 2) Job'u başlat (RUNNING kaydı aç) ve history_id al
HIST_ID=$(psql -U "${DB_USER}" -d "${DB_NAME}" -tAc \
    "SELECT sp_start_backup(${JOB_ID});")
echo "History kaydi acildi: ${HIST_ID} (tip=${BACKUP_TYPE})"

# 3) GERÇEK yedekleme (pg_dump)
OUT_FILE="${BACKUP_DIR}/${BACKUP_TYPE}_job${JOB_ID}_${TIMESTAMP}.dump"
if pg_dump -U "${DB_USER}" -F c -f "${OUT_FILE}" "${DB_NAME}" 2> /tmp/backup_err.log; then
    SIZE_MB=$(du -m "${OUT_FILE}" | cut -f1)
    # 4a) Başarılı bitir
    psql -U "${DB_USER}" -d "${DB_NAME}" -c \
        "SELECT sp_finish_backup(${HIST_ID}, TRUE, '${OUT_FILE}', ${SIZE_MB}, NULL);"
    echo "BASARILI: ${OUT_FILE} (${SIZE_MB} MB)"
else
    ERR=$(tr "'" " " < /tmp/backup_err.log | tr '\n' ' ' | head -c 200)
    # 4b) Başarısız bitir -> trigger otomatik uyari uretir
    psql -U "${DB_USER}" -d "${DB_NAME}" -c \
        "SELECT sp_finish_backup(${HIST_ID}, FALSE, NULL, NULL, '${ERR}');"
    echo "BASARISIZ: ${ERR}"
    echo ">>> backup_alert tablosuna otomatik uyari dustu."
    exit 1
fi

# 5) SLA bekçi taramasını çalıştır (başka job'lar geciktiyse uyar)
psql -U "${DB_USER}" -d "${DB_NAME}" -c "CALL sp_check_sla_alerts();" > /dev/null 2>&1

echo "Job #${JOB_ID} tamamlandi."
