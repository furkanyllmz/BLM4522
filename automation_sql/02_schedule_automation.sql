-- ============================================================
-- ADIM 2: Zamanlama Otomasyonu
-- Komut: psql -U postgres -d backup_demo -f automation_sql/02_schedule_automation.sql
--
-- Tanımlı job'ların belirlenen cron zamanlamasına göre OTOMATİK
-- çalışması. SQL Server Agent'ın "Schedule" özelliğinin karşılığı.
--
-- İki yöntem gösterilir:
--   A) pg_cron     -> veritabanı içinden zamanlama (job tablosundan)
--   B) crontab     -> işletim sistemi + scripts/backup_runner.sh
--
-- Bu dosya, job tablosundaki schedule_cron değerlerini gerçek
-- zamanlayıcı komutlarına dönüştürür.
-- ============================================================

\connect backup_demo

\echo '=========================================='
\echo ' ZAMANLAMA OTOMASYONU'
\echo '=========================================='

-- ============================================================
-- 2.1 JOB TANIMLARINDAN CRON SATIRLARI ÜRET
--
-- backup_job tablosundaki her aktif iş için crontab satırı üretir.
-- Çıktıyı doğrudan crontab'a yapıştırabilirsiniz.
-- ============================================================

\echo ''
\echo '--- 2.1 Otomatik uretilen crontab satirlari ---'

SELECT
    schedule_cron || '  '
    || '/Users/furkanyilmaz/BLM4522_proje3/automation_sql/scripts/backup_runner.sh '
    || job_id
    || '   # ' || job_name
    AS crontab_satiri
FROM backup_job
WHERE is_enabled
ORDER BY job_id;

-- ============================================================
-- 2.2 pg_cron İLE VERİTABANI İÇİ ZAMANLAMA
--
-- pg_cron kuruluysa, job tablosundaki işler doğrudan
-- veritabanı içinde zamanlanabilir.
-- ============================================================

\echo ''
\echo '--- 2.2 pg_cron ile zamanlama (uretilen komutlar) ---'

-- pg_cron kurulumu:  CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT
    format(
        'SELECT cron.schedule(%L, %L, %L);',
        'backup_job_' || job_id,
        schedule_cron,
        format('CALL sp_run_backup_job(%s);', job_id)
    ) AS pg_cron_komutu
FROM backup_job
WHERE is_enabled
ORDER BY job_id;

\echo ''
\echo 'Zamanlanmis isleri gormek icin: SELECT * FROM cron.job;'

-- ============================================================
-- 2.3 ZAMANLANMIŞ ÇALIŞMA SİMÜLASYONU
--
-- pg_cron yokken bile, zamanlayıcının bir günde job'ları nasıl
-- tetikleyeceğini simüle edelim (birkaç tur job çalıştır).
-- ============================================================

\echo ''
\echo '--- 2.3 Bir gunluk otomatik calisma simulasyonu ---'

DO $$
DECLARE
    v_job  RECORD;
    v_fail BOOLEAN;
BEGIN
    -- Her aktif job için 3 kez çalışmış gibi simüle et
    FOR i IN 1..3 LOOP
        FOR v_job IN SELECT job_id FROM backup_job WHERE is_enabled ORDER BY job_id LOOP
            -- %15 ihtimalle başarısızlık simüle et (uyarı tetiklenir)
            v_fail := (random() < 0.15);
            CALL sp_run_backup_job(v_job.job_id, p_force_fail => v_fail);
        END LOOP;
    END LOOP;
END $$;

\echo ''
\echo '--- Simulasyon sonrasi son 10 calisma ---'

SELECT
    id, job_id,
    backup_type AS tip,
    status      AS durum,
    started_at  AS baslangic
FROM backup_history
ORDER BY id DESC
LIMIT 10;

-- ============================================================
-- 2.4 JOB DURUM ÖZETİ
-- ============================================================

\echo ''
\echo '--- 2.4 Job bazli calisma ozeti ---'

SELECT
    j.job_name              AS is,
    COUNT(h.id)             AS toplam_calisma,
    COUNT(*) FILTER (WHERE h.status = 'SUCCESS') AS basarili,
    COUNT(*) FILTER (WHERE h.status = 'FAILED')  AS basarisiz
FROM backup_job j
LEFT JOIN backup_history h ON h.job_id = j.job_id
GROUP BY j.job_id, j.job_name
ORDER BY j.job_id;

\echo ''
\echo 'Zamanlama otomasyonu hazir.'
