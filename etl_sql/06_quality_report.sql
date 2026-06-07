-- ============================================================
-- ADIM 6: Veri Kalitesi Raporları
-- Komut: psql -U postgres -d etl_demo -f etl_sql/06_quality_report.sql
--
-- "Veri temizleme ve dönüştürme sürecine dair raporların
--  oluşturulması"
--
-- Bu rapor 4 başlıkta ETL sürecinin SONUCUNU özetler:
--   • ETL adım adım çalışma kaydı (log)
--   • ÖNCE / SONRA kalite karşılaştırması
--   • Reddedilen kayıtların detayı ve sebepleri
--   • İş değeri sorguları (hedef veriden raporlar)
-- ============================================================

\connect etl_demo

\echo '=========================================='
\echo ' VERI KALITESI RAPORU'
\echo '=========================================='

-- ============================================================
-- 6.1 ETL SÜREÇ AKIŞI (Adım adım log)
-- ============================================================

\echo ''
\echo '--- 6.1 ETL surec akisi (her adim) ---'

SELECT
    id,
    etl_step       AS adim,
    layer          AS katman,
    rows_in        AS giris_satir,
    rows_out       AS cikis_satir,
    rows_rejected  AS reddedilen,
    notes          AS aciklama
FROM target.etl_log
ORDER BY id;

-- ============================================================
-- 6.2 ÖNCE / SONRA KALİTE KARŞILAŞTIRMASI
--
-- 02'de "ONCE" durumunu kaydetmiştik. Şimdi "SONRA" durumunu
-- hesaplayıp yan yana koyuyoruz.
-- ============================================================

\echo ''
\echo '--- 6.2 ONCE / SONRA kalite karsilastirmasi ---'

-- Önceki SONRA kayıtlarını temizle (rapor tekrar çalışınca çiftlenmesin)
DELETE FROM target.quality_profile WHERE asama = 'SONRA';

-- SONRA metriklerini ekle (hedef tablodan)
INSERT INTO target.quality_profile (asama, metrik, deger)
SELECT 'SONRA', 'toplam_ham_kayit',
       (SELECT COUNT(*) FROM staging.online_sales) + (SELECT COUNT(*) FROM staging.store_sales)
UNION ALL SELECT 'SONRA', 'eksik_eposta',
       -- müşteriye bağlanamayan (e-postası olmayan) satışlar
       (SELECT COUNT(*) FROM target.fact_sales WHERE musteri_id IS NULL)
UNION ALL SELECT 'SONRA', 'eksik_sehir',
       (SELECT COUNT(*) FROM target.fact_sales WHERE sehir IS NULL OR TRIM(sehir)='')
UNION ALL SELECT 'SONRA', 'gecersiz_eposta_format', 0
UNION ALL SELECT 'SONRA', 'negatif_fiyat',
       (SELECT COUNT(*) FROM target.fact_sales WHERE birim_fiyat_try < 0)
UNION ALL SELECT 'SONRA', 'sifir_adet',
       (SELECT COUNT(*) FROM target.fact_sales WHERE adet = 0)
UNION ALL SELECT 'SONRA', 'gecersiz_adet', 0;

-- Yan yana karşılaştırma
SELECT
    o.metrik,
    o.deger        AS once,
    s.deger        AS sonra,
    GREATEST(o.deger - s.deger, 0) AS duzeltilen
FROM target.quality_profile o
JOIN target.quality_profile s
  ON o.metrik = s.metrik AND o.asama='ONCE' AND s.asama='SONRA'
ORDER BY o.metrik;

-- ============================================================
-- 6.3 GENEL KALİTE SKORU
--
-- Kaç ham kayıttan kaçı temiz hedefe ulaştı? (başarı oranı)
-- ============================================================

\echo ''
\echo '--- 6.3 ETL basari orani ---'

SELECT
    (SELECT COUNT(*) FROM clean.merged_raw)        AS ham_kayit,
    (SELECT COUNT(*) FROM clean.rejected)          AS reddedilen,
    (SELECT COUNT(*) FROM target.fact_sales)       AS yuklenen,
    ROUND(
        (SELECT COUNT(*) FROM target.fact_sales)::NUMERIC
        / NULLIF((SELECT COUNT(*) FROM clean.merged_raw), 0) * 100, 1
    )                                               AS basari_orani_pct;

-- ============================================================
-- 6.4 REDDEDİLEN KAYITLAR RAPORU (sebep dağılımı)
-- ============================================================

\echo ''
\echo '--- 6.4 Reddedilen kayitlar (sebep dagilimi) ---'

SELECT sebep, COUNT(*) AS adet
FROM clean.rejected
GROUP BY sebep
ORDER BY adet DESC, sebep;

\echo 'Reddedilen kayitlarin detayi:'
SELECT ad, urun, fiyat, adet, sebep, kaynak FROM clean.rejected ORDER BY sebep;

-- ============================================================
-- 6.5 KAYNAK BAZLI DAĞILIM (entegrasyon doğrulama)
-- ============================================================

\echo ''
\echo '--- 6.5 Kaynak bazli dagilim ---'

SELECT
    kaynak,
    COUNT(*)                       AS satis_adedi,
    SUM(toplam_tutar_try)          AS toplam_ciro_try
FROM target.fact_sales
GROUP BY kaynak
ORDER BY kaynak;

-- ============================================================
-- 6.6 İŞ DEĞERİ RAPORLARI (Temiz veriden analiz)
--
-- ETL'in amacı: kirli veriyi güvenilir RAPORLANABILIR hale getirmek.
-- ============================================================

\echo ''
\echo '--- 6.6 Sehir bazli satis ozeti ---'

SELECT
    COALESCE(NULLIF(TRIM(f.sehir),''), '(bilinmiyor)') AS sehir,
    COUNT(*)                       AS satis_adedi,
    SUM(f.toplam_tutar_try)        AS toplam_ciro_try
FROM target.fact_sales f
GROUP BY COALESCE(NULLIF(TRIM(f.sehir),''), '(bilinmiyor)')
ORDER BY toplam_ciro_try DESC;

\echo '--- En cok ciro yapan urunler ---'

SELECT
    urun,
    SUM(adet)                      AS toplam_adet,
    SUM(toplam_tutar_try)          AS toplam_ciro_try
FROM target.fact_sales
GROUP BY urun
ORDER BY toplam_ciro_try DESC;

\echo '--- Aylik satis trendi ---'

SELECT
    satis_yili AS yil,
    satis_ayi  AS ay,
    COUNT(*)                       AS satis_adedi,
    SUM(toplam_tutar_try)          AS aylik_ciro_try
FROM target.fact_sales
GROUP BY satis_yili, satis_ayi
ORDER BY satis_yili, satis_ayi;

\echo ''
\echo '=========================================='
\echo ' ETL SURECI VE KALITE RAPORU TAMAMLANDI'
\echo '=========================================='
