-- ============================================================
-- ADIM 0: Veritabanı Oluşturma
-- Komut: psql -U postgres -f stocks_sql/00_create_database.sql
-- ============================================================

DROP DATABASE IF EXISTS stocks_db;

CREATE DATABASE stocks_db
    WITH
    OWNER      = postgres
    ENCODING   = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE   = 'en_US.UTF-8'
    TEMPLATE   = template0;

\connect stocks_db

-- Performans izleme için gerekli uzantılar
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pgstattuple;

\echo 'stocks_db veritabani hazir.'
