-- ============================================================
-- ADIM 0: ETL Demo Veritabanı ve Şema Yapısı
-- Komut: psql -U postgres -f etl_sql/00_create_database.sql
--
-- ETL (Extract - Transform - Load) süreçleri için katmanlı
-- bir şema mimarisi kurulur:
--   staging -> ham, işlenmemiş kaynak veriler (EXTRACT)
--   clean   -> temizlenmiş ve dönüştürülmüş veriler (TRANSFORM)
--   target  -> nihai hedef tablolar (LOAD)
--
-- Bu katmanlı yapı, gerçek bir veri ambarı (data warehouse)
-- mimarisinin temel mantığıdır.
-- ============================================================

DROP DATABASE IF EXISTS etl_demo;

CREATE DATABASE etl_demo
    WITH
    OWNER      = postgres
    ENCODING   = 'UTF8'
    TEMPLATE   = template0;

\connect etl_demo

-- ============================================================
-- 0.1 KATMANLI ŞEMALAR
-- ============================================================

CREATE SCHEMA IF NOT EXISTS staging;   -- Ham kaynak veriler
CREATE SCHEMA IF NOT EXISTS clean;     -- Temizlenmiş veriler
CREATE SCHEMA IF NOT EXISTS target;    -- Hedef (nihai) veriler

COMMENT ON SCHEMA staging IS 'EXTRACT: Kaynaklardan gelen ham, islenmemis veri';
COMMENT ON SCHEMA clean   IS 'TRANSFORM: Temizlenmis ve standartlastirilmis veri';
COMMENT ON SCHEMA target  IS 'LOAD: Nihai hedef tablolar (raporlama icin)';

-- ============================================================
-- 0.2 ETL İŞLEM LOG TABLOSU
--
-- Her ETL adımı bu tabloya kaydedilir. Hangi adımda kaç satır
-- işlendi, kaç hata bulundu, ne kadar sürdü — hepsi izlenebilir.
-- ============================================================

CREATE TABLE IF NOT EXISTS target.etl_log (
    id            BIGSERIAL PRIMARY KEY,
    etl_step      VARCHAR(40)  NOT NULL,
    layer         VARCHAR(20),
    started_at    TIMESTAMPTZ  DEFAULT NOW(),
    finished_at   TIMESTAMPTZ,
    rows_in       BIGINT,
    rows_out      BIGINT,
    rows_rejected BIGINT,
    notes         TEXT
);

COMMENT ON TABLE target.etl_log IS 'ETL surec adimlarinin calisma kaydi';

-- Bir ETL adımını kaydeden yardımcı fonksiyon
CREATE OR REPLACE FUNCTION target.log_etl(
    p_step      VARCHAR,
    p_layer     VARCHAR,
    p_rows_in   BIGINT,
    p_rows_out  BIGINT,
    p_rejected  BIGINT DEFAULT 0,
    p_notes     TEXT   DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO target.etl_log
        (etl_step, layer, finished_at, rows_in, rows_out, rows_rejected, notes)
    VALUES
        (p_step, p_layer, NOW(), p_rows_in, p_rows_out, p_rejected, p_notes);
    RAISE NOTICE 'ETL [%]: giris=% cikis=% red=% | %',
        p_step, p_rows_in, p_rows_out, p_rejected, COALESCE(p_notes, '');
END $$;

\echo 'etl_demo veritabani ve katmanli semalar hazir (staging / clean / target).'
