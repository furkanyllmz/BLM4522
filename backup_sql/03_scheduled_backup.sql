-- ============================================================
-- ADIM 3: Zamanlayıcılarla Otomatik Yedekleme
--
-- Yedekleme işlerinin belirli aralıklarla OTOMATİK çalışması.
-- SQL Server'daki "SQL Server Agent Job" karşılığı.
--
-- PostgreSQL'de 3 yol vardır:
--   A) cron       -> işletim sistemi zamanlayıcısı (en yaygın)
--   B) pg_cron    -> veritabanı içi zamanlayıcı uzantısı
--   C) pgAgent    -> grafik arayüzlü iş zamanlayıcı
--
-- Bu dosya pg_cron yaklaşımını gösterir.
-- Çalıştırılabilir shell script: backup_sql/scripts/run_backup.sh
-- ============================================================

\connect backup_demo

\echo '=========================================='
\echo ' ZAMANLANMIS OTOMATIK YEDEKLEME'
\echo '=========================================='

-- ============================================================
-- 3.1 CRON İLE ZAMANLAMA (İşletim Sistemi Seviyesi)
-- ============================================================

\echo ''
\echo '--- 3.1 CRONTAB AYARLARI ---'
\echo 'crontab -e ile asagidaki satirlar eklenir:'
\echo ''
\echo '# Her gun gece 02:00 - TAM yedek'
\echo '0 2 * * * /Users/furkanyilmaz/BLM4522_proje3/backup_sql/scripts/run_backup.sh full'
\echo ''
\echo '# Her 6 saatte bir - FARK yedek'
\echo '0 */6 * * * /Users/furkanyilmaz/BLM4522_proje3/backup_sql/scripts/run_backup.sh diff'
\echo ''
\echo '# Pazar 03:00 - eski yedekleri temizle (7 gunden eski)'
\echo '0 3 * * 0 find /Users/furkanyilmaz/BLM4522_proje3/backup_sql/backups -name "*.dump" -mtime +7 -delete'

-- ============================================================
-- 3.2 pg_cron UZANTISI (Veritabanı İçi Zamanlama)
--
-- pg_cron, zamanlanmış işleri doğrudan veritabanında tutar.
-- Kurulum: postgresql.conf -> shared_preload_libraries = 'pg_cron'
-- ============================================================

\echo ''
\echo '--- 3.2 pg_cron ILE ZAMANLAMA ---'
\echo 'Uzanti kurulumu (superuser):'
\echo '   CREATE EXTENSION IF NOT EXISTS pg_cron;'

-- pg_cron varsa örnek iş tanımları (yorum satırı olarak güvenli)
-- SELECT cron.schedule('gunluk-tam-yedek', '0 2 * * *',
--     $$ CALL log_backup_run('full', 'pg_cron otomatik tam yedek') $$);
--
-- SELECT cron.schedule('saatlik-fark', '0 * * * *',
--     $$ CALL log_backup_run('diff', 'pg_cron otomatik fark yedek') $$);
--
-- Zamanlanmış işleri görmek için:
-- SELECT * FROM cron.job;

-- ============================================================
-- 3.3 YEDEKLEME LOG TABLOSU VE KAYIT PROSEDÜRÜ
--
-- Her otomatik yedek çalıştığında bu tabloya kayıt düşülür.
-- Bu, yedeklerin gerçekten çalışıp çalışmadığını izlemeyi sağlar.
-- ============================================================

\echo ''
\echo '--- 3.3 YEDEKLEME LOG ALTYAPISI ---'

CREATE TABLE IF NOT EXISTS backup_history (
    id            BIGSERIAL PRIMARY KEY,
    backup_type   VARCHAR(20)  NOT NULL,
    started_at    TIMESTAMPTZ  DEFAULT NOW(),
    finished_at   TIMESTAMPTZ,
    status        VARCHAR(20)  DEFAULT 'RUNNING',
    file_path     TEXT,
    file_size_mb  NUMERIC(12,2),
    notes         TEXT
);

COMMENT ON TABLE backup_history IS 'Otomatik yedekleme islerinin calisma gecmisi';

-- Yedek başlangıcını kaydeden prosedür
CREATE OR REPLACE PROCEDURE log_backup_run(
    p_type  VARCHAR,
    p_notes TEXT DEFAULT NULL
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO backup_history (backup_type, status, notes)
    VALUES (p_type, 'RUNNING', p_notes);
    RAISE NOTICE 'Yedekleme kaydi olusturuldu: % (%);', p_type, now();
END $$;

-- Yedek bitişini güncelleyen fonksiyon
CREATE OR REPLACE FUNCTION complete_backup(
    p_id        BIGINT,
    p_status    VARCHAR,
    p_path      TEXT DEFAULT NULL,
    p_size_mb   NUMERIC DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE backup_history
    SET finished_at  = NOW(),
        status       = p_status,
        file_path    = COALESCE(p_path, file_path),
        file_size_mb = COALESCE(p_size_mb, file_size_mb)
    WHERE id = p_id;
END $$;

-- ============================================================
-- 3.4 ÖRNEK ÇALIŞTIRMA (Manuel simülasyon)
-- ============================================================

\echo ''
\echo '--- 3.4 ORNEK YEDEK CALISTIRMA SIMULASYONU ---'

CALL log_backup_run('full', 'Manuel test - tam yedek simulasyonu');

-- Son kaydı tamamlanmış olarak işaretle
SELECT complete_backup(
    (SELECT MAX(id) FROM backup_history),
    'SUCCESS',
    'backup_sql/backups/backup_demo_full.dump',
    12.5
);

-- Geçmişi göster
SELECT
    id,
    backup_type   AS tip,
    status        AS durum,
    started_at    AS baslangic,
    finished_at   AS bitis,
    file_size_mb  AS boyut_mb,
    notes
FROM backup_history
ORDER BY id DESC
LIMIT 10;

\echo ''
\echo 'Zamanlanmis yedekleme altyapisi hazir.'
