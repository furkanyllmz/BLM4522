-- ============================================================
-- ADIM 1: Yedekleme Stratejileri (Tam / Fark / Artık)
--
-- PostgreSQL'de yedekleme iki ana yöntemle yapılır:
--   A) Mantıksal yedek  -> pg_dump / pg_dumpall (tablo & veri SQL'i)
--   B) Fiziksel yedek    -> pg_basebackup + WAL arşivi (PITR temeli)
--
-- Ödevdeki kavram karşılıkları:
--   Tam Yedekleme   (Full)         -> pg_dump / pg_basebackup (tüm DB)
--   Fark Yedekleme  (Differential) -> son tam yedekten beri biriken WAL
--   Artık Yedekleme (Incremental)  -> son yedekten beri biriken WAL
--                                      (PostgreSQL 17+ : pg_basebackup --incremental)
--
-- NOT: pg_dump bir KOMUT SATIRI aracıdır, psql içinden değil terminalden
-- çalıştırılır. Bu dosyadaki komutlar referans/dökümantasyon amaçlıdır;
-- gerçek çalıştırılacak komutlar \echo ile gösterilmiştir.
-- Çalıştırılabilir hali için: backup_sql/scripts/ klasörüne bakın.
-- ============================================================

\connect backup_demo

\echo '=========================================='
\echo ' YEDEKLEME STRATEJILERI'
\echo '=========================================='

-- ============================================================
-- 1.1 TAM YEDEKLEME (FULL BACKUP) - Mantıksal
--
-- Tüm veritabanını tek bir dosyaya alır. En basit ve taşınabilir yöntem.
-- ============================================================

\echo ''
\echo '--- 1.1 TAM YEDEKLEME (pg_dump) ---'
\echo 'Terminalde calistirilacak komutlar:'
\echo ''
\echo '# Custom format (sikistirilmis, pg_restore ile esnek geri yukleme):'
\echo 'pg_dump -U postgres -F c -b -v -f backups/backup_demo_full.dump backup_demo'
\echo ''
\echo '# Plain SQL format (insan tarafindan okunabilir):'
\echo 'pg_dump -U postgres -F p -f backups/backup_demo_full.sql backup_demo'
\echo ''
\echo '# Tum cluster (roller dahil tum veritabanlari):'
\echo 'pg_dumpall -U postgres -f backups/cluster_full.sql'
\echo ''
\echo 'Parametreler:'
\echo '  -F c : custom format   -F p : plain SQL   -F t : tar'
\echo '  -b   : large object dahil'
\echo '  -v   : verbose (detayli cikti)'

-- ============================================================
-- 1.2 FARK / ARTIK YEDEKLEME (WAL Arşivleme Temeli)
--
-- PostgreSQL'de "fark" ve "artık" yedekleme, WAL (Write-Ahead Log)
-- dosyalarının arşivlenmesi ile sağlanır. Mantık şudur:
--   1) Bir kez TAM fiziksel yedek alınır (base backup)
--   2) Sonrasında sadece DEĞİŞEN WAL kayıtları arşivlenir
--   3) Geri yükleme = base backup + WAL'ların yeniden oynatılması
--
-- Bu, "sadece değişeni yedekleme" yani incremental mantığıdır.
-- ============================================================

\echo ''
\echo '--- 1.2 WAL ARSIVLEME (Fark/Artik temeli) ---'
\echo 'postgresql.conf icinde su ayarlar acilmalidir:'
\echo ''
\echo "  wal_level = replica"
\echo "  archive_mode = on"
\echo "  archive_command = 'cp %p /Users/furkanyilmaz/BLM4522_proje3/backup_sql/wal_archive/%f'"
\echo ''

-- Mevcut WAL ayarlarını kontrol et
SELECT name, setting, short_desc
FROM pg_settings
WHERE name IN ('wal_level', 'archive_mode', 'archive_command', 'max_wal_size')
ORDER BY name;

-- ============================================================
-- 1.3 FİZİKSEL TAM YEDEK (pg_basebackup) - PITR temeli
-- ============================================================

\echo ''
\echo '--- 1.3 FIZIKSEL TAM YEDEK (pg_basebackup) ---'
\echo 'Terminalde:'
\echo ''
\echo '# Tum data dizininin fiziksel kopyasi (PITR icin base):'
\echo 'pg_basebackup -U postgres -D backups/base_$(date +%Y%m%d) -F t -z -P -X stream'
\echo ''
\echo '# PostgreSQL 17+ ARTIK (incremental) yedek:'
\echo '#   Once manifest ile tam yedek, sonra sadece degisenler:'
\echo 'pg_basebackup -U postgres -D backups/base_full -X stream'
\echo 'pg_basebackup -U postgres -D backups/base_incr \\'
\echo '    --incremental=backups/base_full/backup_manifest -X stream'

-- ============================================================
-- 1.4 GENEL STRATEJİ ÖZETİ
--
-- Tipik bir kurumsal yedekleme planı:
--   - Haftada 1 kez  -> TAM yedek      (Pazar gecesi)
--   - Her gün        -> FARK yedek     (son tam yedekten beri)
--   - Sürekli        -> WAL arşivi     (her işlem, PITR için)
-- ============================================================

\echo ''
\echo '--- 1.4 ONERILEN YEDEKLEME TAKVIMI ---'

-- Strateji tablosunu kayıt altına alalım (raporlama için)
CREATE TABLE IF NOT EXISTS backup_strategy (
    id            SERIAL PRIMARY KEY,
    yedek_tipi    VARCHAR(30),
    siklik        VARCHAR(40),
    yontem        VARCHAR(60),
    aciklama      TEXT
);

TRUNCATE backup_strategy RESTART IDENTITY;

INSERT INTO backup_strategy (yedek_tipi, siklik, yontem, aciklama) VALUES
    ('Tam',   'Haftalik (Pazar 02:00)', 'pg_dump / pg_basebackup', 'Tum veritabaninin tam kopyasi'),
    ('Fark',  'Gunluk (her gece 02:00)', 'WAL arsivi (son tam yedekten beri)', 'Sadece son TAM yedekten beri degisenler'),
    ('Artik', 'Saatlik / surekli',       'WAL streaming + archive', 'Son herhangi bir yedekten beri degisenler'),
    ('PITR',  'Surekli',                 'base backup + WAL replay', 'Belirli bir ana geri donus imkani');

SELECT yedek_tipi, siklik, yontem, aciklama FROM backup_strategy ORDER BY id;

\echo ''
\echo 'Yedekleme stratejileri tanimlandi.'
