-- ============================================================
-- FAZ 1 - ADIM 2: Erişim Yönetimi (RBAC + RLS)
-- Roller: city_reception, resort_reception, admin
-- ============================================================

-- ============================================================
-- BÖLÜM A: ROL OLUŞTURMA (RBAC - Role-Based Access Control)
-- ============================================================

-- Önceki rolleri temizle (idempotent script için)
DROP ROLE IF EXISTS city_reception;
DROP ROLE IF EXISTS resort_reception;
DROP ROLE IF EXISTS admin;

-- 1. City Hotel resepsiyonisti
CREATE ROLE city_reception WITH LOGIN PASSWORD 'CityHotel2024!';

-- 2. Resort Hotel resepsiyonisti
CREATE ROLE resort_reception WITH LOGIN PASSWORD 'ResortHotel2024!';

-- 3. Genel Müdür / Admin (her iki oteli de görür)
CREATE ROLE admin WITH LOGIN PASSWORD 'AdminSuper2024!';

-- ============================================================
-- BÖLÜM B: TABLO YETKİLERİ (GRANT)
-- ============================================================

-- rezervasyonlar tablosuna temel erişim izinleri
GRANT SELECT ON TABLE rezervasyonlar TO city_reception;
GRANT SELECT ON TABLE rezervasyonlar TO resort_reception;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE rezervasyonlar TO admin;

-- musteriler tablosuna erişim
GRANT SELECT ON TABLE musteriler TO city_reception;
GRANT SELECT ON TABLE musteriler TO resort_reception;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE musteriler TO admin;

-- Sequence erişimi (admin için)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO admin;

-- ============================================================
-- BÖLÜM C: ROW-LEVEL SECURITY (RLS) - Satır Düzeyinde Güvenlik
-- ============================================================

-- rezervasyonlar tablosunda RLS'yi etkinleştir
ALTER TABLE rezervasyonlar ENABLE ROW LEVEL SECURITY;
ALTER TABLE rezervasyonlar FORCE ROW LEVEL SECURITY;

-- Mevcut politikaları temizle
DROP POLICY IF EXISTS city_hotel_policy ON rezervasyonlar;
DROP POLICY IF EXISTS resort_hotel_policy ON rezervasyonlar;
DROP POLICY IF EXISTS admin_full_access ON rezervasyonlar;

-- POLİTİKA 1: city_reception → sadece 'City Hotel' satırlarını görür
CREATE POLICY city_hotel_policy
    ON rezervasyonlar
    FOR ALL
    TO city_reception
    USING (hotel = 'City Hotel');

-- POLİTİKA 2: resort_reception → sadece 'Resort Hotel' satırlarını görür
CREATE POLICY resort_hotel_policy
    ON rezervasyonlar
    FOR ALL
    TO resort_reception
    USING (hotel = 'Resort Hotel');

-- POLİTİKA 3: admin → tüm satırları görür (bypass)
CREATE POLICY admin_full_access
    ON rezervasyonlar
    FOR ALL
    TO admin
    USING (true);

-- ============================================================
-- DOĞRULAMA TESTLERİ
-- ============================================================

-- Test 1: city_reception olarak bağlanıp sorgu çek
-- (Bu sorgu yalnızca City Hotel satırlarını döndürmeli)
-- SET ROLE city_reception;
-- SELECT hotel, COUNT(*) FROM rezervasyonlar GROUP BY hotel;
-- RESET ROLE;

-- Test 2: resort_reception olarak bağlanıp sorgu çek
-- (Bu sorgu yalnızca Resort Hotel satırlarını döndürmeli)
-- SET ROLE resort_reception;
-- SELECT hotel, COUNT(*) FROM rezervasyonlar GROUP BY hotel;
-- RESET ROLE;

-- Test 3: admin her iki oteli de görmeli
-- SET ROLE admin;
-- SELECT hotel, COUNT(*) FROM rezervasyonlar GROUP BY hotel;
-- RESET ROLE;

-- Mevcut politikaları listele
SELECT
    schemaname,
    tablename,
    policyname,
    roles,
    cmd,
    qual
FROM pg_policies
WHERE tablename = 'rezervasyonlar'
ORDER BY policyname;
