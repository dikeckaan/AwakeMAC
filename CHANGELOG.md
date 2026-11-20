# Changelog

## 1.2.0

**Güvenlik**
- Kapak kapanınca ekranı anında kilitle (varsayılan açık) — Mac uyumadığı için aksi halde kilitlenmezdi.
- "Kapak kapalı mod yalnızca şarjdayken" seçeneği; şarj kablosu çıkınca anında kapanır.
- Isı uyarısı (Sıcak seviyesinde bildirim; Kritik'te kapak modu kapanır).
- Süre bitmeden 5 dk önce "+30 dk" düğmeli bildirim.

**Akıllı tetikleyiciler**
- Seçilen uygulamalar açıkken, belirli komutlar (ffmpeg, rsync…) çalışırken, indirme/yükleme sürerken, şarj adaptörü veya harici ekran bağlıyken ve her gün belirli saatlerde otomatik uyanık kal. Elle seçim her zaman önceliklidir.

**Kullanım kolaylığı**
- Global kısayol ⌥⌘A, menü ikonuna sağ tıkla hızlı menü, menü çubuğunda kalan süre.
- Özel süreler (15 dk, 3/4/8 sa), "belirli saate kadar", "+30 dk uzat".
- "Ekranı da açık tut" seçeneği.
- `awakemac://` URL şeması ve Kısayollar (Shortcuts) eylemleri.
- Sekmeli Ayarlar penceresi ve ilk açılış ekranı.

**Dağıtım ve kalite**
- Xcode projesi; Developer ID imzası + Apple noter onayı (`scripts/release.sh`).
- GitHub Releases üzerinden günlük güncelleme denetimi.
- Birim testleri ve GitHub Actions CI; Homebrew cask.
- Tamamen olay güdümlü: boştayken zamanlayıcı yok, %0 CPU.

## 1.1.1
- Ayarlar paneli aşağı doğru düzgün açılıyor.

## 1.1.0
- Yeni ad: Awake Mac; 15 dil; "Seçimi hatırla"; menü çubuğundan açılan panel.

## 1.0.0
- İlk sürüm (LidAwake).
