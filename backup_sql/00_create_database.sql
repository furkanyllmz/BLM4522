-- ============================================================
-- ADIM 0: Yedekleme Demo Veritabanı ve Örnek Veri
-- Komut: psql -U postgres -f backup_sql/00_create_database.sql
--
-- Bu veritabanı, yedekleme ve felaketten kurtarma senaryolarını
-- temiz ve kontrollü bir şekilde göstermek için kurulur.
-- ============================================================

DROP DATABASE IF EXISTS backup_demo;

CREATE DATABASE backup_demo
    WITH
    OWNER      = postgres
    ENCODING   = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE   = 'en_US.UTF-8'
    TEMPLATE   = template0;

\connect backup_demo

-- ============================================================
-- 0.1 ÖRNEK İŞ TABLOSU: Müşteri Siparişleri
-- (Kaza ile silme/kurtarma senaryolarında kullanılacak)
-- ============================================================

CREATE TABLE customers (
    customer_id   SERIAL PRIMARY KEY,
    full_name     VARCHAR(100) NOT NULL,
    email         VARCHAR(120) UNIQUE NOT NULL,
    city          VARCHAR(60),
    created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE orders (
    order_id      SERIAL PRIMARY KEY,
    customer_id   INT NOT NULL REFERENCES customers(customer_id),
    product_name  VARCHAR(120) NOT NULL,
    quantity      INT NOT NULL CHECK (quantity > 0),
    unit_price    NUMERIC(10,2) NOT NULL,
    total_price   NUMERIC(12,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    order_date    TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE customers IS 'Yedekleme demosu için örnek müşteri tablosu';
COMMENT ON TABLE orders    IS 'Yedekleme demosu için örnek sipariş tablosu';

-- ============================================================
-- 0.2 BAŞLANGIÇ VERİSİ
-- ============================================================

INSERT INTO customers (full_name, email, city) VALUES
    ('Ahmet Yılmaz',  'ahmet@example.com',  'İstanbul'),
    ('Ayşe Demir',    'ayse@example.com',   'Ankara'),
    ('Mehmet Kaya',   'mehmet@example.com', 'İzmir'),
    ('Fatma Şahin',   'fatma@example.com',  'Bursa'),
    ('Can Öztürk',    'can@example.com',    'Antalya');

INSERT INTO orders (customer_id, product_name, quantity, unit_price) VALUES
    (1, 'Laptop',        1, 25000.00),
    (1, 'Mouse',         2,   350.00),
    (2, 'Klavye',        1,   850.00),
    (3, 'Monitör',       2,  4500.00),
    (4, 'Kulaklık',      3,  1200.00),
    (5, 'Webcam',        1,   950.00),
    (2, 'USB Bellek',    5,   180.00);

-- ============================================================
-- 0.3 DOĞRULAMA
-- ============================================================

SELECT 'customers' AS tablo, COUNT(*) AS kayit_sayisi FROM customers
UNION ALL
SELECT 'orders',  COUNT(*) FROM orders;

\echo 'backup_demo veritabani ve ornek veri hazir.'
