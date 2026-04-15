-- ============================================================
-- FAZ 1 - ADIM 3: Audit Log Tablosu ve Fiyat Değişiklik Trigger'ı
-- Hikaye: Yetkisiz fiyat değişikliklerini engelle ve kaydet
-- ============================================================

-- ============================================================
-- BÖLÜM A: GÜVENLİK LOGLARI TABLOSU
-- ============================================================
DROP TABLE IF EXISTS guvenlik_loglari CASCADE;

CREATE TABLE guvenlik_loglari (
    log_id          SERIAL PRIMARY KEY,
    kullanici_adi   TEXT,
    islem_zamani    TIMESTAMP DEFAULT NOW(),
    tablo_adi       TEXT,
    islem_turu      TEXT,          -- 'ENGELLENDI' veya 'IZIN VERILDI'
    aciklama        TEXT,
    eski_deger      NUMERIC(10,2),
    yeni_deger      NUMERIC(10,2),
    rezervasyon_id  INTEGER
);

-- Admin bu tabloyu tam okuyabilir, diğerleri okuyamaz
GRANT SELECT, INSERT ON guvenlik_loglari TO admin;
GRANT INSERT ON guvenlik_loglari TO city_reception;
GRANT INSERT ON guvenlik_loglari TO resort_reception;
GRANT USAGE, SELECT ON SEQUENCE guvenlik_loglari_log_id_seq TO city_reception;
GRANT USAGE, SELECT ON SEQUENCE guvenlik_loglari_log_id_seq TO resort_reception;
GRANT USAGE, SELECT ON SEQUENCE guvenlik_loglari_log_id_seq TO admin;

-- ============================================================
-- BÖLÜM B: FİYAT DEĞİŞİKLİK TRIGGER FONKSİYONU
-- ============================================================
CREATE OR REPLACE FUNCTION fiyat_degisiklik_kontrol()
RETURNS TRIGGER AS $$
DECLARE
    mevcut_kullanici TEXT;
    degisim_orani    NUMERIC;
BEGIN
    mevcut_kullanici := current_user;

    -- Sadece ADR (fiyat) kolonunda değişiklik varsa devam et
    IF OLD.adr IS DISTINCT FROM NEW.adr THEN

        -- Değişim oranını hesapla
        degisim_orani := ROUND(
            ((NEW.adr - OLD.adr) / NULLIF(OLD.adr, 0)) * 100,
            2
        );

        -- KURAL 1: Resepsiyonistler fiyat DEĞİŞTİREMEZ
        IF mevcut_kullanici IN ('city_reception', 'resort_reception') THEN

            -- Yetkisiz denemeyi logla
            INSERT INTO guvenlik_loglari (
                kullanici_adi,
                islem_zamani,
                tablo_adi,
                islem_turu,
                aciklama,
                eski_deger,
                yeni_deger,
                rezervasyon_id
            ) VALUES (
                mevcut_kullanici,
                NOW(),
                TG_TABLE_NAME,
                'ENGELLENDI',
                FORMAT(
                    'Kullanici: %s | Saat: %s | Islem: Yetkisiz Fiyat Degisiklik Denemesi | Otel: %s | Degisim: %%%s',
                    mevcut_kullanici,
                    TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS'),
                    OLD.hotel,
                    degisim_orani
                ),
                OLD.adr,
                NEW.adr,
                OLD.rezervasyon_id
            );

            -- İşlemi ENGELLE ve hata fırlat
            RAISE EXCEPTION
                'YETKİ HATASI: Kullanıcı "%" fiyat değiştiremez! '
                'Rezervasyon #% için eski fiyat: % TL, denenen yeni fiyat: % TL. '
                'Bu işlem güvenlik loglarına kaydedildi.',
                mevcut_kullanici,
                OLD.rezervasyon_id,
                OLD.adr,
                NEW.adr;

        -- KURAL 2: Admin fiyat değiştirebilir ama yine de loglanır
        ELSIF mevcut_kullanici = 'admin' THEN

            INSERT INTO guvenlik_loglari (
                kullanici_adi,
                islem_zamani,
                tablo_adi,
                islem_turu,
                aciklama,
                eski_deger,
                yeni_deger,
                rezervasyon_id
            ) VALUES (
                mevcut_kullanici,
                NOW(),
                TG_TABLE_NAME,
                'IZIN VERILDI',
                FORMAT(
                    'Kullanici: %s | Saat: %s | Islem: Admin Fiyat Guncelleme | Otel: %s | Degisim: %%%s',
                    mevcut_kullanici,
                    TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS'),
                    OLD.hotel,
                    degisim_orani
                ),
                OLD.adr,
                NEW.adr,
                OLD.rezervasyon_id
            );

            -- Admin işlemi GEÇİRİLİR
            RETURN NEW;
        END IF;

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- BÖLÜM C: TRIGGER'I TABLOYA BAĞLA
-- ============================================================
DROP TRIGGER IF EXISTS fiyat_koruma_trigger ON rezervasyonlar;

CREATE TRIGGER fiyat_koruma_trigger
    BEFORE UPDATE OF adr
    ON rezervasyonlar
    FOR EACH ROW
    EXECUTE FUNCTION fiyat_degisiklik_kontrol();

-- ============================================================
-- TEST SENARYOLARI
-- ============================================================

-- SENARYO 1: city_reception bir fiyatı değiştirmeye çalışır (ENGELLENMELI)
-- SET ROLE city_reception;
-- UPDATE rezervasyonlar
--     SET adr = 50.00
-- WHERE rezervasyon_id = 1;
-- → HATA: YETKİ HATASI mesajı görünmeli
-- RESET ROLE;

-- SENARYO 2: Logları admin olarak incele
-- SET ROLE admin;
-- SELECT
--     log_id,
--     kullanici_adi,
--     TO_CHAR(islem_zamani, 'DD.MM.YYYY HH24:MI:SS') AS zaman,
--     islem_turu,
--     aciklama,
--     eski_deger AS "Eski Fiyat",
--     yeni_deger AS "Denenen Fiyat"
-- FROM guvenlik_loglari
-- ORDER BY islem_zamani DESC;
-- RESET ROLE;

-- Trigger'ın oluşturulduğunu doğrula
SELECT
    trigger_name,
    event_manipulation,
    event_object_table,
    action_timing,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'rezervasyonlar';
