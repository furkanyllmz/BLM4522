-- ============================================================
-- ADIM 3: TRANSFORM (1/2) — Veri Temizleme
-- Komut: psql -U postgres -d etl_demo -f etl_sql/03_data_cleaning.sql
--
-- "SQL kullanarak hatalı verilerin temizlenmesi"
--   • Eksik veriler        -> doldur veya işaretle
--   • Tutarsız veriler      -> normalize et (boşluk, büyük/küçük harf)
--   • Yanlış formatlar      -> düzelt (telefon, e-posta, tarih)
--   • Geçersiz/aykırı veri  -> düzelt veya reddet (negatif, sıfır, gelecek)
--   • Mükerrer kayıtlar     -> tekilleştir (deduplication)
--
-- Önce iki kaynak ORTAK bir ham modelde birleştirilir, sonra
-- bu birleşik küme üzerinde tüm temizleme kuralları uygulanır.
-- Reddedilen (kurtarılamayan) kayıtlar ayrı bir tabloya alınır.
-- ============================================================

\connect etl_demo

\echo '=========================================='
\echo ' TRANSFORM (1/2): Veri Temizleme'
\echo '=========================================='

-- ============================================================
-- 3.1 İKİ KAYNAĞI ORTAK HAM MODELDE BİRLEŞTİR (Veri Entegrasyonu)
--
-- Farklı sütun isimlerini (musteri_adi vs full_name) tek modele
-- getiririz. Bu, "veri entegrasyonu" adımıdır.
-- ============================================================

\echo ''
\echo '--- 3.1 Iki kaynak birlestiriliyor (entegrasyon) ---'

DROP TABLE IF EXISTS clean.merged_raw;
CREATE TABLE clean.merged_raw AS
    SELECT musteri_adi AS ad, eposta, telefon, sehir, urun,
           adet, birim_fiyat AS fiyat, para_birimi, satis_tarihi, kaynak
    FROM staging.online_sales
    UNION ALL
    SELECT full_name, email_addr, phone, city_name, product_name,
           qty, price, currency, sale_dt, kaynak
    FROM staging.store_sales;

SELECT COUNT(*) AS birlesik_ham_satir FROM clean.merged_raw;

-- ============================================================
-- 3.2 REDDEDİLEN KAYIT TABLOSU (kurtarılamayan veriler)
-- ============================================================

DROP TABLE IF EXISTS clean.rejected;
CREATE TABLE clean.rejected (
    ad        TEXT,
    eposta    TEXT,
    urun      TEXT,
    fiyat     TEXT,
    adet      TEXT,
    sebep     TEXT,
    kaynak    TEXT
);

-- ============================================================
-- 3.3 TÜRKÇE-DOĞRU BAŞLIK (INITCAP) FONKSİYONU
--
-- PostgreSQL'in yerleşik INITCAP'i Türkçe i/İ kuralını bilmez
-- ("ISTANBUL" -> "Istanbul" yerine "İstanbul" olmalı). Bu
-- fonksiyon her kelimenin ilk harfini Türkçe kurala göre büyütür.
-- ============================================================

CREATE OR REPLACE FUNCTION clean.tr_initcap(p_text TEXT)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    v_word   TEXT;
    v_result TEXT := '';
    v_first  TEXT;
    v_rest   TEXT;
BEGIN
    IF p_text IS NULL THEN RETURN NULL; END IF;
    -- kelimelere ayır (fazla boşluklar tek boşluğa indirilmiş varsayılır)
    FOREACH v_word IN ARRAY regexp_split_to_array(TRIM(p_text), '\s+') LOOP
        IF v_word = '' THEN CONTINUE; END IF;
        v_first := LEFT(v_word, 1);
        v_rest  := SUBSTRING(v_word FROM 2);
        -- ilk harf: i -> İ (Türkçe), diğerleri normal upper
        v_first := CASE v_first WHEN 'i' THEN 'İ' WHEN 'ı' THEN 'I' ELSE UPPER(v_first) END;
        -- geri kalan: İ -> i, I -> ı (Türkçe), diğerleri normal lower
        v_rest  := REPLACE(REPLACE(LOWER(REPLACE(REPLACE(v_rest,'I','\I'),'İ','\i')),'\i','i'),'\I','ı');
        v_result := v_result || CASE WHEN v_result = '' THEN '' ELSE ' ' END || v_first || v_rest;
    END LOOP;
    RETURN v_result;
END $$;

-- ============================================================
-- 3.4 TEMİZLENMİŞ TABLOYU OLUŞTUR
-- ============================================================

DROP TABLE IF EXISTS clean.sales_clean;
CREATE TABLE clean.sales_clean (
    id            SERIAL PRIMARY KEY,
    ad            TEXT,
    eposta        TEXT,
    telefon       TEXT,
    sehir         TEXT,
    urun          TEXT,
    adet          INT,
    fiyat         NUMERIC(12,2),
    para_birimi   TEXT,
    satis_tarihi  DATE,
    kaynak        TEXT
);

-- ============================================================
-- 3.4 GEÇERSİZ KAYITLARI REDDET
--
-- Kurtarılamayacak kayıtları (negatif fiyat, sıfır/geçersiz adet,
-- gelecek tarih, eksik kritik alan) ayır ve sebebiyle kaydet.
-- ============================================================

\echo ''
\echo '--- 3.4 Gecersiz kayitlar reddediliyor ---'

INSERT INTO clean.rejected (ad, eposta, urun, fiyat, adet, sebep, kaynak)
SELECT ad, eposta, urun, fiyat, adet,
    CASE
        WHEN fiyat ~ '^-'                          THEN 'Negatif fiyat'
        WHEN adet !~ '^[0-9]+$'                     THEN 'Gecersiz adet (sayi degil)'
        WHEN adet = '0'                            THEN 'Sifir adet'
        WHEN satis_tarihi ~ '^\d{4}'
             AND LEFT(satis_tarihi,4)::INT > EXTRACT(YEAR FROM NOW())::INT
                                                   THEN 'Gelecek tarih'
        WHEN ad IS NULL OR TRIM(ad) = ''           THEN 'Eksik musteri adi'
    END AS sebep,
    kaynak
FROM clean.merged_raw
WHERE fiyat ~ '^-'
   OR adet !~ '^[0-9]+$'
   OR adet = '0'
   OR (satis_tarihi ~ '^\d{4}' AND LEFT(satis_tarihi,4)::INT > EXTRACT(YEAR FROM NOW())::INT)
   OR ad IS NULL OR TRIM(ad) = '';

\echo 'Reddedilen kayitlar:';
SELECT sebep, COUNT(*) AS adet FROM clean.rejected GROUP BY sebep ORDER BY sebep;

-- ============================================================
-- 3.5 GEÇERLİ KAYITLARI TEMİZLEYEREK YÜKLE
--
-- Burada tüm temizleme kuralları SQL ile uygulanır:
--   • Ad: TRIM + fazla boşlukları teke indir + INITCAP
--   • E-posta: küçük harf, geçersizse NULL
--   • Telefon: sadece rakam, +90 standart
--   • Şehir: TRIM + büyük/küçük normalize
--   • Tarih: çoklu formatı tek DATE'e çevir
-- ============================================================

\echo ''
\echo '--- 3.5 Gecerli kayitlar temizleniyor ---'

INSERT INTO clean.sales_clean (ad, eposta, telefon, sehir, urun, adet, fiyat, para_birimi, satis_tarihi, kaynak)
SELECT
    -- AD: kenar boşlukları sil, içteki çoklu boşlukları teke indir, baş harfleri büyüt (Türkçe)
    clean.tr_initcap(TRIM(REGEXP_REPLACE(ad, '\s+', ' ', 'g')))              AS ad,

    -- E-POSTA: küçük harf + boşluk temizle; geçersizse NULL
    CASE
        WHEN LOWER(TRIM(eposta)) ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
        THEN LOWER(TRIM(eposta))
        ELSE NULL
    END                                                                       AS eposta,

    -- TELEFON: sadece rakamları al, 10 haneye indir, +90 ekle
    CASE
        WHEN REGEXP_REPLACE(telefon, '\D', '', 'g') = '' THEN NULL
        ELSE '+90' || RIGHT(REGEXP_REPLACE(telefon, '\D', '', 'g'), 10)
    END                                                                       AS telefon,

    -- ŞEHİR: kısaltmaları aç, boşluk temizle, ilk harf büyük (04'te tam standardize edilecek)
    clean.tr_initcap(TRIM(
        CASE LOWER(TRIM(sehir))
            WHEN 'ist.' THEN 'istanbul'
            ELSE LOWER(TRIM(sehir))
        END))                                                                 AS sehir,

    urun,
    adet::INT,
    fiyat::NUMERIC(12,2),
    UPPER(TRIM(para_birimi))                                                  AS para_birimi,

    -- TARİH: 4 farklı formatı tek DATE'e çevir (YYYY-MM-DD / DD.MM.YYYY / YYYY/MM/DD)
    CASE
        WHEN satis_tarihi ~ '^\d{4}-\d{2}-\d{2}$' THEN satis_tarihi::DATE
        WHEN satis_tarihi ~ '^\d{2}\.\d{2}\.\d{4}$' THEN TO_DATE(satis_tarihi, 'DD.MM.YYYY')
        WHEN satis_tarihi ~ '^\d{4}/\d{2}/\d{2}$' THEN TO_DATE(satis_tarihi, 'YYYY/MM/DD')
        ELSE NULL
    END                                                                       AS satis_tarihi,
    kaynak
FROM clean.merged_raw
-- sadece reddedilmeyen (geçerli) kayıtlar
WHERE NOT (
       fiyat ~ '^-'
    OR adet !~ '^[0-9]+$'
    OR adet = '0'
    OR (satis_tarihi ~ '^\d{4}' AND LEFT(satis_tarihi,4)::INT > EXTRACT(YEAR FROM NOW())::INT)
    OR ad IS NULL OR TRIM(ad) = ''
);

-- ============================================================
-- 3.6 MÜKERRER KAYITLARI TEKİLLEŞTİR (Deduplication)
--
-- Aynı ad + ürün + tarih + kaynak olan kayıtlardan sadece
-- ilkini tut, diğerlerini sil.
-- ============================================================

\echo ''
\echo '--- 3.6 Mukerrer kayitlar tekillestiriliyor ---'

WITH dups AS (
    SELECT id,
        ROW_NUMBER() OVER (
            PARTITION BY ad, urun, satis_tarihi, kaynak
            ORDER BY id
        ) AS rn
    FROM clean.sales_clean
)
DELETE FROM clean.sales_clean
WHERE id IN (SELECT id FROM dups WHERE rn > 1);

\echo 'Tekillestirme sonrasi kalan satir:';
SELECT COUNT(*) AS temiz_satir FROM clean.sales_clean;

-- ============================================================
-- 3.7 TEMİZLEME SONUCU
-- ============================================================

\echo ''
\echo '--- 3.7 Temizlenmis veri ornegi ---'

SELECT id, ad, eposta, telefon, sehir, urun, adet, fiyat, para_birimi, satis_tarihi, kaynak
FROM clean.sales_clean
ORDER BY id
LIMIT 12;

SELECT target.log_etl('CLEANING', 'clean',
    (SELECT COUNT(*) FROM clean.merged_raw),
    (SELECT COUNT(*) FROM clean.sales_clean),
    (SELECT COUNT(*) FROM clean.rejected),
    'Eksik/format/aykiri temizlendi, mukerrer tekillestirildi');

\echo ''
\echo 'Veri temizleme tamamlandi.'
