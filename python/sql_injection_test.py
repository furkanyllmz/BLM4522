"""
FAZ 1 - ADIM 4: SQL Injection Güvenlik Testi
============================================
Bu betik iki senaryo gösterir:
  1. SAVUNMASIZ sorgu  → SQL Injection ile tüm veriler sızıyor
  2. GÜVENLİ sorgu    → Parametrik sorgu ile açık kapatılıyor

Gereksinim: pip install psycopg2-binary
"""

import psycopg2
import psycopg2.extras

# ── Bağlantı Ayarları ─────────────────────────────────────────────────────────
DB_CONFIG = {
    "host":     "localhost",
    "port":     5432,
    "dbname":   "hotel_db",
    "user":     "city_reception",   # Kısıtlı rol (sadece City Hotel görmeli)
    "password": "CityHotel2024!"
}

SEPARATOR = "=" * 70


def baglanti_kur(config: dict):
    """Veritabanı bağlantısı oluşturur."""
    try:
        conn = psycopg2.connect(**config)
        conn.autocommit = True
        return conn
    except psycopg2.OperationalError as e:
        print(f"[HATA] Veritabanına bağlanılamadı: {e}")
        raise


# ─────────────────────────────────────────────────────────────────────────────
# SENARYO 1: SAVUNMASIZ KOD (SQL Injection açığı var)
# ─────────────────────────────────────────────────────────────────────────────
def musteri_sorgula_SAVUNMASIZ(conn, musteri_ulke: str):
    """

    Giriş değerini doğrudan SQL string'e yapıştırır.
    Saldırgan değeri:  ' OR '1'='1' --
    Bu değer şu sorguyu oluşturur:
        SELECT ... WHERE country = '' OR '1'='1' --'
    '1'='1' her zaman TRUE olduğundan RLS politikası devre dışı kalır ve
    city_reception kullanıcısı Resort Hotel verilerini de görür!
    """
    print(f"\n{'[!] SAVUNMASIZ SORGU':^{len(SEPARATOR)}}")
    print(SEPARATOR)
    print(f"Girdi: '{musteri_ulke}'")

    # !! String birleştirme → SQL Injection açığı !!
    sorgu = f"""
        SELECT r.rezervasyon_id, r.hotel, m.ulke, r.adr, r.reservation_status
        FROM   rezervasyonlar r
        JOIN   musteriler m ON m.musteri_id = r.musteri_id
        WHERE  m.ulke = '{musteri_ulke}'
        LIMIT  20
    """
    print(f"\nOluşan SQL:\n{sorgu}")

    try:
        with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
            cur.execute(sorgu)
            satirlar = cur.fetchall()

        if not satirlar:
            print("Sonuç bulunamadı.")
            return

        print(f"\n{'ID':<6} {'Hotel':<15} {'Ulke':<6} {'ADR':>8}  {'Durum'}")
        print("-" * 50)
        for satir in satirlar:
            print(
                f"{satir['rezervasyon_id']:<6} "
                f"{satir['hotel']:<15} "
                f"{satir['ulke']:<6} "
                f"{satir['adr']:>8.2f}  "
                f"{satir['reservation_status']}"
            )

        otel_sayaci = {}
        for satir in satirlar:
            otel_sayaci[satir['hotel']] = otel_sayaci.get(satir['hotel'], 0) + 1

        print(f"\n{'UYARI':!^50}")
        print(f"city_reception kullanicisi {len(satirlar)} kayit gordu!")
        for otel, sayi in otel_sayaci.items():
            print(f"  → {otel}: {sayi} kayit")
        if len(otel_sayaci) > 1:
            print("  !! RESORT HOTEL VERİLERİ SIZDI — RLS AŞILDI !!")

    except psycopg2.Error as e:
        print(f"[DB HATA] {e}")


# ─────────────────────────────────────────────────────────────────────────────
# SENARYO 2: GÜVENLİ KOD (Parametrik Sorgu)
# ─────────────────────────────────────────────────────────────────────────────
def musteri_sorgula_GUVENLI(conn, musteri_ulke: str):
    """
    Parametrik sorgu kullanır (%s placeholder).
    psycopg2 girdiyi otomatik kaçış karakterleriyle temizler.
    Aynı saldırı girdisi artık literal string olarak aranır → 0 sonuç döner.
    """
    print(f"\n{'[✓] GÜVENLİ SORGU (PARAMETRİK)':^{len(SEPARATOR)}}")
    print(SEPARATOR)
    print(f"Girdi: '{musteri_ulke}'")

    # Parametre ayrı geçiliyor — psycopg2 otomatik sanitize eder
    sorgu = """
        SELECT r.rezervasyon_id, r.hotel, m.ulke, r.adr, r.reservation_status
        FROM   rezervasyonlar r
        JOIN   musteriler m ON m.musteri_id = r.musteri_id
        WHERE  m.ulke = %s
        LIMIT  20
    """
    print(f"\nKullanılan SQL şablonu:{sorgu}")
    print(f"Parametre: ('{musteri_ulke}',)")

    try:
        with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
            cur.execute(sorgu, (musteri_ulke,))   # Parametre tuple ile geçiliyor
            satirlar = cur.fetchall()

        if not satirlar:
            print("\nSonuç: 0 kayit bulundu.")
            print("AÇIKLAMA: Saldırı girdisi literal string olarak arandı,")
            print("          SQL kodu olarak yorumlanmadı. Sistem güvende.")
            return

        print(f"\n{'ID':<6} {'Hotel':<15} {'Ulke':<6} {'ADR':>8}  {'Durum'}")
        print("-" * 50)
        for satir in satirlar:
            print(
                f"{satir['rezervasyon_id']:<6} "
                f"{satir['hotel']:<15} "
                f"{satir['ulke']:<6} "
                f"{satir['adr']:>8.2f}  "
                f"{satir['reservation_status']}"
            )
        print(f"\n{len(satirlar)} meşru kayit döndürüldü (RLS aktif).")

    except psycopg2.Error as e:
        print(f"[DB HATA] {e}")


# ─────────────────────────────────────────────────────────────────────────────
# SENARYO 3: Normal meşru kullanım (karşılaştırma için)
# ─────────────────────────────────────────────────────────────────────────────
def normal_kullanim_goster(conn):
    """RLS'nin doğru çalıştığını gösterir: city_reception sadece City Hotel görür."""
    print(f"\n{'[i] NORMAL KULLANIM — RLS TESTİ':^{len(SEPARATOR)}}")
    print(SEPARATOR)
    sorgu = """
        SELECT hotel, COUNT(*) AS kayit_sayisi
        FROM   rezervasyonlar
        GROUP  BY hotel
        ORDER  BY hotel
    """
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
            cur.execute(sorgu)
            satirlar = cur.fetchall()
        print("city_reception rolüyle GROUP BY hotel sonucu:")
        for satir in satirlar:
            print(f"  {satir['hotel']}: {satir['kayit_sayisi']} kayit")
        if len(satirlar) == 1 and satirlar[0]['hotel'] == 'City Hotel':
            print("\n[OK] RLS çalışıyor: sadece City Hotel görünüyor.")
    except psycopg2.Error as e:
        print(f"[DB HATA] {e}")


# ─────────────────────────────────────────────────────────────────────────────
# ANA AKIŞ
# ─────────────────────────────────────────────────────────────────────────────
def main():
    print(SEPARATOR)
    print("  OTEL RESERVASYONİ SİSTEMİ — SQL GÜVENLİK TESTİ")
    print("  Kullanıcı: city_reception (sadece City Hotel görmelidir)")
    print(SEPARATOR)

    conn = baglanti_kur(DB_CONFIG)

    # 1. Normal meşru kullanım — RLS doğrulaması
    normal_kullanim_goster(conn)

    # 2. SQL Injection saldırısı (savunmasız kod ile)
    print(f"\n{SEPARATOR}")
    print("  SALDIRI SİMÜLASYONU")
    print(SEPARATOR)
    saldiri_girdisi = "' OR '1'='1' --"
    musteri_sorgula_SAVUNMASIZ(conn, saldiri_girdisi)

    # 3. Aynı saldırı girdisi — ama güvenli kod ile
    print(f"\n{SEPARATOR}")
    print("  SAVUNMA: PARAMETRİK SORGU")
    print(SEPARATOR)
    musteri_sorgula_GUVENLI(conn, saldiri_girdisi)

    # 4. Meşru parametrik sorgu (gerçek ülke kodu)
    print(f"\n{SEPARATOR}")
    print("  MEŞRU PARAMETRİK SORGU (PRT = Portekiz)")
    print(SEPARATOR)
    musteri_sorgula_GUVENLI(conn, "PRT")

    conn.close()
    print(f"\n{SEPARATOR}")
    print("  TEST TAMAMLANDI")
    print(SEPARATOR)


if __name__ == "__main__":
    main()
