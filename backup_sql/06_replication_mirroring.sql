-- ============================================================
-- ADIM 6: Streaming Replication (Database Mirroring Karşılığı)
--
-- SQL Server'daki "Database Mirroring" özelliğinin PostgreSQL
-- karşılığı STREAMING REPLICATION'dır:
--   - Bir PRIMARY (ana) sunucu vardır
--   - Bir veya daha fazla STANDBY (yedek/replica) sunucu, WAL
--     kayıtlarını gerçek zamanlı alıp uygular
--   - Primary çökerse standby devralır (failover)
--
-- Bu, yüksek erişilebilirlik (HA) ve felaketten kurtarmanın
-- en güçlü katmanıdır: yedek SÜREKLİ günceldir.
--
-- NOT: Replikasyon iki ayrı sunucu/instance gerektirir. Bu
-- dosya yapılandırmayı gösterir ve replikasyon durumunu sorgular.
-- ============================================================

\connect backup_demo

\echo '=========================================='
\echo ' STREAMING REPLICATION (MIRRORING)'
\echo '=========================================='

-- ============================================================
-- 6.1 PRIMARY (ANA) SUNUCU AYARLARI
-- ============================================================

\echo ''
\echo '--- 6.1 PRIMARY SUNUCU AYARLARI ---'
\echo 'postgresql.conf:'
\echo "  wal_level = replica"
\echo "  max_wal_senders = 5        # standby baglanti sayisi"
\echo "  wal_keep_size = 512MB      # standby icin tutulacak WAL"
\echo "  hot_standby = on"
\echo ''
\echo 'pg_hba.conf (standby IPsine replikasyon izni):'
\echo "  host  replication  replicator  192.168.1.20/32  scram-sha-256"
\echo ''
\echo 'Replikasyon kullanicisi olustur (PRIMARYde):'
\echo "  CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'Repl@2024!';"

-- ============================================================
-- 6.2 STANDBY (YEDEK) SUNUCU KURULUMU
-- ============================================================

\echo ''
\echo '--- 6.2 STANDBY SUNUCU KURULUMU (Terminal) ---'
\echo ''
\echo '1) PRIMARYden temel kopya al (standby sunucuda calistir):'
\echo '   pg_basebackup -h 192.168.1.10 -U replicator \\'
\echo '       -D $PGDATA -F p -X stream -P -R'
\echo '   # -R parametresi otomatik olarak standby ayarlarini yazar'
\echo ''
\echo '2) standby.signal dosyasi olusur (-R sayesinde otomatik).'
\echo '   postgresql.auto.conf icine primary_conninfo eklenir:'
\echo "   primary_conninfo = 'host=192.168.1.10 user=replicator password=...'"
\echo ''
\echo '3) Standbyi baslat:'
\echo '   sudo systemctl start postgresql'
\echo '   # Standby artik PRIMARYi gercek zamanli takip eder.'

-- ============================================================
-- 6.3 REPLİKASYON DURUMUNU İZLEME (Primary üzerinde)
--
-- Bu sorgular gerçek bir replikasyon kurulu ise sonuç döndürür.
-- Tek sunucuda boş döner ama sorgu yapısı doğrudur.
-- ============================================================

\echo ''
\echo '--- 6.3 REPLIKASYON DURUMU IZLEME ---'

\echo 'Bagli standby sunucular ve gecikme:'
SELECT
    client_addr           AS standby_ip,
    state                 AS durum,
    sync_state            AS senkron_tipi,
    pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS gecikme_byte,
    write_lag,
    replay_lag
FROM pg_stat_replication;

\echo ''
\echo 'Bu sunucu standby mi (recovery modunda mi)?'
SELECT
    pg_is_in_recovery()   AS standby_modunda_mi,
    CASE WHEN pg_is_in_recovery()
         THEN 'STANDBY (replica)'
         ELSE 'PRIMARY (ana)'
    END AS sunucu_rolu;

-- ============================================================
-- 6.4 FAILOVER (Devralma) - Primary çökerse
-- ============================================================

\echo ''
\echo '--- 6.4 FAILOVER (Standby devralir) ---'
\echo 'PRIMARY coktuyse, standbyi PRIMARYye yukselt:'
\echo ''
\echo '   # Standby sunucuda:'
\echo '   pg_ctl promote -D $PGDATA'
\echo '   # veya:'
\echo "   SELECT pg_promote();"
\echo ''
\echo 'Artik eski standby yeni PRIMARYdir, yazma kabul eder.'

-- ============================================================
-- 6.5 SENKRON vs ASENKRON KARŞILAŞTIRMA
-- ============================================================

\echo ''
\echo '--- 6.5 SENKRON / ASENKRON REPLIKASYON ---'

CREATE TABLE IF NOT EXISTS replication_modes (
    mod           VARCHAR(20),
    veri_kaybi    VARCHAR(30),
    performans    VARCHAR(20),
    kullanim      TEXT
);

TRUNCATE replication_modes;

INSERT INTO replication_modes VALUES
    ('Asenkron', 'Az miktarda mumkun', 'Yuksek',  'Cogu DR senaryosu, cografi uzak replica'),
    ('Senkron',  'Sifir veri kaybi',   'Daha dusuk','Finansal/kritik sistemler (synchronous_commit)');

SELECT mod AS replikasyon_modu, veri_kaybi, performans, kullanim
FROM replication_modes;

\echo ''
\echo 'Senkron mod icin PRIMARY postgresql.conf:'
\echo "   synchronous_standby_names = 'standby1'"
\echo "   synchronous_commit = on"

\echo ''
\echo 'Replikasyon / mirroring rehberi tamamlandi.'
