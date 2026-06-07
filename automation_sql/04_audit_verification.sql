-- ============================================================
-- ADIM 4: Denetim ve Doğrulama
-- Komut: psql -U postgres -d backup_demo -f automation_sql/04_audit_verification.sql
--
-- "Yedeklerin düzenli olarak alındığını doğrulamak için denetim
--  ve raporlamalar"
--
-- Bu dosya, her job için tanımlı SLA (sla_hours) kuralına göre
-- yedeklerin GERÇEKTEN düzenli alınıp alınmadığını denetler:
--   • SLA ihlali: son başarılı yedek çok eski mi?
--   • Hiç yedek alınmamış job var mı?
--   • Boyutu anormal küçük/sıfır (şüpheli) yedek var mı?
--   • Genel uyumluluk skoru
--
-- Denetim sonuçları, 05'teki uyarı sistemini besler.
-- ============================================================

\connect backup_demo

\echo '=========================================='
\echo ' YEDEKLEME DENETIMI (AUDIT)'
\echo '=========================================='

-- ============================================================
-- 4.1 SLA İHLALİ DENETİMİ
--
-- Her job için: son başarılı yedek, SLA penceresinden eski mi?
-- (Örn. "Saatlik Log" 1 saat içinde alınmalı; 3 saattir yoksa ihlal.)
-- ============================================================

\echo ''
\echo '--- 4.1 SLA ihlal denetimi ---'

CREATE OR REPLACE VIEW v_sla_audit AS
SELECT
    j.job_id,
    j.job_name,
    j.backup_type,
    j.sla_hours,
    son.son_basarili,
    ROUND(EXTRACT(EPOCH FROM (NOW() - son.son_basarili)) / 3600, 1) AS gecen_saat,
    CASE
        WHEN son.son_basarili IS NULL THEN 'YEDEK YOK'
        WHEN EXTRACT(EPOCH FROM (NOW() - son.son_basarili)) / 3600 > j.sla_hours
             THEN 'SLA IHLALI'
        ELSE 'UYUMLU'
    END AS durum
FROM backup_job j
LEFT JOIN LATERAL (
    SELECT MAX(started_at) AS son_basarili
    FROM backup_history h
    WHERE h.job_id = j.job_id AND h.status = 'SUCCESS'
) son ON TRUE
WHERE j.is_enabled;

SELECT job_name AS is, sla_hours AS sla_saat, gecen_saat, durum
FROM v_sla_audit
ORDER BY job_id;

-- ============================================================
-- 4.2 SLA İHLALİ SİMÜLASYONU (denetimin çalıştığını göster)
--
-- Bir job'u kasıtlı olarak "eski" yapalım: son yedeğini geçmişe
-- alıp denetimin onu yakaladığını gösterelim.
-- ============================================================

\echo ''
\echo '--- 4.2 SLA ihlali senaryosu (Saatlik Log job geciktirildi) ---'

-- Saatlik Log job'unun (sla=1 saat) tüm yedeklerini 5 saat geçmişe al
-- (bunu sadece denetim demosu için yapıyoruz)
UPDATE backup_history
SET started_at = NOW() - interval '5 hours'
WHERE job_id = 3;

\echo 'Denetim tekrar calistirildi (Saatlik Log artik ihlalde olmali):'
SELECT job_name AS is, sla_hours AS sla_saat, gecen_saat, durum
FROM v_sla_audit
ORDER BY job_id;

-- ============================================================
-- 4.3 ŞÜPHELİ YEDEK DENETİMİ (boyut anomalisi)
--
-- Başarılı görünen ama boyutu çok küçük (<1 MB) veya NULL olan
-- yedekler şüphelidir — belki dosya bozuk/boş.
-- ============================================================

\echo ''
\echo '--- 4.3 Supheli yedekler (boyut anomalisi) ---'

SELECT
    id, job_id, backup_type AS tip, status,
    file_size_mb AS boyut_mb,
    'Boyut supheli kucuk/bos' AS uyari
FROM backup_history
WHERE status = 'SUCCESS'
  AND (file_size_mb IS NULL OR file_size_mb < 1)
ORDER BY id DESC
LIMIT 10;

-- ============================================================
-- 4.4 GENEL UYUMLULUK SKORU
--
-- Tüm job'ların kaçı SLA'ya uyuyor? (denetim özeti)
-- ============================================================

\echo ''
\echo '--- 4.4 Genel denetim uyumluluk skoru ---'

SELECT
    COUNT(*)                                            AS toplam_job,
    COUNT(*) FILTER (WHERE durum = 'UYUMLU')            AS uyumlu,
    COUNT(*) FILTER (WHERE durum = 'SLA IHLALI')        AS sla_ihlali,
    COUNT(*) FILTER (WHERE durum = 'YEDEK YOK')         AS yedek_yok,
    ROUND(
        COUNT(*) FILTER (WHERE durum = 'UYUMLU')::NUMERIC
        / NULLIF(COUNT(*), 0) * 100, 1
    )                                                   AS uyumluluk_pct
FROM v_sla_audit;

-- ============================================================
-- 4.5 DENETİM RAPORU FONKSİYONU (tek komutla denetim)
--
-- DBA bu fonksiyonu çağırarak anlık denetim özeti alabilir.
-- ============================================================

\echo ''
\echo '--- 4.5 fn_audit_summary (tek komut denetim) ---'

CREATE OR REPLACE FUNCTION fn_audit_summary()
RETURNS TABLE(denetim_basligi TEXT, sonuc TEXT)
LANGUAGE sql AS $$
    SELECT 'Toplam aktif job', COUNT(*)::TEXT FROM v_sla_audit
    UNION ALL
    SELECT 'SLA ihlali olan', COUNT(*)::TEXT FROM v_sla_audit WHERE durum = 'SLA IHLALI'
    UNION ALL
    SELECT 'Yedegi hic alinmamis', COUNT(*)::TEXT FROM v_sla_audit WHERE durum = 'YEDEK YOK'
    UNION ALL
    SELECT 'Son 24 saatte basarisiz', COUNT(*)::TEXT
        FROM backup_history WHERE status='FAILED' AND started_at >= NOW() - interval '24 hours'
    UNION ALL
    SELECT 'Genel durum',
        CASE WHEN EXISTS (SELECT 1 FROM v_sla_audit WHERE durum <> 'UYUMLU')
             THEN 'DIKKAT GEREKLI' ELSE 'TUM YEDEKLER GUNCEL' END;
$$;

SELECT * FROM fn_audit_summary();

\echo ''
\echo 'Denetim tamamlandi.'
