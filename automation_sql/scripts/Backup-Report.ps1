# ============================================================
# Backup-Report.ps1
# PowerShell ile yedekleme raporu oluşturma ve uyarı kontrolü
#
# Ödev maddesi: "PowerShell veya T-SQL Scripting ile yedekleme
# raporları oluşturma" + "Otomatik Yedekleme Uyarıları"
#
# Bu script (Windows / SQL Server Agent ortamı için):
#   1) Veritabanından günlük yedekleme raporunu çeker
#   2) Çözülmemiş kritik uyarı varsa yöneticiye e-posta gönderir
#
# Çalıştırma:  powershell -File Backup-Report.ps1
# (macOS/Linux'ta PowerShell Core ile de çalışır: pwsh Backup-Report.ps1)
#
# NOT: psql PATH'te olmalı. backup_runner.sh bash karşılığıdır.
# ============================================================

param(
    [string]$DbName   = "backup_demo",
    [string]$DbUser   = "postgres",
    [string]$MailTo   = "dba@sirket.com",
    [string]$SmtpHost = "smtp.sirket.com"
)

Write-Host "=========================================="
Write-Host " YEDEKLEME GUNLUK RAPORU - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
Write-Host "=========================================="

# --- 1) Günlük yedekleme durum raporunu çek ---
$reportQuery = @"
SELECT started_at::DATE AS tarih,
       COUNT(*) AS toplam,
       COUNT(*) FILTER (WHERE status='SUCCESS') AS basarili,
       COUNT(*) FILTER (WHERE status='FAILED')  AS basarisiz
FROM backup_history
WHERE started_at >= CURRENT_DATE - 1
GROUP BY started_at::DATE
ORDER BY tarih DESC;
"@

$report = psql -U $DbUser -d $DbName -c $reportQuery
Write-Host $report

# --- 2) Çözülmemiş KRİTİK uyarı sayısını al ---
$alertQuery = "SELECT COUNT(*) FROM backup_alert WHERE NOT is_resolved AND severity='CRITICAL';"
$criticalCount = (psql -U $DbUser -d $DbName -tAc $alertQuery).Trim()

Write-Host ""
Write-Host "Cozulmemis KRITIK uyari sayisi: $criticalCount"

# --- 3) Kritik uyarı varsa yöneticiye e-posta gönder ---
if ([int]$criticalCount -gt 0) {

    $alertDetail = psql -U $DbUser -d $DbName -c `
        "SELECT created_at, message FROM backup_alert WHERE NOT is_resolved AND severity='CRITICAL' ORDER BY created_at DESC;"

    $subject = "[KRITIK] Yedekleme Hatasi - $criticalCount uyari"
    $body    = "Asagidaki yedekleme islemleri basarisiz oldu:`n`n$alertDetail"

    Write-Host ""
    Write-Host ">>> KRITIK uyari! Yoneticiye e-posta gonderiliyor: $MailTo"

    # Gerçek ortamda e-posta gönderimi:
    # Send-MailMessage -To $MailTo -From "backup@sirket.com" `
    #     -Subject $subject -Body $body -SmtpServer $SmtpHost

    # Simülasyon (gerçek SMTP yerine ekrana/dosyaya yaz):
    Write-Host "----- E-POSTA (simulasyon) -----"
    Write-Host "Kime    : $MailTo"
    Write-Host "Konu    : $subject"
    Write-Host "Icerik  :`n$body"
    Write-Host "--------------------------------"
}
else {
    Write-Host ">>> Kritik uyari yok. Tum yedekler saglikli."
}

Write-Host ""
Write-Host "Rapor tamamlandi."
