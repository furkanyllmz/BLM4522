-- ============================================================
-- ADIM 5: Otomatik Yedekleme Uyarıları
-- Komut: psql -U postgres -d backup_demo -f automation_sql/05_failure_alerts.sql
--
-- "Yedekleme işlemleri başarısız olduğunda yöneticilere bildirim
--  gönderme"
--
-- İki tetikleyici mekanizma kurulur:
--   A) TRIGGER  -> bir yedek FAILED olduğu ANDA otomatik uyarı üret
--   B) PROSEDÜR -> SLA ihlali / hiç yedek yok durumunda uyarı tara
--
-- Uyarılar backup_alert tablosuna düşer ve ilgili severity'deki
-- yöneticilere (backup_operator) yönlendirilir. RAISE WARNING ile
-- de anlık olarak görünür (SQL Server Operator bildirimi karşılığı).
-- ============================================================

\connect backup_demo

\echo '=========================================='
\echo ' OTOMATIK YEDEKLEME UYARILARI'
\echo '=========================================='

-- ============================================================
-- 5.1 UYARI OLUŞTURMA YARDIMCI FONKSİYONU
--
-- Uyarıyı tabloya yazar VE ilgili yöneticilere yönlendirir.
-- ============================================================

\echo ''
\echo '--- 5.1 fn_raise_alert (uyari + bildirim) ---'

CREATE OR REPLACE FUNCTION fn_raise_alert(
    p_severity   VARCHAR,
    p_type       VARCHAR,
    p_job_id     INT,
    p_message    TEXT
) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
    v_alert_id  BIGINT;
    v_targets   TEXT;
BEGIN
    -- Uyarıyı kaydet
    INSERT INTO backup_alert (severity, alert_type, job_id, message)
    VALUES (p_severity, p_type, p_job_id, p_message)
    RETURNING alert_id INTO v_alert_id;

    -- Bu severity'yi alması gereken yöneticileri belirle
    SELECT string_agg(email, ', ') INTO v_targets
    FROM backup_operator
    WHERE CASE min_severity
            WHEN 'INFO'     THEN TRUE
            WHEN 'WARNING'  THEN p_severity IN ('WARNING','CRITICAL')
            WHEN 'CRITICAL' THEN p_severity = 'CRITICAL'
          END;

    -- backup_alert'in notified_to alanını güncelle
    UPDATE backup_alert SET notified_to = COALESCE(v_targets, 'dba@sirket.com')
    WHERE alert_id = v_alert_id;

    -- Anlık bildirim (Operator'a "e-posta" karşılığı)
    RAISE WARNING '[BILDIRIM -> %] %: % (job=%)',
        COALESCE(v_targets, 'dba@sirket.com'), p_severity, p_message, p_job_id;

    RETURN v_alert_id;
END $$;

-- ============================================================
-- 5.2 TRIGGER: Yedek FAILED olunca OTOMATİK uyarı
--
-- backup_history'de status FAILED'e dönen her satır için
-- otomatik olarak uyarı üretilir. Yönetici hiçbir şey yapmadan
-- bildirim oluşur.
-- ============================================================

\echo ''
\echo '--- 5.2 Otomatik uyari trigger kuruluyor ---'

CREATE OR REPLACE FUNCTION trg_backup_failed()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    -- Sadece FAILED'e GEÇİŞ anında tetikle (zaten FAILED ise tekrar etme)
    IF NEW.status = 'FAILED'
       AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'FAILED') THEN

        PERFORM fn_raise_alert(
            'CRITICAL',
            'BACKUP_FAILED',
            NEW.job_id,
            format('Yedekleme BASARISIZ oldu (history_id=%s, tip=%s): %s',
                   NEW.id, NEW.backup_type, COALESCE(NEW.error_msg, 'bilinmeyen hata'))
        );
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tr_backup_failed ON backup_history;
CREATE TRIGGER tr_backup_failed
    AFTER INSERT OR UPDATE OF status ON backup_history
    FOR EACH ROW
    EXECUTE FUNCTION trg_backup_failed();

\echo 'Trigger kuruldu: backup_history FAILED -> otomatik CRITICAL uyari.'

-- ============================================================
-- 5.3 TEST: Başarısız yedek -> trigger otomatik uyarı üretmeli
-- ============================================================

\echo ''
\echo '--- 5.3 Test: basarisiz job (trigger tetiklenmeli) ---'

-- 01'deki prosedürle zorla başarısız bir job çalıştır
CALL sp_run_backup_job(1, p_force_fail => TRUE);

\echo 'Trigger ile uretilen uyari:'
SELECT alert_id, severity, alert_type, job_id, LEFT(message, 60) AS mesaj, notified_to
FROM backup_alert
ORDER BY alert_id DESC
LIMIT 3;

-- ============================================================
-- 5.4 SLA İHLALİ TARAMASI -> uyarı üret
--
-- 04'teki v_sla_audit görünümünü kullanarak, SLA ihlali veya
-- hiç yedek olmayan job'lar için uyarı üretir. Bu, zamanlanmış
-- bir "bekçi" (watchdog) olarak periyodik çalıştırılabilir.
-- ============================================================

\echo ''
\echo '--- 5.4 sp_check_sla_alerts (SLA bekci taramasi) ---'

CREATE OR REPLACE PROCEDURE sp_check_sla_alerts()
LANGUAGE plpgsql AS $$
DECLARE
    v_rec  RECORD;
    v_cnt  INT := 0;
BEGIN
    FOR v_rec IN
        SELECT job_id, job_name, durum, gecen_saat, sla_hours
        FROM v_sla_audit
        WHERE durum <> 'UYUMLU'
    LOOP
        -- Aynı job için son 1 saatte zaten uyarı varsa tekrar etme (spam önleme)
        IF NOT EXISTS (
            SELECT 1 FROM backup_alert
            WHERE job_id = v_rec.job_id
              AND alert_type IN ('SLA_BREACH','NO_BACKUP')
              AND created_at >= NOW() - interval '1 hour'
        ) THEN
            PERFORM fn_raise_alert(
                CASE WHEN v_rec.durum = 'YEDEK YOK' THEN 'CRITICAL' ELSE 'WARNING' END,
                CASE WHEN v_rec.durum = 'YEDEK YOK' THEN 'NO_BACKUP' ELSE 'SLA_BREACH' END,
                v_rec.job_id,
                format('%s: "%s" icin son yedek %s saat once (SLA: %s saat)',
                       v_rec.durum, v_rec.job_name,
                       COALESCE(v_rec.gecen_saat::TEXT, 'YOK'), v_rec.sla_hours)
            );
            v_cnt := v_cnt + 1;
        END IF;
    END LOOP;

    RAISE NOTICE 'SLA taramasi tamamlandi: % yeni uyari uretildi.', v_cnt;
END $$;

\echo 'SLA bekci taramasi calistiriliyor:'
CALL sp_check_sla_alerts();

-- ============================================================
-- 5.5 AKTİF UYARILAR PANOSU (yöneticinin göreceği)
-- ============================================================

\echo ''
\echo '--- 5.5 Aktif (cozulmemis) uyarilar panosu ---'

SELECT
    a.alert_id,
    a.created_at::TIMESTAMP(0)  AS zaman,
    a.severity                  AS oncelik,
    a.alert_type                AS tip,
    j.job_name                  AS is,
    LEFT(a.message, 55)         AS mesaj,
    a.notified_to               AS bildirildi
FROM backup_alert a
LEFT JOIN backup_job j ON a.job_id = j.job_id
WHERE NOT a.is_resolved
ORDER BY
    CASE a.severity WHEN 'CRITICAL' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END,
    a.created_at DESC;

-- ============================================================
-- 5.6 UYARI ÖZETİ (severity dağılımı)
-- ============================================================

\echo ''
\echo '--- 5.6 Uyari ozeti ---'

SELECT
    severity        AS oncelik,
    alert_type      AS tip,
    COUNT(*)        AS adet,
    COUNT(*) FILTER (WHERE NOT is_resolved) AS cozulmemis
FROM backup_alert
GROUP BY severity, alert_type
ORDER BY
    CASE severity WHEN 'CRITICAL' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END,
    alert_type;

\echo ''
\echo 'Otomatik uyari sistemi kuruldu ve test edildi.'
