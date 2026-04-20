-- ============================================================
-- ADIM 6: İndeks Yönetimi - Kullanım Analizi ve Temizlik
-- Komut: psql -U postgres -d stocks_db -f stocks_sql/06_index_management.sql
-- ============================================================

\connect stocks_db

-- ============================================================
-- 6.1 KULLANILMAYAN İNDEKSLERİ TESPİT ET
-- ============================================================

\echo '--- Kullanilmayan indeksler (kaldirma adaylari) ---'

SELECT
    schemaname                                          AS sema,
    relname                                             AS tablo,
    indexrelname                                        AS indeks,
    idx_scan                                            AS kullanim_sayisi,
    pg_size_pretty(pg_relation_size(indexrelid))        AS boyut,
    CASE
        WHEN idx_scan = 0 THEN 'KALDIR - Hic kullanilmamis'
        WHEN idx_scan < 10 THEN 'GOZDEN GECIR - Az kullaniliyor'
        ELSE 'Aktif - Koru'
    END AS oneri
FROM pg_stat_user_indexes
JOIN pg_index USING (indexrelid)
WHERE relname = 'stock_prices'
  AND NOT indisunique
  AND NOT indisprimary
ORDER BY idx_scan ASC, pg_relation_size(indexrelid) DESC;

-- ============================================================
-- 6.2 İNDEKS BLOAT ANALİZİ
-- ============================================================

\echo '--- Indeks bloat analizi ---'

SELECT
    indexrelname                                        AS indeks,
    pg_size_pretty(pg_relation_size(indexrelid))        AS mevcut_boyut,
    idx_scan                                            AS tarama_sayisi,
    idx_tup_read                                        AS okunan_tuple,
    ROUND(idx_tup_read::NUMERIC /
          NULLIF(idx_scan, 0), 1)                       AS tarama_basina_tuple
FROM pg_stat_user_indexes
WHERE relname = 'stock_prices'
ORDER BY pg_relation_size(indexrelid) DESC;

-- ============================================================
-- 6.3 GEREKSİZ İNDEKSİ KALDIR (Örnek)
-- Aşağıdaki indeks symbol+date bileşik indeks tarafından karşılandığından
-- tek başına symbol indeksi çoğu durumda gereksizdir.
-- ============================================================

-- DIKKAT: Kaldırmadan önce kullanım istatistiklerini kontrol edin!
-- DROP INDEX CONCURRENTLY IF EXISTS idx_stock_symbol;

-- Kaldırma yerine bir rapor üret:
\echo '--- Potansiyel duplike indeks kontrolu ---'

SELECT
    a.indexrelname  AS indeks_1,
    b.indexrelname  AS indeks_2,
    a.relname       AS tablo,
    'Indeks_1 Indeks_2 ile kapsaniyor olabilir' AS uyari
FROM pg_stat_user_indexes a
JOIN pg_stat_user_indexes b
     ON a.relname = b.relname
    AND a.indexrelid < b.indexrelid
WHERE a.relname = 'stock_prices';

-- ============================================================
-- 6.4 YENİ İNDEKS ETKİSİNİ TEST ET (CONCURRENT BUILD)
-- Üretim ortamında tablo kilitlemeden indeks oluşturma
-- ============================================================

-- Örnek: Yıl + sembol için yeni indeks CONCURRENT oluşturma
-- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_stock_year_symbol
--     ON stock_prices (EXTRACT(YEAR FROM trade_date)::INT, symbol);

-- ============================================================
-- 6.5 VACUUM ve ANALYZE
-- Bloat temizleme ve istatistik güncelleme
-- ============================================================

\echo '--- VACUUM ANALYZE calistiriliyor ---'

VACUUM ANALYZE stock_prices;

-- Vacuum sonrası durum
SELECT
    relname,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze,
    n_dead_tup                          AS olü_satir_kalan,
    vacuum_count,
    analyze_count
FROM pg_stat_user_tables
WHERE relname = 'stock_prices';

-- ============================================================
-- 6.6 İNDEKS BOYUT ÖZET RAPORU
-- ============================================================

\echo '--- Indeks boyut ozet raporu ---'

SELECT
    indexrelname                                        AS indeks_adi,
    pg_size_pretty(pg_relation_size(indexrelid))        AS boyut,
    idx_scan                                            AS kullanim,
    CASE indisunique WHEN true THEN 'UNIQUE' ELSE '-' END AS tip
FROM pg_stat_user_indexes
JOIN pg_index USING (indexrelid)
WHERE relname = 'stock_prices'
ORDER BY pg_relation_size(indexrelid) DESC;

\echo 'Indeks yonetim analizi tamamlandi.'
