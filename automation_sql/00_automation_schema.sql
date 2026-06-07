-- ============================================================
-- ADIM 0: Yedekleme Otomasyon ve Denetim Altyapısı
-- Komut: psql -U postgres -d backup_demo -f automation_sql/00_automation_schema.sql
--
-- Bu proje, backup_sql'de kurulan backup_demo veritabanını ve
-- backup_history tablosunu KULLANIR. Üzerine otomasyon, denetim
-- ve uyarı katmanını ekler:
--   backup_job        -> tanımlı yedekleme işleri (Agent Job karşılığı)
--   backup_alert      -> başarısızlık/uyarı kayıtları
--   backup_policy     -> "ne sıklıkla yedek alınmalı" denetim kuralları
--
-- SQL Server karşılıkları:
--   SQL Server Agent Job   -> backup_job + prosedürler
--   Job History            -> backup_history (mevcut)
--   Operator/Alert         -> backup_alert + trigger
-- ============================================================

\connect backup_demo

\echo '=========================================='
\echo ' YEDEKLEME OTOMASYON ALTYAPISI'
\echo '=========================================='

-- ============================================================
-- 0.1 backup_history GENİŞLETME (denetim için ek sütunlar)
--
-- Mevcut tabloyu bozmadan, denetim için gereken sütunları
-- (yoksa) ekleriz.
-- ============================================================

\echo ''
\echo '--- 0.1 backup_history denetim sutunlari ---'

ALTER TABLE backup_history ADD COLUMN IF NOT EXISTS job_id      INT;
ALTER TABLE backup_history ADD COLUMN IF NOT EXISTS duration_s  NUMERIC(10,2);
ALTER TABLE backup_history ADD COLUMN IF NOT EXISTS error_msg   TEXT;

-- ============================================================
-- 0.2 backup_job — TANIMLI YEDEKLEME İŞLERİ
--
-- SQL Server Agent'taki "Job" tanımının karşılığı. Hangi iş,
-- ne tipte, hangi sıklıkta çalışmalı — burada tanımlanır.
-- ============================================================

\echo ''
\echo '--- 0.2 backup_job tablosu ---'

DROP TABLE IF EXISTS backup_job CASCADE;
CREATE TABLE backup_job (
    job_id         SERIAL PRIMARY KEY,
    job_name       VARCHAR(60)  NOT NULL UNIQUE,
    backup_type    VARCHAR(20)  NOT NULL,          -- full / diff / log
    schedule_cron  VARCHAR(40),                    -- ör. '0 2 * * *'
    sla_hours      INT          NOT NULL DEFAULT 24,-- en fazla kaç saatte bir alınmalı
    is_enabled     BOOLEAN      DEFAULT TRUE,
    created_at     TIMESTAMPTZ  DEFAULT NOW()
);

COMMENT ON TABLE backup_job IS 'Tanimli yedekleme isleri (SQL Server Agent Job karsiligi)';
COMMENT ON COLUMN backup_job.sla_hours IS 'Denetim esigi: bu surede bir yedek alinmazsa UYARI';

-- Örnek job tanımları
INSERT INTO backup_job (job_name, backup_type, schedule_cron, sla_hours) VALUES
    ('Gunluk Tam Yedek',   'full', '0 2 * * *',   24),  -- her gün 02:00, 24 saat SLA
    ('6 Saatlik Fark',     'diff', '0 */6 * * *',  6),  -- her 6 saat, 6 saat SLA
    ('Saatlik Log Yedek',  'log',  '0 * * * *',    1);  -- her saat, 1 saat SLA

SELECT job_id, job_name, backup_type, schedule_cron, sla_hours, is_enabled FROM backup_job;

-- ============================================================
-- 0.3 backup_alert — UYARI / BİLDİRİM KAYITLARI
--
-- Yedekleme başarısız olduğunda veya SLA ihlal edildiğinde
-- buraya kayıt düşülür. Yöneticiye "bildirim" bu tabloda tutulur.
-- ============================================================

\echo ''
\echo '--- 0.3 backup_alert tablosu ---'

DROP TABLE IF EXISTS backup_alert CASCADE;
CREATE TABLE backup_alert (
    alert_id     BIGSERIAL PRIMARY KEY,
    created_at   TIMESTAMPTZ DEFAULT NOW(),
    severity     VARCHAR(10)  DEFAULT 'WARNING',   -- INFO / WARNING / CRITICAL
    alert_type   VARCHAR(30),                      -- BACKUP_FAILED / SLA_BREACH / NO_BACKUP
    job_id       INT,
    message      TEXT,
    is_resolved  BOOLEAN DEFAULT FALSE,
    notified_to  VARCHAR(100) DEFAULT 'dba@sirket.com'
);

COMMENT ON TABLE backup_alert IS 'Yedekleme uyarilari (Operator/Alert bildirimi karsiligi)';

-- ============================================================
-- 0.4 YÖNETİCİ (OPERATOR) TANIMLARI
--
-- Uyarıların kime gideceği. SQL Server "Operator" karşılığı.
-- ============================================================

\echo ''
\echo '--- 0.4 yonetici (operator) tanimlari ---'

DROP TABLE IF EXISTS backup_operator CASCADE;
CREATE TABLE backup_operator (
    operator_id  SERIAL PRIMARY KEY,
    ad_soyad     VARCHAR(60),
    email        VARCHAR(100),
    min_severity VARCHAR(10) DEFAULT 'WARNING'    -- bu seviye ve üstü uyarıları alır
);

INSERT INTO backup_operator (ad_soyad, email, min_severity) VALUES
    ('Furkan Yilmaz (DBA)',  'dba@sirket.com',      'WARNING'),
    ('Sistem Yoneticisi',    'sysadmin@sirket.com', 'CRITICAL');

SELECT operator_id, ad_soyad, email, min_severity FROM backup_operator;

\echo ''
\echo 'Otomasyon altyapisi hazir (backup_job / backup_alert / backup_operator).'
