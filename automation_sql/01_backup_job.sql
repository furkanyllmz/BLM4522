-- ============================================================
-- ADIM 1: Yedekleme İş (Job) Prosedürleri
-- Komut: psql -U postgres -d backup_demo -f automation_sql/01_backup_job.sql
--
-- "SQL Server Agent kullanarak yedekleme süreçlerini
--  otomatikleştirme"
--
-- SQL Server Agent'ın bir Job'u arka planda çalıştırıp sonucu
-- Job History'e yazmasının karşılığı: burada bir PL/pgSQL
-- prosedürü yedeklemeyi başlatır, sonucu backup_history'e
-- kaydeder ve başarısızlıkta hata yakalar.
--
-- NOT: Gerçek dosya yedeği (pg_dump) işletim sistemi seviyesinde
-- alınır; bu yüzden 02'deki shell script gerçek pg_dump çağırır.
-- Bu dosyadaki prosedür job'un VERİTABANI tarafını (kayıt, durum,
-- hata yönetimi) yönetir.
-- ============================================================

\connect backup_demo

\echo '=========================================='
\echo ' YEDEKLEME JOB PROSEDURLERI'
\echo '=========================================='

-- ============================================================
-- 1.1 JOB BAŞLAT: backup_history'e RUNNING kaydı aç
-- ============================================================

\echo ''
\echo '--- 1.1 sp_start_backup prosedru ---'

CREATE OR REPLACE FUNCTION sp_start_backup(p_job_id INT)
RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
    v_type VARCHAR;
    v_hist_id BIGINT;
BEGIN
    SELECT backup_type INTO v_type FROM backup_job WHERE job_id = p_job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job bulunamadi: %', p_job_id;
    END IF;

    INSERT INTO backup_history (job_id, backup_type, status, notes)
    VALUES (p_job_id, v_type, 'RUNNING', 'Job otomatik baslatildi')
    RETURNING id INTO v_hist_id;

    RAISE NOTICE 'Job % basladi (history_id=%)', p_job_id, v_hist_id;
    RETURN v_hist_id;
END $$;

-- ============================================================
-- 1.2 JOB BİTİR: başarı/başarısızlık durumunu yaz
-- ============================================================

\echo ''
\echo '--- 1.2 sp_finish_backup prosedru ---'

CREATE OR REPLACE FUNCTION sp_finish_backup(
    p_hist_id   BIGINT,
    p_success   BOOLEAN,
    p_path      TEXT     DEFAULT NULL,
    p_size_mb   NUMERIC  DEFAULT NULL,
    p_error     TEXT     DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
    v_start TIMESTAMPTZ;
BEGIN
    SELECT started_at INTO v_start FROM backup_history WHERE id = p_hist_id;

    UPDATE backup_history
    SET finished_at = NOW(),
        status      = CASE WHEN p_success THEN 'SUCCESS' ELSE 'FAILED' END,
        file_path   = p_path,
        file_size_mb= p_size_mb,
        error_msg   = p_error,
        duration_s  = EXTRACT(EPOCH FROM (NOW() - v_start))
    WHERE id = p_hist_id;

    RAISE NOTICE 'Job tamamlandi (history_id=%): %',
        p_hist_id, CASE WHEN p_success THEN 'SUCCESS' ELSE 'FAILED' END;
    -- Not: FAILED durumunda 05'teki trigger otomatik UYARI üretecek.
END $$;

-- ============================================================
-- 1.3 TEK PROSEDÜRDE TAM JOB ÇALIŞTIRMA (simülasyon)
--
-- Gerçekte yedeği shell script alır; bu prosedür job akışını
-- (başlat → çalış → bitir) tek yerde simüle eder. p_force_fail
-- ile başarısızlık senaryosu da test edilebilir.
-- ============================================================

\echo ''
\echo '--- 1.3 sp_run_backup_job (tam akis) ---'

CREATE OR REPLACE PROCEDURE sp_run_backup_job(
    p_job_id     INT,
    p_force_fail BOOLEAN DEFAULT FALSE
)
LANGUAGE plpgsql AS $$
DECLARE
    v_hist_id BIGINT;
    v_type    VARCHAR;
    v_path    TEXT;
    v_size    NUMERIC;
BEGIN
    -- Job aktif mi?
    IF NOT EXISTS (SELECT 1 FROM backup_job WHERE job_id = p_job_id AND is_enabled) THEN
        RAISE NOTICE 'Job % pasif veya yok, atlandi.', p_job_id;
        RETURN;
    END IF;

    SELECT backup_type INTO v_type FROM backup_job WHERE job_id = p_job_id;

    -- 1) Başlat
    v_hist_id := sp_start_backup(p_job_id);

    BEGIN
        -- 2) Yedekleme işi (simülasyon)
        IF p_force_fail THEN
            -- başarısızlık senaryosu (ör. disk dolu, yetki hatası)
            RAISE EXCEPTION 'Disk alani yetersiz - yedek alinamadi';
        END IF;

        -- başarı: gerçekçi dosya yolu ve boyut üret
        v_path := format('backup_sql/backups/%s_%s.dump',
                         v_type, to_char(NOW(), 'YYYYMMDD_HH24MISS'));
        v_size := ROUND((random() * 20 + 5)::NUMERIC, 2);  -- 5-25 MB arası

        -- kısa bir işlem süresi simülasyonu
        PERFORM pg_sleep(0.05);

        -- 3) Başarılı bitir
        PERFORM sp_finish_backup(v_hist_id, TRUE, v_path, v_size, NULL);

    EXCEPTION WHEN OTHERS THEN
        -- 3') Hata yakala ve FAILED olarak bitir
        PERFORM sp_finish_backup(v_hist_id, FALSE, NULL, NULL, SQLERRM);
        RAISE WARNING 'Job % BASARISIZ: %', p_job_id, SQLERRM;
    END;
END $$;

-- ============================================================
-- 1.4 TEST: BAŞARILI ve BAŞARISIZ job çalıştırma
-- ============================================================

\echo ''
\echo '--- 1.4 Test: basarili job calistirma ---'

CALL sp_run_backup_job(1);              -- Gunluk Tam Yedek (başarılı)
CALL sp_run_backup_job(2);              -- 6 Saatlik Fark (başarılı)

\echo ''
\echo '--- 1.4 Test: basarisiz job calistirma (uyari uretmeli) ---'

CALL sp_run_backup_job(3, p_force_fail => TRUE);  -- Saatlik Log (zorla başarısız)

-- Sonuç
\echo ''
\echo '--- Son job calismalari ---'

SELECT
    id, job_id,
    backup_type   AS tip,
    status        AS durum,
    ROUND(duration_s, 2) AS sure_s,
    file_size_mb  AS boyut_mb,
    COALESCE(error_msg, '-') AS hata
FROM backup_history
ORDER BY id DESC
LIMIT 5;

\echo ''
\echo 'Yedekleme job prosedurleri hazir ve test edildi.'
