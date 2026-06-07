-- ============================================================
-- ADIM 4: Felaketten Kurtarma Senaryoları
--
-- "Kaza ile silinen verilerin geri getirilmesi"
--
-- Bu dosya CANLI olarak çalıştırılabilir bir senaryo sunar:
--   1) Mevcut durumu yedekle (pg_dump terminalden)
--   2) Kaza simülasyonu: yanlışlıkla DELETE / DROP
--   3) Veriyi geri getir (3 farklı yöntemle)
--
-- Videoda gösterim için adım adım ilerleyin.
-- ============================================================

\connect backup_demo

\echo '=========================================='
\echo ' FELAKETTEN KURTARMA SENARYOLARI'
\echo '=========================================='

-- ============================================================
-- 4.1 BAŞLANGIÇ DURUMU (Felaket öncesi)
-- ============================================================

\echo ''
\echo '--- 4.1 FELAKET ONCESI DURUM ---'

SELECT 'customers' AS tablo, COUNT(*) AS kayit FROM customers
UNION ALL
SELECT 'orders', COUNT(*) FROM orders;

\echo ''
\echo 'ONEMLI: Bu senaryo oncesi terminalde TAM yedek alin:'
\echo '   pg_dump -U postgres -F c -f backup_sql/backups/before_disaster.dump backup_demo'

-- ============================================================
-- SENARYO A: Transaction içinde yanlış DELETE -> ROLLBACK
--
-- En basit kurtarma: işlem henüz COMMIT edilmediyse geri al.
-- ============================================================

\echo ''
\echo '=== SENARYO A: ROLLBACK ile aninda kurtarma ==='

BEGIN;
    -- Kaza: tüm siparişleri sildik!
    DELETE FROM orders;
    \echo 'Kaza! Tum siparisler silindi. Silinen sonrasi:'
    SELECT COUNT(*) AS kalan_siparis FROM orders;

    -- Fark ettik -> henüz commit etmedik -> geri al
ROLLBACK;

\echo 'ROLLBACK sonrasi (veri geri geldi):'
SELECT COUNT(*) AS siparis_sayisi FROM orders;

-- ============================================================
-- SENARYO B: COMMIT edilmiş silme -> Yedekten kurtarma
--
-- İşlem commit edildiyse ROLLBACK işe yaramaz.
-- Bu durumda alınan yedekten ilgili tablo geri yüklenir.
-- ============================================================

\echo ''
\echo '=== SENARYO B: COMMIT sonrasi yedekten kurtarma ==='

-- Önce kurtarma için bir "güvenli kopya" alalım (gerçekte pg_dump yedeği)
CREATE TABLE orders_safety_copy AS TABLE orders;
\echo 'Guvenli kopya alindi (orders_safety_copy).'

-- Kaza: belirli müşterinin siparişleri kalıcı silindi (commit'li)
DELETE FROM orders WHERE customer_id = 2;
\echo 'Kaza: customer_id=2 siparisleri silindi. Mevcut durum:'
SELECT customer_id, COUNT(*) FROM orders GROUP BY customer_id ORDER BY customer_id;

-- KURTARMA: yedek kopyadan eksik kayıtları geri yükle
INSERT INTO orders (order_id, customer_id, product_name, quantity, unit_price, order_date)
SELECT order_id, customer_id, product_name, quantity, unit_price, order_date
FROM orders_safety_copy
WHERE customer_id = 2
  AND order_id NOT IN (SELECT order_id FROM orders);

\echo 'Kurtarma sonrasi (customer_id=2 geri geldi):'
SELECT customer_id, COUNT(*) FROM orders GROUP BY customer_id ORDER BY customer_id;

-- Sequence'ı düzelt (manuel order_id girdiğimiz için)
SELECT setval('orders_order_id_seq', (SELECT MAX(order_id) FROM orders));

-- Temizlik
DROP TABLE orders_safety_copy;

-- ============================================================
-- SENARYO C: pg_dump yedeğinden tek tablo geri yükleme (Terminal)
--
-- Gerçek dosya yedeğinden geri yükleme komutları.
-- ============================================================

\echo ''
\echo '=== SENARYO C: pg_restore ile dosya yedeginden kurtarma ==='
\echo 'Terminalde calistirilacak komutlar:'
\echo ''
\echo '# Tum veritabanini geri yukle (mevcut DB silinir):'
\echo 'pg_restore -U postgres -d backup_demo --clean backup_sql/backups/before_disaster.dump'
\echo ''
\echo '# SADECE orders tablosunu geri yukle:'
\echo 'pg_restore -U postgres -d backup_demo -t orders \\'
\echo '    --data-only backup_sql/backups/before_disaster.dump'
\echo ''
\echo '# Yeni bos bir DBye geri yukleyip kontrol et (en guvenli):'
\echo 'createdb -U postgres backup_demo_restore'
\echo 'pg_restore -U postgres -d backup_demo_restore backup_sql/backups/before_disaster.dump'

-- ============================================================
-- SENARYO D: DROP TABLE felaketi -> Tam DB geri yükleme (Terminal)
-- ============================================================

\echo ''
\echo '=== SENARYO D: DROP TABLE / DROP DATABASE felaketi ==='
\echo 'Eger tablo veya DB tamamen silindiyse, sadece tam yedek kurtarir:'
\echo ''
\echo '# DByi yeniden olustur ve geri yukle:'
\echo 'dropdb -U postgres backup_demo          # (zaten silinmis olabilir)'
\echo 'createdb -U postgres backup_demo'
\echo 'pg_restore -U postgres -d backup_demo backup_sql/backups/before_disaster.dump'
\echo ''
\echo '# Belirli bir ANA donmek gerekiyorsa -> PITR (bkz. 02_pitr_setup.sql)'

-- ============================================================
-- 4.2 KURTARMA SONRASI DOĞRULAMA
-- ============================================================

\echo ''
\echo '--- 4.2 SON DURUM DOGRULAMA ---'

SELECT 'customers' AS tablo, COUNT(*) AS kayit FROM customers
UNION ALL
SELECT 'orders', COUNT(*) FROM orders;

\echo ''
\echo 'Felaketten kurtarma senaryolari tamamlandi.'
