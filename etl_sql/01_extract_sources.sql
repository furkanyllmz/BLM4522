-- ============================================================
-- ADIM 1: EXTRACT — Kaynak Verilerin Çıkarılması
-- Komut: psql -U postgres -d etl_demo -f etl_sql/01_extract_sources.sql
--
-- İki FARKLI kaynak sistemden veri geldiğini simüle ediyoruz:
--   Kaynak A: online_sales  -> Web/online satış sistemi
--   Kaynak B: store_sales    -> Fiziksel şube/mağaza sistemi
--
-- Her iki kaynak da GERÇEK HAYATTAKİ gibi "kirli" veri içerir:
--   • Eksik değerler (NULL / boş / 'N/A')
--   • Tutarsız yazımlar (istanbul / İSTANBUL / ist.)
--   • Yanlış formatlar (tarih, telefon, e-posta)
--   • Aykırı/hatalı değerler (negatif fiyat, gelecek tarih)
--   • Mükerrer kayıtlar
--   • Farklı para birimleri (TRY / USD) ve farklı sütun düzeni
--
-- Bu kirlilikler sonraki adımlarda (02-06) temizlenecektir.
-- ============================================================

\connect etl_demo

\echo '=========================================='
\echo ' EXTRACT: Kaynak verilerin yuklenmesi'
\echo '=========================================='

-- ============================================================
-- 1.1 KAYNAK A: ONLINE SATIŞ SİSTEMİ (staging.online_sales)
--
-- Her şey TEXT olarak gelir — çünkü kaynak sistem veriyi
-- doğrulamadan dışa aktarır (gerçek hayatta CSV/JSON böyledir).
-- ============================================================

DROP TABLE IF EXISTS staging.online_sales;

CREATE TABLE staging.online_sales (
    raw_id        SERIAL PRIMARY KEY,
    musteri_adi   TEXT,
    eposta        TEXT,
    telefon       TEXT,
    sehir         TEXT,
    urun          TEXT,
    adet          TEXT,     -- bilerek TEXT (kirli sayılar)
    birim_fiyat   TEXT,     -- bilerek TEXT
    para_birimi   TEXT,
    satis_tarihi  TEXT,     -- bilerek TEXT (karışık format)
    kaynak        TEXT DEFAULT 'online'
);

INSERT INTO staging.online_sales
    (musteri_adi, eposta, telefon, sehir, urun, adet, birim_fiyat, para_birimi, satis_tarihi) VALUES
    -- normal kayıtlar
    ('Ahmet Yılmaz',  'ahmet@example.com',   '0532 111 2233', 'İstanbul',  'Laptop',   '1',  '25000',  'TRY', '2024-01-15'),
    ('Ayşe Demir',    'AYSE@EXAMPLE.COM',     '532-222-3344',  'istanbul',  'Mouse',    '2',  '350',    'TRY', '2024-01-16'),
    -- tutarsız şehir yazımı
    ('Mehmet Kaya',   'mehmet@example.com',  '05333334455',   'ISTANBUL',  'Klavye',   '1',  '850',    'TRY', '15.01.2024'),
    ('Fatma Şahin',   'fatma@example.com',   '0534 444 5566', 'ankara',    'Monitör',  '2',  '4500',   'TRY', '2024/01/17'),
    ('Can Öztürk',    'can@example.com',     '535 555 6677',  'Ankara ',   'Kulaklık', '3',  '1200',   'TRY', '2024-01-18'),
    -- EKSİK e-posta
    ('Zeynep Acar',   NULL,                  '0536 666 7788', 'İzmir',     'Webcam',   '1',  '950',    'TRY', '2024-01-19'),
    ('Burak Çelik',   '',                    '537 777 8899',  'izmir',     'USB Bellek','5', '180',    'TRY', '2024-01-20'),
    -- EKSİK / hatalı sayısal değer
    ('Elif Yıldız',   'elif@example.com',    '0538 888 9900', 'Bursa',     'Laptop',   'N/A','25000',  'TRY', '2024-01-21'),
    ('Okan Arslan',   'okan@example.com',    '539 999 0011',  'BURSA',     'Mouse',    '2',  '-350',   'TRY', '2024-01-22'),  -- negatif fiyat
    -- USD para birimi (dönüştürülmeli)
    ('John Smith',    'john@example.com',    '+1 555 123 456','İstanbul',  'Monitör',  '1',  '150',    'USD', '2024-01-23'),
    -- MÜKERRER kayıt (Ahmet Yılmaz tekrar — birebir aynı satış)
    ('Ahmet Yılmaz',  'ahmet@example.com',   '0532 111 2233', 'İstanbul',  'Laptop',   '1',  '25000',  'TRY', '2024-01-15'),
    -- isimde fazla boşluk + karışık büyük/küçük harf
    ('  veli  KURT ', 'veli@example.com',    '0540 111 2222', 'antalya',   'Webcam',   '1',  '950',    'TRY', '2024-01-24'),
    -- gelecek tarih (hatalı)
    ('Selin Aydın',   'selin@example.com',   '0541 222 3333', 'İzmir',     'Klavye',   '1',  '850',    'TRY', '2099-12-31');

-- ============================================================
-- 1.2 KAYNAK B: ŞUBE/MAĞAZA SİSTEMİ (staging.store_sales)
--
-- Aynı iş verisi ama FARKLI sütun isimleri ve düzeni —
-- gerçek hayatta her sistem kendi şemasını kullanır.
-- Veri entegrasyonunda bunları ortak modele getirmek gerekir.
-- ============================================================

DROP TABLE IF EXISTS staging.store_sales;

CREATE TABLE staging.store_sales (
    raw_id        SERIAL PRIMARY KEY,
    full_name     TEXT,
    email_addr    TEXT,
    phone         TEXT,
    city_name     TEXT,
    product_name  TEXT,
    qty           TEXT,
    price         TEXT,
    currency      TEXT,
    sale_dt       TEXT,
    kaynak        TEXT DEFAULT 'store'
);

INSERT INTO staging.store_sales
    (full_name, email_addr, phone, city_name, product_name, qty, price, currency, sale_dt) VALUES
    ('Hakan Şahin',   'hakan@example.com',   '0542 333 4444', 'İstanbul',  'Laptop',    '1', '24500', 'TRY', '2024-02-01'),
    ('Deniz Polat',   'deniz@example.com',   '543 444 5555',  'Ankara',    'Mouse',     '3', '350',   'TRY', '2024-02-02'),
    -- şehir kısaltması
    ('Cem Toprak',    'cem@example.com',     '0544 555 6666', 'ist.',      'Monitör',   '2', '4400',  'TRY', '2024-02-03'),
    -- eksik şehir
    ('Gül Erim',      'gul@example.com',     '0545 666 7777', NULL,        'Kulaklık',  '1', '1200',  'TRY', '2024-02-04'),
    -- hatalı e-posta formatı (@ yok)
    ('Ozan Bal',      'ozan.example.com',    '0546 777 8888', 'İzmir',     'Webcam',    '2', '950',   'TRY', '2024-02-05'),
    -- adet sıfır (geçersiz)
    ('Pınar Ak',      'pinar@example.com',   '0547 888 9999', 'Bursa',     'USB Bellek','0', '180',   'TRY', '2024-02-06'),
    -- USD
    ('Emma Brown',    'emma@example.com',    '+1 555 987 654','İstanbul',  'Laptop',    '1', '780',   'USD', '2024-02-07'),
    -- MÜKERRER (Hakan Şahin tekrar)
    ('Hakan Şahin',   'hakan@example.com',   '0542 333 4444', 'İstanbul',  'Laptop',    '1', '24500', 'TRY', '2024-02-01'),
    -- boşluklu/karışık şehir
    ('Murat Demir',   'murat@example.com',   '0548 999 0000', '  izMir ',  'Klavye',    '1', '850',   'TRY', '2024-02-08');

-- ============================================================
-- 1.3 EXTRACT DOĞRULAMA
-- ============================================================

\echo ''
\echo '--- Cikarilan ham veri ozeti ---'

SELECT 'staging.online_sales' AS kaynak_tablo, COUNT(*) AS ham_satir FROM staging.online_sales
UNION ALL
SELECT 'staging.store_sales',  COUNT(*) FROM staging.store_sales;

-- ETL log kaydı
SELECT target.log_etl(
    'EXTRACT', 'staging',
    (SELECT COUNT(*) FROM staging.online_sales) + (SELECT COUNT(*) FROM staging.store_sales),
    (SELECT COUNT(*) FROM staging.online_sales) + (SELECT COUNT(*) FROM staging.store_sales),
    0,
    'Iki kaynaktan ham veri cikarildi (online + store)'
);

\echo ''
\echo 'EXTRACT tamamlandi: iki kaynaktan ham veri staging katmanina yuklendi.'
