-- ============================================================
-- ADIM 7: Disk Alanı Yönetimi ve Tablo Bölümleme (Partitioning)
-- Komut: psql -U postgres -d stocks_db -f stocks_sql/07_disk_and_partition.sql
-- ============================================================

\connect stocks_db

-- ============================================================
-- 7.1 MEVCUT TABLO BOYUTU ANALİZİ
-- ============================================================

\echo '--- Disk alani kullanim raporu ---'

SELECT
    relname                                                     AS nesne,
    pg_size_pretty(pg_table_size(oid))                          AS veri_boyutu,
    pg_size_pretty(pg_indexes_size(oid))                        AS indeks_boyutu,
    pg_size_pretty(pg_total_relation_size(oid))                 AS toplam_boyut,
    ROUND(pg_indexes_size(oid)::NUMERIC /
          NULLIF(pg_table_size(oid), 0) * 100, 1)               AS indeks_veri_orani_pct
FROM pg_class
WHERE relname = 'stock_prices'
  AND relkind = 'r';

-- ============================================================
-- 7.2 YILI BAZLI VERİ DAĞILIMI
-- ============================================================

\echo '--- Yil bazli veri yogunlugu ---'

SELECT
    EXTRACT(YEAR FROM trade_date)::INT  AS yil,
    COUNT(*)                            AS kayit_sayisi,
    COUNT(DISTINCT symbol)              AS farkli_hisse,
    ROUND(COUNT(*) * 100.0 /
          SUM(COUNT(*)) OVER (), 2)     AS yuzdesi,
    pg_size_pretty(
        COUNT(*) * 100                  -- her satir ~100 byte tahmin
    )                                   AS tahmini_alan
FROM stock_prices
GROUP BY EXTRACT(YEAR FROM trade_date)
ORDER BY yil;

-- ============================================================
-- 7.3 YILA GÖRE BÖLÜMLENMIŞ TABLO (Range Partitioning)
-- Büyük tablolarda sorgu performansını artırmak için
-- ============================================================

\echo '--- Bolumlendirilmis tablo yapisi olusturuluyor ---'

-- Ana bölümlenmiş tablo
CREATE TABLE IF NOT EXISTS stock_prices_partitioned (
    id          BIGSERIAL,
    trade_date  DATE          NOT NULL,
    open_price  NUMERIC(12,4) NOT NULL,
    high_price  NUMERIC(12,4) NOT NULL,
    low_price   NUMERIC(12,4) NOT NULL,
    close_price NUMERIC(12,4) NOT NULL,
    volume      BIGINT        NOT NULL,
    symbol      VARCHAR(10)   NOT NULL,
    daily_change   NUMERIC(12,4) GENERATED ALWAYS AS (close_price - open_price) STORED,
    daily_range    NUMERIC(12,4) GENERATED ALWAYS AS (high_price - low_price) STORED,
    PRIMARY KEY (id, trade_date)
) PARTITION BY RANGE (trade_date);

-- Yıl bazlı bölümler
CREATE TABLE IF NOT EXISTS stock_prices_2013
    PARTITION OF stock_prices_partitioned
    FOR VALUES FROM ('2013-01-01') TO ('2014-01-01');

CREATE TABLE IF NOT EXISTS stock_prices_2014
    PARTITION OF stock_prices_partitioned
    FOR VALUES FROM ('2014-01-01') TO ('2015-01-01');

CREATE TABLE IF NOT EXISTS stock_prices_2015
    PARTITION OF stock_prices_partitioned
    FOR VALUES FROM ('2015-01-01') TO ('2016-01-01');

CREATE TABLE IF NOT EXISTS stock_prices_2016
    PARTITION OF stock_prices_partitioned
    FOR VALUES FROM ('2016-01-01') TO ('2017-01-01');

CREATE TABLE IF NOT EXISTS stock_prices_2017
    PARTITION OF stock_prices_partitioned
    FOR VALUES FROM ('2017-01-01') TO ('2018-01-01');

CREATE TABLE IF NOT EXISTS stock_prices_2018
    PARTITION OF stock_prices_partitioned
    FOR VALUES FROM ('2018-01-01') TO ('2019-01-01');

-- Bölümlenmiş tabloya indeks ekle (her bölüme otomatik yansır)
CREATE INDEX IF NOT EXISTS idx_part_symbol_date
    ON stock_prices_partitioned (symbol, trade_date DESC);

-- ============================================================
-- 7.4 VERİYİ BÖLÜMLENMIŞ TABLOYA KOPYALA
-- ============================================================

INSERT INTO stock_prices_partitioned
    (trade_date, open_price, high_price, low_price, close_price, volume, symbol)
SELECT trade_date, open_price, high_price, low_price, close_price, volume, symbol
FROM stock_prices;

ANALYZE stock_prices_partitioned;

-- ============================================================
-- 7.5 PARTITION PRUNING DOĞRULAMASI
-- Planlayıcının sadece ilgili bölümü taradığını göster
-- ============================================================

\echo '--- Partition pruning testi: sadece 2017 bolumu taranmali ---'

EXPLAIN (ANALYZE, BUFFERS)
SELECT symbol, AVG(close_price)
FROM stock_prices_partitioned
WHERE trade_date BETWEEN '2017-01-01' AND '2017-12-31'
GROUP BY symbol
ORDER BY AVG(close_price) DESC
LIMIT 10;

-- ============================================================
-- 7.6 BÖLÜM BOYUTLARI
-- ============================================================

\echo '--- Bolum boyutlari ---'

SELECT
    child.relname                                           AS bolum_adi,
    pg_size_pretty(pg_total_relation_size(child.oid))       AS boyut,
    pg_stat_get_live_tuples(child.oid)                      AS satir_sayisi
FROM pg_inherits
JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
JOIN pg_class child  ON pg_inherits.inhrelid  = child.oid
WHERE parent.relname = 'stock_prices_partitioned'
ORDER BY child.relname;

\echo 'Disk alani yonetimi ve bolümleme tamamlandi.'
