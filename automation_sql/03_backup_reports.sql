-- ============================================================
-- ADIM 3: Yedekleme Raporları (T-SQL / Scripting Karşılığı)
-- Komut: psql -U postgres -d backup_demo -f automation_sql/03_backup_reports.sql
--
-- "PowerShell veya T-SQL Scripting ile yedekleme raporları
--  oluşturma"
--
-- Bu dosya, backup_history verisinden yöneticinin görmek
-- isteyeceği raporları üretir:
--   • Günlük yedekleme durum panosu
--   • İş (job) bazlı başarı oranı
--   • Boyut ve süre trendi
--   • Son N gün özet
--
-- NOT: Raporların geçmiş günleri de göstermesi için önce
-- gerçekçi tarihsel test verisi üretilir (son 7 gün).
-- ============================================================

\connect backup_demo

\echo '=========================================='
\echo ' YEDEKLEME RAPORLARI'
\echo '=========================================='

-- ============================================================
-- 3.1 GEÇMİŞ 7 GÜN İÇİN GERÇEKÇİ TEST VERİSİ
--
-- Her gün her job çalışmış gibi tarihsel kayıt üretiriz.
-- Böylece günlük trend raporları anlamlı olur.
-- ============================================================

\echo ''
\echo '--- 3.1 Son 7 gun icin tarihsel veri uretiliyor ---'

-- Önceki simülasyon verisini koru, sadece geçmiş günleri ekle
INSERT INTO backup_history
    (job_id, backup_type, started_at, finished_at, status, file_path, file_size_mb, duration_s, error_msg)
SELECT
    j.job_id,
    j.backup_type,
    gun + TIME '02:00',
    gun + TIME '02:00' + (random() * interval '5 minutes'),
    -- %90 başarı, %10 başarısızlık
    CASE WHEN random() < 0.90 THEN 'SUCCESS' ELSE 'FAILED' END,
    format('backup_sql/backups/%s_%s.dump', j.backup_type, to_char(gun, 'YYYYMMDD')),
    ROUND((random() * 20 + 5)::NUMERIC, 2),
    ROUND((random() * 200 + 30)::NUMERIC, 2),
    NULL
FROM backup_job j
CROSS JOIN generate_series(
    (CURRENT_DATE - 7),
    (CURRENT_DATE - 1),
    interval '1 day'
) AS gun
WHERE j.is_enabled;

-- FAILED olanlara hata mesajı yaz
UPDATE backup_history
SET error_msg = 'Yedekleme zaman asimina ugradi'
WHERE status = 'FAILED' AND error_msg IS NULL;

SELECT COUNT(*) AS toplam_kayit FROM backup_history;

-- ============================================================
-- 3.2 GÜNLÜK YEDEKLEME DURUM PANOSU
-- ============================================================

\echo ''
\echo '--- 3.2 Gunluk yedekleme durum panosu ---'

SELECT
    started_at::DATE                                AS tarih,
    COUNT(*)                                        AS toplam_yedek,
    COUNT(*) FILTER (WHERE status = 'SUCCESS')      AS basarili,
    COUNT(*) FILTER (WHERE status = 'FAILED')       AS basarisiz,
    ROUND(
        COUNT(*) FILTER (WHERE status = 'SUCCESS')::NUMERIC
        / NULLIF(COUNT(*), 0) * 100, 1
    )                                               AS basari_pct,
    pg_size_pretty((SUM(file_size_mb) * 1024 * 1024)::BIGINT) AS toplam_boyut
FROM backup_history
WHERE started_at >= CURRENT_DATE - 7
GROUP BY started_at::DATE
ORDER BY tarih DESC;

-- ============================================================
-- 3.3 İŞ (JOB) BAZLI BAŞARI ORANI RAPORU
-- ============================================================

\echo ''
\echo '--- 3.3 Job bazli basari orani ---'

SELECT
    j.job_name                                      AS is_adi,
    j.backup_type                                   AS tip,
    COUNT(h.id)                                     AS calisma_sayisi,
    COUNT(*) FILTER (WHERE h.status = 'SUCCESS')    AS basarili,
    COUNT(*) FILTER (WHERE h.status = 'FAILED')     AS basarisiz,
    ROUND(
        COUNT(*) FILTER (WHERE h.status = 'SUCCESS')::NUMERIC
        / NULLIF(COUNT(h.id), 0) * 100, 1
    )                                               AS basari_pct,
    ROUND(AVG(h.duration_s) FILTER (WHERE h.status='SUCCESS'), 1) AS ort_sure_s,
    ROUND(AVG(h.file_size_mb) FILTER (WHERE h.status='SUCCESS'), 2) AS ort_boyut_mb
FROM backup_job j
LEFT JOIN backup_history h ON h.job_id = j.job_id
GROUP BY j.job_id, j.job_name, j.backup_type
ORDER BY j.job_id;

-- ============================================================
-- 3.4 SON BAŞARILI YEDEK (job başına) — "en güncel yedek"
-- ============================================================

\echo ''
\echo '--- 3.4 Her job icin son basarili yedek ---'

SELECT DISTINCT ON (j.job_id)
    j.job_name                          AS is_adi,
    h.started_at                        AS son_basarili_yedek,
    ROUND(EXTRACT(EPOCH FROM (NOW() - h.started_at)) / 3600, 1) AS kac_saat_once,
    h.file_size_mb                      AS boyut_mb
FROM backup_job j
JOIN backup_history h ON h.job_id = j.job_id AND h.status = 'SUCCESS'
ORDER BY j.job_id, h.started_at DESC;

-- ============================================================
-- 3.5 BOYUT TRENDİ (büyüme takibi — kapasite planlama)
-- ============================================================

\echo ''
\echo '--- 3.5 Gunluk yedek boyut trendi (full) ---'

SELECT
    started_at::DATE        AS tarih,
    ROUND(SUM(file_size_mb), 2) AS toplam_mb,
    ROUND(AVG(file_size_mb), 2) AS ort_mb
FROM backup_history
WHERE backup_type = 'full' AND status = 'SUCCESS'
  AND started_at >= CURRENT_DATE - 7
GROUP BY started_at::DATE
ORDER BY tarih;

\echo ''
\echo 'Yedekleme raporlari olusturuldu.'
