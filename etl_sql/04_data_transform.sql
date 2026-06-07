-- ============================================================
-- ADIM 4: TRANSFORM (2/2) — Veri Dönüştürme
-- Komut: psql -U postgres -d etl_demo -f etl_sql/04_data_transform.sql
--
-- "Farklı kaynaklardan gelen verilerin standartlaştırılması
--  ve dönüştürülmesi"
--
--   • Şehir standardizasyonu  -> referans tablo ile tek isim
--   • Para birimi dönüşümü     -> USD -> TRY (tek para birimi)
--   • Türetilmiş sütunlar      -> toplam_tutar, yil, ay
--   • Müşteri tekilleştirme    -> e-posta bazlı tekil müşteri kimliği
--
-- Çıktı: clean.sales_transformed (yüklemeye hazır standart veri)
-- ============================================================

\connect etl_demo

\echo '=========================================='
\echo ' TRANSFORM (2/2): Veri Donusturme'
\echo '=========================================='

-- ============================================================
-- 4.1 ŞEHİR REFERANS (LOOKUP) TABLOSU
--
-- Tutarsız şehir yazımlarını tek bir standart isme eşler.
-- Bu, "standartlaştırma" için klasik bir referans tablo yöntemidir.
-- ============================================================

\echo ''
\echo '--- 4.1 Sehir standardizasyon referansi ---'

DROP TABLE IF EXISTS clean.city_lookup;
CREATE TABLE clean.city_lookup (
    ham_yazim   TEXT PRIMARY KEY,
    standart    TEXT NOT NULL,
    plaka       INT
);

INSERT INTO clean.city_lookup (ham_yazim, standart, plaka) VALUES
    ('İstanbul', 'İstanbul', 34),
    ('Istanbul', 'İstanbul', 34),
    ('Ankara',   'Ankara',   6),
    ('İzmir',    'İzmir',    35),
    ('Izmir',    'İzmir',    35),
    ('Bursa',    'Bursa',    16),
    ('Antalya',  'Antalya',  7);

-- ============================================================
-- 4.2 PARA BİRİMİ KURU REFERANSI
--
-- USD kayıtları TRY'ye çevrilir (tek para biriminde raporlama).
-- ============================================================

\echo ''
\echo '--- 4.2 Para birimi kurlari ---'

DROP TABLE IF EXISTS clean.exchange_rate;
CREATE TABLE clean.exchange_rate (
    para_birimi TEXT PRIMARY KEY,
    try_kuru    NUMERIC(10,4)
);

INSERT INTO clean.exchange_rate (para_birimi, try_kuru) VALUES
    ('TRY', 1.0),
    ('USD', 32.5),
    ('EUR', 35.0);

SELECT para_birimi, try_kuru FROM clean.exchange_rate;

-- ============================================================
-- 4.3 DÖNÜŞTÜRÜLMÜŞ TABLO
--
-- Tüm standartlaştırma ve türetmeler tek SELECT'te uygulanır.
-- ============================================================

\echo ''
\echo '--- 4.3 Veri donusturuluyor ---'

DROP TABLE IF EXISTS clean.sales_transformed;
CREATE TABLE clean.sales_transformed AS
SELECT
    s.id,
    s.ad,
    s.eposta,
    s.telefon,

    -- ŞEHİR: referans tablodan standart isim (eşleşmezse orijinal)
    COALESCE(c.standart, s.sehir)                            AS sehir,
    c.plaka                                                  AS sehir_plaka,

    s.urun,
    s.adet,

    -- FİYAT: orijinal para biriminde
    s.fiyat                                                  AS birim_fiyat_orijinal,
    s.para_birimi                                            AS orijinal_para_birimi,

    -- FİYAT: TRY'ye dönüştürülmüş
    ROUND(s.fiyat * COALESCE(r.try_kuru, 1), 2)             AS birim_fiyat_try,

    -- TÜRETİLMİŞ: toplam tutar (adet * birim fiyat, TRY)
    ROUND(s.adet * s.fiyat * COALESCE(r.try_kuru, 1), 2)   AS toplam_tutar_try,

    s.satis_tarihi,
    -- TÜRETİLMİŞ: yıl ve ay (zaman bazlı raporlama için)
    EXTRACT(YEAR  FROM s.satis_tarihi)::INT                  AS satis_yili,
    EXTRACT(MONTH FROM s.satis_tarihi)::INT                  AS satis_ayi,

    s.kaynak
FROM clean.sales_clean s
LEFT JOIN clean.city_lookup   c ON LOWER(s.sehir)       = LOWER(c.ham_yazim)
LEFT JOIN clean.exchange_rate r ON s.para_birimi        = r.para_birimi;

-- ============================================================
-- 4.4 MÜŞTERİ BOYUT TABLOSU (Tekil müşteri — e-posta bazlı)
--
-- Aynı müşteri birden çok satışta görünebilir. E-posta bazlı
-- tekil müşteri listesi çıkarırız (veri ambarı "dimension" mantığı).
-- ============================================================

\echo ''
\echo '--- 4.4 Tekil musteri boyutu olusturuluyor ---'

DROP TABLE IF EXISTS clean.dim_customer;
CREATE TABLE clean.dim_customer AS
SELECT
    ROW_NUMBER() OVER (ORDER BY MIN(id))    AS musteri_id,
    eposta,
    MAX(ad)                                 AS ad,
    MAX(telefon)                            AS telefon,
    MAX(sehir)                              AS sehir,
    COUNT(*)                                AS satis_sayisi
FROM clean.sales_transformed
WHERE eposta IS NOT NULL
GROUP BY eposta;

SELECT musteri_id, ad, eposta, sehir, satis_sayisi
FROM clean.dim_customer
ORDER BY musteri_id;

-- ============================================================
-- 4.5 DÖNÜŞTÜRME SONUCU
-- ============================================================

\echo ''
\echo '--- 4.5 Donusturulmus veri ornegi (USD donusumu dahil) ---'

SELECT id, ad, sehir, urun, adet,
       birim_fiyat_orijinal, orijinal_para_birimi,
       birim_fiyat_try, toplam_tutar_try,
       satis_yili, satis_ayi
FROM clean.sales_transformed
WHERE orijinal_para_birimi = 'USD' OR id <= 4
ORDER BY id;

SELECT target.log_etl('TRANSFORM', 'clean',
    (SELECT COUNT(*) FROM clean.sales_clean),
    (SELECT COUNT(*) FROM clean.sales_transformed),
    0,
    'Sehir/para birimi standardize, turetilmis sutunlar eklendi');

\echo ''
\echo 'Veri donusturme tamamlandi.'
