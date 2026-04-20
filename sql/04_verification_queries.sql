-- ============================================================
-- DOĞRULAMA ve DEMO SORGULARI
-- Video çekimi ve rapor için kullanılacak sorgular
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. Şifrelenmiş kredi kartı kolonunu göster
-- ────────────────────────────────────────────────────────────
SELECT
    musteri_id,
    ulke,
    musteri_tipi,
    -- İlk 20 karakter + "..." göster (tam hash çok uzun)
    LEFT(kredi_karti, 29) || '...' AS sifreli_kredi_karti
FROM musteriler
LIMIT 10;

-- ────────────────────────────────────────────────────────────
-- 2. Otel bazında rezervasyon dağılımı (RLS olmadan — admin görür)
-- ────────────────────────────────────────────────────────────
SET ROLE admin;

SELECT
    hotel,
    COUNT(*)                              AS toplam_rezervasyon,
    ROUND(AVG(adr), 2)                    AS ortalama_fiyat,
    SUM(CASE WHEN is_canceled = 1 THEN 1 ELSE 0 END) AS iptal_sayisi
FROM rezervasyonlar
GROUP BY hotel
ORDER BY hotel;

RESET ROLE;

-- ────────────────────────────────────────────────────────────
-- 3. RLS İzolasyon Testi — city_reception (City Hotel görmeli)
-- ────────────────────────────────────────────────────────────
SET ROLE city_reception;

SELECT hotel, COUNT(*) AS gordugun_kayit_sayisi
FROM rezervasyonlar
GROUP BY hotel;
-- Beklenen: sadece "City Hotel" satırı

RESET ROLE;

-- ────────────────────────────────────────────────────────────
-- 4. RLS İzolasyon Testi — resort_reception (Resort Hotel görmeli)
-- ────────────────────────────────────────────────────────────
SET ROLE resort_reception;

SELECT hotel, COUNT(*) AS gordugun_kayit_sayisi
FROM rezervasyonlar
GROUP BY hotel;
-- Beklenen: sadece "Resort Hotel" satırı

RESET ROLE;

-- ────────────────────────────────────────────────────────────
-- 5. Yetkisiz Fiyat Değişikliği Testi (city_reception)
-- ────────────────────────────────────────────────────────────
SET ROLE city_reception;

-- Bu sorgu HATA verecek ve log tablosuna kaydedecek
UPDATE rezervasyonlar
    SET adr = 10.00
WHERE rezervasyon_id = 1;
-- Beklenen HATA: YETKİ HATASI mesajı

RESET ROLE;

-- ────────────────────────────────────────────────────────────
-- 6. Audit log tablosunu incele
-- ────────────────────────────────────────────────────────────
SET ROLE admin;

SELECT
    log_id,
    kullanici_adi,
    TO_CHAR(islem_zamani, 'DD.MM.YYYY HH24:MI:SS') AS zaman,
    islem_turu,
    eski_deger  AS "Eski ADR",
    yeni_deger  AS "Denenen ADR",
    aciklama
FROM guvenlik_loglari
ORDER BY islem_zamani DESC;

RESET ROLE;

-- ────────────────────────────────────────────────────────────
-- 7. Mevcut RLS politikalarını listele
-- ────────────────────────────────────────────────────────────
SELECT
    policyname   AS politika_adi,
    roles        AS roller,
    cmd          AS komut,
    qual         AS kosul
FROM pg_policies
WHERE tablename = 'rezervasyonlar'
ORDER BY policyname;
