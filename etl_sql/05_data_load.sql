-- ============================================================
-- ADIM 5: LOAD — Verilerin Hedef Veritabanına Yüklenmesi
-- Komut: psql -U postgres -d etl_demo -f etl_sql/05_data_load.sql
--
-- "Verilerin doğru hedef veritabanlarına yüklenmesi"
--
-- Temizlenmiş ve dönüştürülmüş veri, nihai hedef şemaya
-- (target) yıldız şeması (star schema) mantığıyla yüklenir:
--   target.dim_customer  -> müşteri boyutu
--   target.fact_sales    -> satış olgu (fact) tablosu
--
-- Yükleme UPSERT (INSERT ... ON CONFLICT) ile yapılır; böylece
-- ETL tekrar çalıştığında veri ÇİFTLENMEZ (idempotent yükleme).
-- ============================================================

\connect etl_demo

\echo '=========================================='
\echo ' LOAD: Hedef veritabanina yukleme'
\echo '=========================================='

-- ============================================================
-- 5.1 HEDEF BOYUT TABLOSU: target.dim_customer
-- ============================================================

\echo ''
\echo '--- 5.1 Musteri boyutu (dim_customer) yukleniyor ---'

CREATE TABLE IF NOT EXISTS target.dim_customer (
    musteri_id    INT PRIMARY KEY,
    ad            TEXT,
    eposta        TEXT UNIQUE,
    telefon       TEXT,
    sehir         TEXT,
    yuklenme_zamani TIMESTAMPTZ DEFAULT NOW()
);

-- UPSERT: e-posta varsa güncelle, yoksa ekle
INSERT INTO target.dim_customer (musteri_id, ad, eposta, telefon, sehir)
SELECT musteri_id, ad, eposta, telefon, sehir
FROM clean.dim_customer
ON CONFLICT (eposta) DO UPDATE
SET ad      = EXCLUDED.ad,
    telefon = EXCLUDED.telefon,
    sehir   = EXCLUDED.sehir;

SELECT COUNT(*) AS yuklenen_musteri FROM target.dim_customer;

-- ============================================================
-- 5.2 HEDEF OLGU TABLOSU: target.fact_sales
--
-- Her satış kaydı, müşteri boyutuna bağlanır (foreign key).
-- ============================================================

\echo ''
\echo '--- 5.2 Satis olgu tablosu (fact_sales) yukleniyor ---'

CREATE TABLE IF NOT EXISTS target.fact_sales (
    satis_id         INT PRIMARY KEY,
    musteri_id       INT REFERENCES target.dim_customer(musteri_id),
    urun             TEXT,
    adet             INT,
    birim_fiyat_try  NUMERIC(12,2),
    toplam_tutar_try NUMERIC(12,2),
    sehir            TEXT,
    satis_tarihi     DATE,
    satis_yili       INT,
    satis_ayi        INT,
    kaynak           TEXT,
    yuklenme_zamani  TIMESTAMPTZ DEFAULT NOW()
);

-- UPSERT: aynı satis_id tekrar gelirse güncelle (idempotent)
-- NOT: sehir dogrudan fact'e yazilir (denormalize); boylece e-postasiz
-- (musteriye baglanamayan) satislarda da sehir bilgisi korunur.
INSERT INTO target.fact_sales
    (satis_id, musteri_id, urun, adet, birim_fiyat_try, toplam_tutar_try,
     sehir, satis_tarihi, satis_yili, satis_ayi, kaynak)
SELECT
    t.id,
    dc.musteri_id,
    t.urun,
    t.adet,
    t.birim_fiyat_try,
    t.toplam_tutar_try,
    t.sehir,
    t.satis_tarihi,
    t.satis_yili,
    t.satis_ayi,
    t.kaynak
FROM clean.sales_transformed t
LEFT JOIN target.dim_customer dc ON t.eposta = dc.eposta
ON CONFLICT (satis_id) DO UPDATE
SET musteri_id       = EXCLUDED.musteri_id,
    adet             = EXCLUDED.adet,
    birim_fiyat_try  = EXCLUDED.birim_fiyat_try,
    toplam_tutar_try = EXCLUDED.toplam_tutar_try,
    sehir            = EXCLUDED.sehir;

SELECT COUNT(*) AS yuklenen_satis FROM target.fact_sales;

-- ============================================================
-- 5.3 YÜKLEME DOĞRULAMA (Referans Bütünlüğü)
--
-- Her satış bir müşteriye bağlanmış mı? Tutarlar tutuyor mu?
-- ============================================================

\echo ''
\echo '--- 5.3 Yukleme dogrulama ---'

\echo 'Musteriye baglanamayan satis (olmamali):'
SELECT COUNT(*) AS bagsiz_satis
FROM target.fact_sales
WHERE musteri_id IS NULL;

\echo 'Kaynak (clean) ve hedef (target) satir sayisi karsilastirma:'
SELECT
    (SELECT COUNT(*) FROM clean.sales_transformed) AS clean_satir,
    (SELECT COUNT(*) FROM target.fact_sales)        AS target_satir,
    CASE WHEN (SELECT COUNT(*) FROM clean.sales_transformed)
            = (SELECT COUNT(*) FROM target.fact_sales)
         THEN 'ESIT - OK' ELSE 'FARKLI - KONTROL ET' END AS durum;

-- ============================================================
-- 5.4 IDEMPOTENT TEST (tekrar yükleme çiftleme yapmamalı)
--
-- Aynı yükleme tekrar çalıştırılırsa satır sayısı DEĞİŞMEMELİ.
-- ============================================================

\echo ''
\echo '--- 5.4 Idempotent yukleme testi (tekrar yukle) ---'

DO $$
DECLARE v_before BIGINT; v_after BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_before FROM target.fact_sales;

    -- aynı veriyi tekrar yükle
    INSERT INTO target.fact_sales
        (satis_id, musteri_id, urun, adet, birim_fiyat_try, toplam_tutar_try,
         sehir, satis_tarihi, satis_yili, satis_ayi, kaynak)
    SELECT t.id, dc.musteri_id, t.urun, t.adet, t.birim_fiyat_try,
           t.toplam_tutar_try, t.sehir, t.satis_tarihi, t.satis_yili, t.satis_ayi, t.kaynak
    FROM clean.sales_transformed t
    LEFT JOIN target.dim_customer dc ON t.eposta = dc.eposta
    ON CONFLICT (satis_id) DO NOTHING;

    SELECT COUNT(*) INTO v_after FROM target.fact_sales;

    RAISE NOTICE 'Tekrar yukleme: once=% sonra=% -> %',
        v_before, v_after,
        CASE WHEN v_before = v_after THEN 'CIFTLEME YOK (idempotent OK)'
             ELSE 'CIFTLEME VAR (HATA!)' END;
END $$;

-- ============================================================
-- 5.5 HEDEF VERİ ÖNİZLEME
-- ============================================================

\echo ''
\echo '--- 5.5 Hedef fact_sales onizleme (musteri ile join) ---'

SELECT
    f.satis_id,
    COALESCE(d.ad, '(e-postasiz musteri)') AS musteri,
    f.sehir,
    f.urun,
    f.adet,
    f.toplam_tutar_try,
    f.satis_tarihi,
    f.kaynak
FROM target.fact_sales f
LEFT JOIN target.dim_customer d ON f.musteri_id = d.musteri_id
ORDER BY f.satis_id
LIMIT 16;

SELECT target.log_etl('LOAD', 'target',
    (SELECT COUNT(*) FROM clean.sales_transformed),
    (SELECT COUNT(*) FROM target.fact_sales),
    0,
    'Hedef yildiz semasina UPSERT ile yuklendi (dim_customer + fact_sales)');

\echo ''
\echo 'Veri yukleme tamamlandi.'
