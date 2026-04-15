"""
Veri Aktarım Betiği: hotel_bookings.csv → PostgreSQL ham_rezervasyonlar
=======================================================================
Kullanım:
    python import_csv.py

Gereksinim: pip install psycopg2-binary
"""

import csv
import psycopg2
import os

DB_CONFIG = {
    "host":     "localhost",
    "port":     5432,
    "dbname":   "hotel_db",
    "user":     "postgres",
    "password": "postgres"        # Süper kullanıcı ile import yapılır
}

CSV_PATH = os.path.join(os.path.dirname(__file__), "..", "hotel_bookings.csv")

INSERT_SQL = """
    INSERT INTO ham_rezervasyonlar (
        hotel, is_canceled, lead_time,
        arrival_date_year, arrival_date_month, arrival_date_week_number, arrival_date_day_of_month,
        stays_in_weekend_nights, stays_in_week_nights,
        adults, children, babies, meal, country,
        market_segment, distribution_channel,
        is_repeated_guest, previous_cancellations, previous_bookings_not_canceled,
        reserved_room_type, assigned_room_type,
        booking_changes, deposit_type, agent, company,
        days_in_waiting_list, customer_type, adr,
        required_car_parking_spaces, total_of_special_requests,
        reservation_status, reservation_status_date
    ) VALUES (
        %s, %s, %s,
        %s, %s, %s, %s,
        %s, %s,
        %s, %s, %s, %s, %s,
        %s, %s,
        %s, %s, %s,
        %s, %s,
        %s, %s, %s, %s,
        %s, %s, %s,
        %s, %s,
        %s, %s
    )
"""

def temizle(deger):
    """NULL ve boş string dönüşümü."""
    if deger in ("NULL", "NA", ""):
        return None
    return deger

def main():
    print("CSV → PostgreSQL aktarımı başlatılıyor...")
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()

    batch = []
    BATCH_SIZE = 1000
    toplam = 0
    hatalar = 0

    with open(CSV_PATH, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for satir in reader:
            try:
                kayit = (
                    satir["hotel"],
                    int(satir["is_canceled"]),
                    int(satir["lead_time"]),
                    int(satir["arrival_date_year"]),
                    satir["arrival_date_month"],
                    int(satir["arrival_date_week_number"]),
                    int(satir["arrival_date_day_of_month"]),
                    int(satir["stays_in_weekend_nights"]),
                    int(satir["stays_in_week_nights"]),
                    int(satir["adults"]),
                    temizle(satir["children"]),
                    int(satir["babies"]),
                    satir["meal"],
                    satir["country"],
                    satir["market_segment"],
                    satir["distribution_channel"],
                    int(satir["is_repeated_guest"]),
                    int(satir["previous_cancellations"]),
                    int(satir["previous_bookings_not_canceled"]),
                    satir["reserved_room_type"],
                    satir["assigned_room_type"],
                    int(satir["booking_changes"]),
                    satir["deposit_type"],
                    temizle(satir["agent"]),
                    temizle(satir["company"]),
                    int(satir["days_in_waiting_list"]),
                    satir["customer_type"],
                    float(satir["adr"]),
                    int(satir["required_car_parking_spaces"]),
                    int(satir["total_of_special_requests"]),
                    satir["reservation_status"],
                    satir["reservation_status_date"],
                )
                batch.append(kayit)
                toplam += 1

                if len(batch) >= BATCH_SIZE:
                    try:
                        cur.executemany(INSERT_SQL, batch)
                        conn.commit()
                        print(f"  {toplam} kayit aktarıldı...")
                    except Exception as batch_err:
                        conn.rollback()
                        print(f"  [UYARI] Batch atlandı ({batch_err})")
                    batch.clear()

            except Exception as e:
                hatalar += 1
                if hatalar <= 5:
                    print(f"  [UYARI] Satir atlandı ({e})")

    # Kalan kayıtları yaz
    if batch:
        try:
            cur.executemany(INSERT_SQL, batch)
            conn.commit()
        except Exception as e:
            conn.rollback()
            print(f"  [UYARI] Son batch atlandı ({e})")

    cur.close()
    conn.close()
    print(f"\nTamamlandı! Toplam {toplam} kayit aktarıldı, {hatalar} hata.")

if __name__ == "__main__":
    main()
