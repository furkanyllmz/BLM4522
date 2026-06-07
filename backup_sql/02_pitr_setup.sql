-- ============================================================
-- ADIM 2: Point-in-Time Recovery (PITR) Yapılandırması
--
-- PITR = Belirli bir AN'a (ör. "kaza silmeden 1 dk önce") geri dönüş.
-- SQL Server'daki "Point-in-time restore" özelliğinin karşılığıdır.
--
-- Mantık:
--   1) Bir TAM fiziksel yedek (base backup) alınır
--   2) Sürekli WAL dosyaları arşivlenir
--   3) Felaket anında: base backup geri yüklenir + WAL'lar
--      İSTENEN ANA KADAR yeniden oynatılır (recovery_target_time)
--
-- NOT: PITR yapılandırması sunucu seviyesindedir (postgresql.conf).
-- Bu dosya hem ayarları gösterir hem de mevcut durumu sorgular.
-- ============================================================

\connect backup_demo

\echo '=========================================='
\echo ' POINT-IN-TIME RECOVERY (PITR) KURULUMU'
\echo '=========================================='

-- ============================================================
-- 2.1 GEREKLİ SUNUCU AYARLARI (postgresql.conf)
-- ============================================================

\echo ''
\echo '--- 2.1 postgresql.conf ayarlari ---'
\echo ''
\echo "wal_level = replica          # WAL'a yeterli bilgi yaz"
\echo "archive_mode = on            # arsivlemeyi ac"
\echo "archive_command = 'test ! -f /yol/wal_archive/%f && cp %p /yol/wal_archive/%f'"
\echo "max_wal_senders = 3          # replikasyon/yedek baglantilari"
\echo ""
\echo 'Ayar sonrasi: sudo systemctl restart postgresql (veya pg_ctl restart)'

-- Mevcut ayarları doğrula
SELECT name, setting
FROM pg_settings
WHERE name IN ('wal_level','archive_mode','archive_command','max_wal_senders')
ORDER BY name;

-- ============================================================
-- 2.2 BASE BACKUP ALMA (PITR başlangıç noktası)
-- ============================================================

\echo ''
\echo '--- 2.2 BASE BACKUP (Terminalde) ---'
\echo 'pg_basebackup -U postgres -D backup_sql/base_backup -F p -X stream -P'
\echo ''
\echo 'Bu komut, su andaki tam fiziksel durumu kaydeder.'
\echo 'Bundan SONRAKI tum degisiklikler WAL ile takip edilir.'

-- ============================================================
-- 2.3 GERİ YÜKLEME (RESTORE) ADIMLARI - İSTENEN ANA
--
-- Felaket sonrası izlenecek adımlar (terminalde):
-- ============================================================

\echo ''
\echo '--- 2.3 PITR GERI YUKLEME ADIMLARI ---'
\echo ''
\echo '1) PostgreSQL servisini durdur:'
\echo '   sudo systemctl stop postgresql'
\echo ''
\echo '2) Bozuk/mevcut data dizinini yedekle ve temizle:'
\echo '   mv $PGDATA $PGDATA_bozuk'
\echo ''
\echo '3) base_backup icerigini data dizinine kopyala:'
\echo '   cp -R backup_sql/base_backup/* $PGDATA/'
\echo ''
\echo '4) recovery hedefini ayarla. postgresql.conf icine ekle:'
\echo "   restore_command = 'cp backup_sql/wal_archive/%f %p'"
\echo "   recovery_target_time = '2026-06-04 14:30:00'   # silmeden hemen ONCE"
\echo "   recovery_target_action = 'promote'"
\echo ''
\echo '5) Recovery sinyal dosyasini olustur:'
\echo '   touch $PGDATA/recovery.signal'
\echo ''
\echo '6) Servisi baslat. PostgreSQL WALlari hedef ana kadar oynatir:'
\echo '   sudo systemctl start postgresql'

-- ============================================================
-- 2.4 GERİ YÜKLEME HEDEFİ SEÇENEKLERİ
--
-- PITR'da hedef farklı şekillerde belirtilebilir:
-- ============================================================

\echo ''
\echo '--- 2.4 RECOVERY HEDEF SECENEKLERI ---'

CREATE TABLE IF NOT EXISTS pitr_recovery_targets (
    parametre     VARCHAR(40),
    aciklama      TEXT,
    ornek         TEXT
);

TRUNCATE pitr_recovery_targets;

INSERT INTO pitr_recovery_targets (parametre, aciklama, ornek) VALUES
    ('recovery_target_time', 'Belirli bir zamana geri don',        '2026-06-04 14:30:00'),
    ('recovery_target_xid',  'Belirli bir islem (transaction) ID', '123456'),
    ('recovery_target_lsn',  'Belirli bir WAL pozisyonu (LSN)',    '0/3000000'),
    ('recovery_target_name', 'Onceden isaretlenmis restore point', 'silme_oncesi'),
    ('recovery_target',      'En son tutarli ana kadar (immediate)','immediate');

SELECT parametre, aciklama, ornek FROM pitr_recovery_targets;

-- ============================================================
-- 2.5 İSİMLENDİRİLMİŞ KURTARMA NOKTASI (Restore Point)
--
-- Riskli bir işlem öncesi manuel kontrol noktası oluşturulabilir.
-- Sonra PITR ile "silme_oncesi" noktasına dönülebilir.
-- ============================================================

\echo ''
\echo '--- 2.5 ISIMLENDIRILMIS KURTARMA NOKTASI ---'
\echo 'Riskli bir islem oncesi calistir (superuser gerekir):'
\echo "   SELECT pg_create_restore_point('silme_oncesi');"

-- Mevcut WAL pozisyonunu göster (kayıt için)
SELECT
    pg_current_wal_lsn()        AS guncel_wal_pozisyonu,
    pg_walfile_name(pg_current_wal_lsn()) AS guncel_wal_dosyasi,
    now()                       AS su_an;

\echo ''
\echo 'PITR yapilandirma rehberi tamamlandi.'
