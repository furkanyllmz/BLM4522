-- ============================================================
-- ADIM 3: CSV Veri Yükleme
-- Komut: psql -U postgres -d stocks_db -f stocks_sql/03_load_data.sql
-- NOT: CSV dosyasının tam yolunu kendi sisteminize göre düzenleyin.
-- ============================================================

\connect stocks_db

-- Yükleme öncesi performans ölçümü
DO $$
DECLARE v_start TIMESTAMPTZ := clock_timestamp();
BEGIN
    RAISE NOTICE 'Veri yukleme basliyor: %', v_start;
END $$;

-- İndeksleri geçici olarak devre dışı bırak (bulk insert hızlandırma)
UPDATE pg_index SET indisready = false
WHERE indrelid = 'stock_prices'::regclass
  AND indexrelid <> (
      SELECT indexrelid FROM pg_index
      WHERE indrelid = 'stock_prices'::regclass AND indisprimary
  );

-- CSV'den yükle (yolu kendi ortamınıza göre değiştirin)
\COPY stock_prices (trade_date, open_price, high_price, low_price, close_price, volume, symbol)
FROM '/Users/furkanyilmaz/BLM4522_proje3/all_stocks_5yr.csv'
WITH (
    FORMAT CSV,
    HEADER TRUE,
    DELIMITER ','
);

-- İndeksleri yeniden etkinleştir
UPDATE pg_index SET indisready = true
WHERE indrelid = 'stock_prices'::regclass;

-- İndeksleri yeniden oluştur
REINDEX TABLE stock_prices;

-- İstatistikleri güncelle
ANALYZE stock_prices;

-- Yükleme sonrası doğrulama
SELECT
    COUNT(*)                    AS toplam_kayit,
    COUNT(DISTINCT symbol)      AS farkli_hisse,
    MIN(trade_date)             AS ilk_tarih,
    MAX(trade_date)             AS son_tarih,
    pg_size_pretty(pg_total_relation_size('stock_prices')) AS tablo_boyutu
FROM stock_prices;

\echo 'Veri yukleme tamamlandi.'
