-- ============================================================
-- ADIM 2: Veri Profilleme — Hataların Tespiti
-- Komut: psql -U postgres -d etl_demo -f etl_sql/02_data_profiling.sql
--
-- Temizlemeden ÖNCE verideki sorunları tespit ederiz.
-- "Veri hatalarını tespit etme" — ödevin temel maddesi.
--
-- Bu adım, hangi sütunlarda kaç hata olduğunu sayar ve
-- bir KALİTE PROFİLİ çıkarır. Temizleme stratejisi bu
-- profile göre belirlenir.
-- ============================================================

\connect etl_demo

\echo '=========================================='
\echo ' VERI PROFILLEME: Hata Tespiti'
\echo '=========================================='

-- ============================================================
-- 2.1 EKSİK DEĞER ANALİZİ (online_sales)
-- ============================================================

\echo ''
\echo '--- 2.1 ONLINE_SALES: Eksik deger analizi ---'

SELECT
    COUNT(*)                                                    AS toplam,
    COUNT(*) FILTER (WHERE eposta IS NULL OR TRIM(eposta) = '') AS eksik_eposta,
    COUNT(*) FILTER (WHERE sehir  IS NULL OR TRIM(sehir)  = '') AS eksik_sehir,
    COUNT(*) FILTER (WHERE adet ~ '^[0-9]+$' IS NOT TRUE)       AS gecersiz_adet,
    COUNT(*) FILTER (WHERE birim_fiyat !~ '^-?[0-9.]+$')        AS gecersiz_fiyat
FROM staging.online_sales;

-- ============================================================
-- 2.2 AYKIRI / HATALI DEĞER ANALİZİ
-- ============================================================

\echo ''
\echo '--- 2.2 Aykiri ve mantiksal hatalar ---'

-- Negatif fiyat
\echo 'Negatif fiyatli kayitlar:'
SELECT raw_id, musteri_adi, birim_fiyat
FROM staging.online_sales
WHERE birim_fiyat ~ '^-' ;

-- Gelecek tarih (hatalı)
\echo 'Gelecek tarihli (hatali) kayitlar:'
SELECT raw_id, musteri_adi, satis_tarihi
FROM staging.online_sales
WHERE satis_tarihi ~ '^\d{4}' AND LEFT(satis_tarihi,4)::INT > EXTRACT(YEAR FROM NOW());

-- Sıfır adet (store)
\echo 'Sifir adetli kayitlar (store):'
SELECT raw_id, full_name, qty FROM staging.store_sales WHERE qty = '0';

-- ============================================================
-- 2.3 TUTARSIZ FORMAT ANALİZİ (şehir yazımları)
--
-- Aynı şehir, kaç farklı şekilde yazılmış? (istanbul / İSTANBUL / ist.)
-- ============================================================

\echo ''
\echo '--- 2.3 Tutarsiz sehir yazimlari ---'

SELECT sehir AS ham_sehir, COUNT(*) AS adet
FROM staging.online_sales
GROUP BY sehir
ORDER BY sehir;

\echo 'Store kaynagindaki sehir yazimlari:'
SELECT city_name AS ham_sehir, COUNT(*) AS adet
FROM staging.store_sales
GROUP BY city_name
ORDER BY city_name;

-- ============================================================
-- 2.4 GEÇERSİZ E-POSTA FORMATI
-- ============================================================

\echo ''
\echo '--- 2.4 Gecersiz e-posta formati ---'

SELECT raw_id, full_name, email_addr
FROM staging.store_sales
WHERE email_addr IS NOT NULL
  AND email_addr !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$';

-- ============================================================
-- 2.5 MÜKERRER KAYIT TESPİTİ
--
-- Aynı müşteri + ürün + tarih = muhtemel mükerrer.
-- ============================================================

\echo ''
\echo '--- 2.5 Mukerrer kayitlar (online) ---'

SELECT
    TRIM(LOWER(musteri_adi)) AS musteri,
    urun, satis_tarihi,
    COUNT(*) AS tekrar_sayisi
FROM staging.online_sales
GROUP BY TRIM(LOWER(musteri_adi)), urun, satis_tarihi
HAVING COUNT(*) > 1;

-- ============================================================
-- 2.6 GENEL KALİTE PROFİLİ ÖZET TABLOSU
--
-- Tüm hata sayılarını tek bir özet tabloda toplar.
-- Bu, "önce" durumunu temsil eder (06'da "sonra" ile karşılaştırılır).
-- ============================================================

\echo ''
\echo '--- 2.6 GENEL KALITE PROFILI (ONCE) ---'

DROP TABLE IF EXISTS target.quality_profile;
CREATE TABLE target.quality_profile (
    olcum_zamani  TIMESTAMPTZ DEFAULT NOW(),
    asama         VARCHAR(20),
    metrik        VARCHAR(50),
    deger         BIGINT
);

INSERT INTO target.quality_profile (asama, metrik, deger)
SELECT 'ONCE', 'toplam_ham_kayit',
       (SELECT COUNT(*) FROM staging.online_sales) + (SELECT COUNT(*) FROM staging.store_sales)
UNION ALL SELECT 'ONCE', 'eksik_eposta',
       -- boş/null + geçersiz formatlı (kullanılamaz) e-postaların toplamı
       (SELECT COUNT(*) FROM staging.online_sales
            WHERE eposta IS NULL OR TRIM(eposta)=''
               OR LOWER(TRIM(eposta)) !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')
     + (SELECT COUNT(*) FROM staging.store_sales
            WHERE email_addr IS NULL OR TRIM(email_addr)=''
               OR LOWER(TRIM(email_addr)) !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')
UNION ALL SELECT 'ONCE', 'eksik_sehir',
       (SELECT COUNT(*) FROM staging.online_sales WHERE sehir IS NULL OR TRIM(sehir)='')
     + (SELECT COUNT(*) FROM staging.store_sales  WHERE city_name IS NULL OR TRIM(city_name)='')
UNION ALL SELECT 'ONCE', 'gecersiz_eposta_format',
       (SELECT COUNT(*) FROM staging.store_sales WHERE email_addr IS NOT NULL
            AND email_addr !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')
UNION ALL SELECT 'ONCE', 'negatif_fiyat',
       (SELECT COUNT(*) FROM staging.online_sales WHERE birim_fiyat ~ '^-')
UNION ALL SELECT 'ONCE', 'sifir_adet',
       (SELECT COUNT(*) FROM staging.store_sales WHERE qty = '0')
UNION ALL SELECT 'ONCE', 'gecersiz_adet',
       (SELECT COUNT(*) FROM staging.online_sales WHERE adet ~ '^[0-9]+$' IS NOT TRUE);

SELECT asama, metrik, deger FROM target.quality_profile WHERE asama='ONCE' ORDER BY metrik;

SELECT target.log_etl('PROFILING', 'staging',
    (SELECT COUNT(*) FROM staging.online_sales) + (SELECT COUNT(*) FROM staging.store_sales),
    0, 0, 'Veri kalite profili cikarildi (ONCE durumu)');

\echo ''
\echo 'Veri profilleme tamamlandi. Tespit edilen hatalar quality_profile tablosunda.'
