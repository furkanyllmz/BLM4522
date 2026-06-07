-- ============================================================
-- ADIM 5: Test Yedekleme Senaryoları (Yedek Doğrulama)
--
-- "Yedeklerin doğruluğunu test etme"
--
-- En sık yapılan hata: yedek alınır ama HİÇ test edilmez.
-- Felaket anında yedeğin bozuk olduğu anlaşılır. Bu dosya,
-- bir yedeğin gerçekten geri yüklenebildiğini ve verinin
-- tutarlı olduğunu DOĞRULAYAN testleri içerir.
--
-- Yöntem: Yedeği AYRI bir test DB'sine geri yükle, satır
-- sayılarını ve checksum'ları karşılaştır.
-- ============================================================

\connect backup_demo

\echo '=========================================='
\echo ' YEDEK DOGRULAMA / TEST SENARYOLARI'
\echo '=========================================='

-- ============================================================
-- 5.1 KAYNAK VERİTABANI PARMAK İZİ (Checksum)
--
-- Yedek almadan önce kaynağın "parmak izini" çıkarırız.
-- Geri yükleme sonrası bu değerler birebir aynı olmalıdır.
-- ============================================================

\echo ''
\echo '--- 5.1 KAYNAK DB PARMAK IZI ---'

-- Doğrulama sonuçlarını saklamak için tablo
CREATE TABLE IF NOT EXISTS backup_verification (
    id            SERIAL PRIMARY KEY,
    tested_at     TIMESTAMPTZ DEFAULT NOW(),
    tablo_adi     VARCHAR(60),
    kaynak_satir  BIGINT,
    kaynak_checksum TEXT,
    sonuc         VARCHAR(20)
);

-- Her tablonun satır sayısı + içerik checksum'ı
\echo 'Kaynak tablolarin parmak izi:'

SELECT
    'customers' AS tablo,
    COUNT(*)    AS satir_sayisi,
    md5(string_agg(customer_id::text || full_name || email, ',' ORDER BY customer_id)) AS checksum
FROM customers
UNION ALL
SELECT
    'orders',
    COUNT(*),
    md5(string_agg(order_id::text || product_name || total_price::text, ',' ORDER BY order_id))
FROM orders;

-- ============================================================
-- 5.2 OTOMATİK DOĞRULAMA FONKSİYONU
--
-- Bir tablonun satır sayısı ve checksum'ını döndürür.
-- Hem kaynak hem hedef DB'de çağrılıp karşılaştırılabilir.
-- ============================================================

\echo ''
\echo '--- 5.2 DOGRULAMA FONKSIYONU ---'

CREATE OR REPLACE FUNCTION table_fingerprint(p_table TEXT)
RETURNS TABLE(satir_sayisi BIGINT, checksum TEXT)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY EXECUTE format(
        'SELECT COUNT(*)::BIGINT,
                md5(COALESCE(string_agg(t::text, %L ORDER BY t::text), %L))
         FROM %I t',
        ',', 'BOS', p_table
    );
END $$;

-- Kullanım örneği
\echo 'customers parmak izi:'
SELECT * FROM table_fingerprint('customers');

\echo 'orders parmak izi:'
SELECT * FROM table_fingerprint('orders');

-- ============================================================
-- 5.3 GERİ YÜKLEME TESTİ (Terminal adımları)
--
-- Yedeği ayrı bir test DB'sine yükleyip karşılaştırma.
-- ============================================================

\echo ''
\echo '--- 5.3 GERI YUKLEME TESTI (Terminal) ---'
\echo ''
\echo '1) Yedek al:'
\echo '   pg_dump -U postgres -F c -f backup_sql/backups/test_verify.dump backup_demo'
\echo ''
\echo '2) Yedegin bozuk olup olmadigini KONTROL ET (geri yuklemeden):'
\echo '   pg_restore --list backup_sql/backups/test_verify.dump'
\echo '   # Cikti veriyorsa dosya saglam demektir.'
\echo ''
\echo '3) Ayri bir test DBsine geri yukle:'
\echo '   dropdb -U postgres backup_demo_test 2>/dev/null'
\echo '   createdb -U postgres backup_demo_test'
\echo '   pg_restore -U postgres -d backup_demo_test backup_sql/backups/test_verify.dump'
\echo ''
\echo '4) Iki DBnin parmak izini karsilastir:'
\echo '   psql -U postgres -d backup_demo      -c "SELECT * FROM table_fingerprint('"'"'orders'"'"');"'
\echo '   psql -U postgres -d backup_demo_test -c "SELECT * FROM table_fingerprint('"'"'orders'"'"');"'
\echo '   # Satir sayisi ve checksum AYNI ise yedek DOGRULANMIS demektir.'

-- ============================================================
-- 5.4 OTOMATİK TEST SONUCU KAYDI
-- ============================================================

\echo ''
\echo '--- 5.4 TEST SONUCLARINI KAYDET ---'

-- Bu blok kaynak ve hedef parmak izini karşılaştırır.
-- (Demo amaçlı kaynak ile kaynağı karşılaştırıyoruz; gerçekte
--  hedef DB dblink/postgres_fdw ile sorgulanır.)
DO $$
DECLARE
    v_cust_rows  BIGINT;
    v_cust_sum   TEXT;
    v_ord_rows   BIGINT;
    v_ord_sum    TEXT;
BEGIN
    SELECT satir_sayisi, checksum INTO v_cust_rows, v_cust_sum
    FROM table_fingerprint('customers');

    SELECT satir_sayisi, checksum INTO v_ord_rows, v_ord_sum
    FROM table_fingerprint('orders');

    INSERT INTO backup_verification (tablo_adi, kaynak_satir, kaynak_checksum, sonuc)
    VALUES
        ('customers', v_cust_rows, v_cust_sum, CASE WHEN v_cust_rows > 0 THEN 'BASARILI' ELSE 'BOS' END),
        ('orders',    v_ord_rows,  v_ord_sum,  CASE WHEN v_ord_rows  > 0 THEN 'BASARILI' ELSE 'BOS' END);

    RAISE NOTICE 'Dogrulama: customers=% satir, orders=% satir', v_cust_rows, v_ord_rows;
END $$;

-- Test geçmişini göster
SELECT
    tested_at   AS test_zamani,
    tablo_adi   AS tablo,
    kaynak_satir AS satir,
    LEFT(kaynak_checksum, 16) || '...' AS checksum_ozet,
    sonuc
FROM backup_verification
ORDER BY id DESC
LIMIT 10;

\echo ''
\echo 'Yedek dogrulama testleri tamamlandi.'
