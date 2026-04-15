# Skenario Lengkap — Warung Gemoy

Dokumen ini menjelaskan **seluruh skenario yang bisa terjadi** di aplikasi, dari sudut pandang pelanggan maupun admin, secara berurutan dan lengkap termasuk kondisi gagal/edge case.

---

## BAGIAN 1 — APP STARTUP & AUTENTIKASI

---

### S-001 · Buka App Pertama Kali (Belum Login)

1. App dibuka → SplashScreen tampil sebentar
2. App cek session Supabase → tidak ada session aktif
3. App redirect ke **LoginScreen**
4. Pelanggan melihat form nomor HP + password dan tombol "Daftar"

---

### S-002 · Register Pelanggan Baru

1. Di LoginScreen, pelanggan tap "Daftar"
2. RegisterScreen tampil → isi nama lengkap, nomor HP, password
3. Tap "Daftar Sekarang"
4. App membuat akun Supabase Auth dengan email fake format `{nomorHP}@gemoykitchen.com`
5. App insert data ke tabel `users` (nama, phone, created_at)
6. FCM token perangkat disimpan ke `users.fcm_token`
7. Pelanggan langsung masuk ke **HomeScreen** (MainScreen tab Home)

**Gagal — Nomor HP sudah terdaftar:**
- Supabase Auth menolak → muncul pesan ramah "Nomor HP ini sudah terdaftar. Coba masuk langsung."

**Gagal — Koneksi internet mati:**
- Muncul pesan "Tidak dapat terhubung. Periksa koneksi internet kamu."

---

### S-003 · Login Pelanggan

1. Pelanggan isi nomor HP + password → tap "Masuk"
2. App auth ke Supabase dengan email `{nomorHP}@gemoykitchen.com`
3. Session disimpan lokal (persistent)
4. App cek apakah ID ini ada di tabel `admins` → tidak ada → lanjut sebagai pelanggan
5. FCM token diperbarui di `users.fcm_token`
6. Masuk ke **HomeScreen**

**Gagal — Password salah / nomor tidak terdaftar:**
- Muncul pesan "Nomor HP atau password salah."

**Gagal — Akun dinonaktifkan (`users.is_active = false`):**
- Login berhasil di Auth, tapi app cek `is_active` → redirect balik ke LoginScreen dengan pesan "Akun kamu dinonaktifkan. Hubungi admin."

---

### S-004 · Auto-Login (Kembali Buka App)

1. Pelanggan pernah login sebelumnya → buka app lagi
2. SplashScreen cek session Supabase → session masih valid
3. App cek tabel `admins` → bukan admin → langsung ke **HomeScreen**
4. Tidak perlu isi ulang nomor HP / password

**Session expired:**
- Supabase refresh token otomatis di background
- Kalau refresh gagal (jarang) → redirect ke LoginScreen

---

### S-005 · Login Admin

1. Di HomeScreen, tap logo app 7x → tahan 5 detik
2. **AdminLoginScreen** tampil (tersembunyi dari navigasi biasa)
3. Admin isi email + password → tap "Masuk"
4. App auth ke Supabase → cek tabel `admins` → ada → masuk sebagai admin
5. FCM token disimpan ke `admins.fcm_token`
6. Masuk ke **AdminDashboardScreen**

**Login dengan akun pelanggan biasa di form admin:**
- Auth berhasil tapi tidak ada di tabel `admins` → muncul pesan "Akun ini bukan admin."

---

### S-006 · Logout

**Pelanggan:**
1. Tab Akun → tap "Keluar" → konfirmasi
2. `users.fcm_token` dihapus (set null)
3. Session Supabase dihapus
4. Redirect ke **LoginScreen**

**Admin:**
1. AdminDashboard → icon profil → "Keluar"
2. `admins.fcm_token` dihapus
3. Session dihapus → redirect ke **LoginScreen** (bukan AdminLoginScreen)

---

## BAGIAN 2 — HALAMAN UTAMA & MENU

---

### S-007 · Pelanggan Buka HomeScreen — Toko Buka Normal

1. HomeScreen load → app fetch `store_settings`
2. Cek `is_open`, jam buka/tutup, `manually_opened`, `manually_closed_date`
3. Toko dinyatakan **buka** → tombol cart aktif, menu bisa dipesan
4. App fetch menu terjadwal hari ini dari `menu_schedules` join `menus`
5. Menu ditampilkan per kategori (urut by `sort_order`)
6. Tiap menu tampil: nama, harga, deskripsi, foto, sisa stok

---

### S-008 · Pelanggan Buka HomeScreen — Toko Tutup

**Kondisi tutup bisa terjadi karena:**
- Jam sekarang di luar jam buka/tutup di `store_settings`
- Admin toggle tutup manual (`is_open = false`)
- Admin tutup manual hari ini (`manually_closed_date = today`)

**Yang terjadi:**
1. HomeScreen tetap tampil menu (browse aja)
2. Tombol "+" di tiap menu disabled
3. Tombol cart tetap ada tapi checkout akan ditolak
4. Muncul banner/info "Toko sedang tutup"

**Toko tutup manual → buka esok hari:**
- Cron sync tiap menit cek apakah `manually_closed_date != today` → kalau hari baru, reset `is_open = true` di DB

---

### S-009 · Tidak Ada Menu Terjadwal Hari Ini

1. Admin belum menjadwalkan menu untuk hari ini
2. HomeScreen tampil kosong / pesan "Belum ada menu untuk hari ini"
3. Pelanggan tidak bisa memesan

---

### S-010 · Menu Stok Habis

1. Menu dijadwalkan dengan `max_qty = 10`, `used_qty = 10`
2. Di HomeScreen, menu tampil dengan label "Habis" / tombol "+" disabled
3. Pelanggan tidak bisa menambahkan ke cart

---

### S-011 · Pelanggan Terima Broadcast Baru

1. Admin kirim broadcast → data insert ke `broadcast_messages`
2. Supabase Realtime trigger di HomeScreen pelanggan
3. Muncul snackbar notifikasi di HomeScreen
4. Pelanggan tap notifikasi → buka **BroadcastScreen** untuk lihat riwayat pesan

---

## BAGIAN 3 — CART

---

### S-012 · Tambah Menu ke Cart

1. Pelanggan tap "+" pada menu → menu masuk `CartProvider` (state lokal)
2. Badge cart di AppBar update (jumlah item)
3. Bisa tap "+" lagi untuk tambah qty, atau "−" untuk kurangi

**Qty melebihi sisa stok:**
- App hitung: sisa = `max_qty − used_qty`
- Tombol "+" disabled kalau qty di cart sudah = sisa stok
- Pelanggan tidak bisa pesan lebih dari yang tersedia

---

### S-013 · Buka CartScreen

1. Tap ikon cart → **CartScreen** tampil
2. Daftar item + qty + subtotal masing-masing
3. Total keseluruhan di bawah
4. Tombol "Checkout"

**Cart kosong:**
- Tampil ilustrasi + teks "Belum ada item di keranjang"
- Tombol Checkout tidak ada

---

### S-014 · Stok Berubah Saat CartScreen Terbuka (Realtime)

1. Pelanggan buka CartScreen, ada item A qty 3 di cart
2. Sementara itu, pelanggan lain order item A sebanyak 2 → stok tersisa 1
3. Supabase Realtime trigger update di CartScreen
4. CartScreen detect stok tidak cukup → tampil dialog:
   > "Stok [nama menu] tersisa 1. Qty di cart kamu disesuaikan menjadi 1. Lanjut checkout?"
5. Jika pelanggan setuju → qty diupdate, lanjut
6. Jika tidak → tetap di cart dengan qty yang sudah disesuaikan

---

### S-015 · Item di Cart Stoknya Habis Total Saat Realtime

1. Stok item di cart jadi 0 akibat pelanggan lain
2. Dialog muncul: item dihapus dari cart karena stok habis

---

## BAGIAN 4 — CHECKOUT

---

### S-016 · Checkout — Metode Pengiriman (Delivery)

1. Tap "Checkout" → **CheckoutScreen** tampil
2. Pilih "Diantar ke Alamat"
3. Pilih lokasi: bisa dari **saved location** atau tap "Pilih di Peta"
4. **LocationPickerScreen**: peta Google Maps muncul, GPS aktif → pin di lokasi sekarang
5. Geser/tap peta untuk pindah pin → alamat teks update otomatis (reverse geocoding)
6. Tap "Gunakan Lokasi Ini"
7. Kembali ke CheckoutScreen → alamat terisi, **ongkir dihitung otomatis**:
   - Jarak diukur dari koordinat toko (`store_lat`, `store_lng`) ke lokasi pelanggan
   - Kalau ≤ `free_km` → ongkir Rp 0 (Gratis)
   - Kalau > `free_km` → ongkir = `ceil(jarak − free_km) × delivery_fee_per_km`
8. Isi catatan (opsional)
9. Tap "Pesan Sekarang" → proses checkout dimulai

**Lokasi di luar jangkauan (`jarak > max_delivery_km`):**
- Muncul pesan: "Maaf, lokasi kamu terlalu jauh. Jangkauan pengiriman maksimal X km."
- Pelanggan tidak bisa lanjut checkout delivery, harus pilih pickup atau ganti lokasi

---

### S-017 · Checkout — Ambil Sendiri (Pickup)

1. Di CheckoutScreen pilih "Ambil Sendiri di Toko"
2. Tidak ada kolom alamat, tidak ada ongkir
3. Isi catatan (opsional) → tap "Pesan Sekarang"
4. Di semua screen status selanjutnya, label "Sedang Diantar" diganti "Siap Diambil"

---

### S-018 · Proses Internal Checkout (Setelah Tap "Pesan Sekarang")

Urutan insert yang terjadi di DB:

1. Insert ke tabel `orders` → dapat `order_id` baru
2. Insert tiap item ke `order_items` (menu_id, qty, price)
3. Untuk tiap item: panggil RPC `increment_used_qty` secara atomic
   - Kalau stok cukup → `used_qty` bertambah, lanjut
   - Kalau stok tidak cukup (kondisi race) → RPC throw exception
4. Insert ke tabel `payments` (method, expired_at dihitung 30 menit dari sekarang)
5. Kirim notifikasi FCM ke admin: "Pesanan Baru"
6. Navigasi ke **PaymentScreen**

**Kalau RPC gagal (stok habis saat checkout):**
- Semua `increment_used_qty` yang sudah berhasil di-rollback satu per satu (decrement)
- Order dan order_items yang terlanjur diinsert dihapus
- Muncul pesan: "Stok [nama menu] tidak cukup. Silakan perbarui keranjang."

---

### S-019 · Toko Penuh (max_orders_per_day Tercapai)

1. Saat checkout, app hitung jumlah order hari ini
2. Kalau sudah mencapai `max_orders_per_day` → muncul pesan:
   > "Maaf, pesanan hari ini sudah penuh. Coba lagi besok."
3. Checkout dibatalkan, cart tetap tersimpan

---

## BAGIAN 5 — PEMBAYARAN

---

### S-020 · PaymentScreen — Tampilan Awal

1. Pelanggan masuk PaymentScreen → lihat:
   - Countdown timer 30 menit (auto-cancel kalau tidak bayar)
   - Total yang harus dibayar
   - Pilihan metode: Transfer Bank / QRIS / Bayar di Tempat (COD)
2. Info rekening / QRIS diambil dari `store_settings`

---

### S-021 · Pembayaran Transfer Bank

1. Pelanggan pilih "Transfer Bank"
2. Tampil nama bank, nomor rekening, nama pemilik, jumlah yang harus ditransfer
3. Tombol "Salin Nomor Rekening" → copy ke clipboard
4. Pelanggan transfer secara manual di app bank masing-masing
5. Kembali ke app → tap "Upload Bukti Transfer"
6. Pilih foto dari galeri / kamera
7. Tap "Kirim Bukti Pembayaran"
8. Foto terupload ke Supabase Storage bucket `payment-proofs`
9. `payments.proof_url` diupdate, `payments.status` → `waiting_verification` (tetap, bukan berubah)
10. `orders.status` → `waiting_verification`
11. Trigger DB otomatis insert ke `order_status_history`
12. Notifikasi FCM ke admin: "Bukti Bayar Masuk"
13. Pelanggan diarahkan ke **OrderStatusScreen**

---

### S-022 · Pembayaran QRIS

1. Pelanggan pilih "QRIS"
2. Gambar QRIS dari `store_settings.qris_image_url` tampil
3. Pelanggan scan QRIS, bayar via e-wallet / mobile banking
4. Kembali ke app → upload bukti screenshot
5. Proses selanjutnya sama seperti S-021 (transfer bank)

---

### S-023 · Pembayaran COD (Bayar di Tempat)

1. Pelanggan pilih "Bayar di Tempat (COD)"
2. Tap "Konfirmasi Pesanan COD"
3. `orders.status` tetap `pending` (menunggu konfirmasi admin)
4. Tidak ada upload bukti bayar
5. Notifikasi FCM ke admin: "Pesanan Baru" (COD)
6. Pelanggan langsung ke **OrderStatusScreen**

**Di MyOrdersScreen tab "Pembayaran":**
- Order COD pending bisa di-tap → masuk ke OrderStatusScreen (bukan PaymentScreen)

---

### S-024 · Timer Auto-Cancel (Tidak Bayar 30 Menit)

1. Pelanggan membuat order tapi tidak upload bukti dalam 30 menit
2. Countdown timer di PaymentScreen mencapai 0
3. App otomatis:
   - Update `orders.status` → `cancelled`
   - Trigger DB insert ke `order_status_history`
   - Decrement `used_qty` untuk tiap item (stok kembali)
4. PaymentScreen: form upload disembunyikan, muncul tombol "Kembali ke Beranda"
5. Di MyOrdersScreen, order pindah ke tab "History" dengan status "Dibatalkan"

**Kalau app ditutup (killed) sebelum timer habis:**
- Cron job di Supabase berjalan tiap menit, auto-cancel pesanan pending > 30 menit
- Saat app dibuka lagi, status sudah `cancelled`

---

### S-025 · Kembali ke PaymentScreen Order yang Belum Dibayar

1. Pelanggan keluar dari PaymentScreen, lalu tap order di MyOrdersScreen
2. App cek `payments.expired_at` → belum expired → kembali ke **PaymentScreen** dengan sisa waktu yang benar
3. Countdown timer melanjutkan dari sisa waktu, bukan reset dari 30 menit

---

## BAGIAN 6 — STATUS PESANAN (SISI PELANGGAN)

---

### S-026 · OrderStatusScreen — Tampilan

1. Pelanggan buka OrderStatusScreen (dari notifikasi / tap order)
2. Tampil:
   - Icon + judul status saat ini (besar, warna sesuai status)
   - Deskripsi singkat status
   - Timeline riwayat status (dari terbaru ke terlama, dengan timestamp)
   - Info pesanan: order ID, metode pengiriman, daftar item, total
3. Realtime: kalau admin update status, screen ini berubah otomatis

---

### S-027 · Alur Status Normal (Lengkap)

```
pending
  → waiting_verification  (setelah upload bukti bayar)
    → processing           (admin verifikasi pembayaran)
      → delivered          (admin tandai sedang dikirim/siap diambil)
        → completed        (admin tandai selesai)
          → [customer konfirmasi / auto-konfirmasi 24 jam]
            → [rating opsional]
```

Di setiap transisi:
- `order_status_history` otomatis ter-insert via DB trigger
- Pelanggan dapat notifikasi FCM
- OrderStatusScreen + MyOrdersScreen update realtime

---

### S-028 · MyOrdersScreen — Tab-Tab

| Tab | Isi | Badge |
|-----|-----|-------|
| Pembayaran | status `pending` | jumlah order |
| Diproses | `waiting_verification`, `processing` | jumlah order |
| Siap | `delivered` | jumlah order |
| Diterima | `completed` + belum `customer_confirmed` | jumlah order |
| History | `cancelled` + `completed` sudah `customer_confirmed` | tidak ada |

Order berpindah tab otomatis via Realtime saat status berubah.

---

### S-029 · Pembatalan oleh Pelanggan

**Kapan bisa dibatalkan:**
- Hanya saat status masih `pending` (belum upload bukti / COD belum dikonfirmasi admin)

**Langkah:**
1. Tab "Pembayaran" → tap order → tap "Batalkan Pesanan"
2. Muncul dialog konfirmasi
3. Jika setuju:
   - `orders.status` → `cancelled`
   - `used_qty` tiap item dikembalikan (decrement)
   - Notifikasi FCM ke admin: "Pesanan Dibatalkan"
   - Order pindah ke tab "History"

**Setelah upload bukti (status `waiting_verification`):**
- Pelanggan tidak bisa batalkan sendiri
- Harus menghubungi admin via Chat

---

## BAGIAN 7 — SISI ADMIN: KELOLA PESANAN

---

### S-030 · Admin Buka AdminOrdersScreen

1. Admin tap menu "Pesanan" di dashboard
2. **AdminOrdersScreen** tampil dengan 6 tab:

| Tab | Isi |
|-----|-----|
| Perlu Aksi | `pending` + `waiting_verification` |
| Diproses | `processing` |
| Siap | `delivered` |
| Konfirmasi | `completed` belum `customer_confirmed` |
| Selesai | `completed` sudah `customer_confirmed` |
| Dibatalkan | `cancelled` |

3. Tiap tab tampil badge jumlah order
4. Search bar untuk filter by nama / nomor HP / order ID

---

### S-031 · Admin Verifikasi Pembayaran Transfer/QRIS

1. Tab "Perlu Aksi" → tap order dengan status `waiting_verification`
2. Detail order tampil: foto bukti bayar, info pembeli, daftar item, total
3. Admin cek bukti bayar → tap "✅ Verifikasi & Mulai Masak"
4. Yang terjadi:
   - `orders.status` → `processing`
   - `payments.status` → `verified`
   - `payments.verified_at` → timestamp sekarang
   - Notifikasi ke pelanggan: "Pembayaran Dikonfirmasi" + "Pesanan Sedang Dimasak"
   - Order pindah ke tab "Diproses"

---

### S-032 · Admin Tolak Pembayaran

1. Tap order `waiting_verification` → tap "❌ Tolak Pembayaran"
2. Yang terjadi:
   - `orders.status` → `cancelled`
   - Stok tiap item dikembalikan (decrement)
   - Notifikasi ke pelanggan: "Pembayaran Ditolak, silakan upload ulang"
   - Order pindah ke tab "Dibatalkan"

---

### S-033 · Admin Konfirmasi Order COD

1. Tab "Perlu Aksi" → tap order COD (status `pending`)
2. Tap "✅ Konfirmasi Pesanan Cash/Tunai"
3. Yang terjadi:
   - `orders.status` → `processing`
   - Notifikasi ke pelanggan: "Pesanan Dikonfirmasi"

**Admin tolak order COD:**
- Tap "❌ Tolak Pesanan" → status `cancelled`, stok dikembalikan, notif ke pelanggan

---

### S-034 · Admin Update Status: Processing → Delivered

1. Tab "Diproses" → tap order → tap "🛵 Tandai Sedang Dikirim" (delivery) atau "✅ Tandai Siap Diambil" (pickup)
2. `orders.status` → `delivered`
3. Notif ke pelanggan:
   - Delivery: "Pesanan sedang dalam perjalanan"
   - Pickup: "Pesanan siap diambil di toko"

---

### S-035 · Admin Update Status: Delivered → Completed

1. Tab "Siap" → tap order → tap "✅ Tandai Selesai"
2. `orders.status` → `completed`
3. Notif ke pelanggan: "Pesanan Selesai"
4. Order pindah ke tab "Konfirmasi" (menunggu customer konfirmasi)

---

### S-036 · Admin Batalkan Order dari Processing atau Delivered

1. Tab "Diproses" atau "Siap" → tap order → tap "❌ Batalkan Pesanan"
2. Muncul dialog konfirmasi
3. Jika dikonfirmasi:
   - Ambil `orders.created_at` untuk tahu tanggal berapa stok harus dikembalikan
   - Decrement `used_qty` tiap item untuk tanggal tersebut
   - `orders.status` → `cancelled`
   - Notif ke pelanggan: "Pesanan Dibatalkan"

---

### S-037 · Admin Hubungi Pelanggan via WhatsApp

1. Di detail order → tap tombol WA
2. Nomor HP pelanggan di-normalize ke format `628xxxxxxx`
3. Buka WhatsApp dengan pesan template yang berisi nomor order

---

## BAGIAN 8 — KONFIRMASI PENERIMAAN & RATING

---

### S-038 · Pelanggan Konfirmasi Terima Pesanan

1. Order status `completed`, tab "Diterima" di MyOrdersScreen
2. Pelanggan tap order → tap "Konfirmasi Pesanan Diterima"
3. Muncul dialog konfirmasi
4. Jika setuju:
   - `orders.customer_confirmed` → `true`
   - `orders.customer_confirmed_at` → timestamp sekarang
   - Order pindah dari tab "Diterima" ke tab "History"
5. Muncul dialog rating (opsional)

---

### S-039 · Auto-Konfirmasi 24 Jam

1. Order sudah `completed` lebih dari 24 jam, pelanggan tidak konfirmasi
2. Cron job (ID: 6) berjalan tiap jam
3. Order yang memenuhi syarat di-set `customer_confirmed = true` otomatis
4. Order pindah ke tab "History" saat pelanggan buka MyOrdersScreen

---

### S-040 · Rating Setelah Konfirmasi

1. Dialog rating muncul (atau tap dari History)
2. Pelanggan pilih 1–5 bintang (wajib sebelum submit)
3. Isi komentar (opsional)
4. Tap "Kirim Rating"
5. Insert ke tabel `ratings` (order_id, user_id, score, review)
6. Badge di bottom nav berkurang (karena order ini tidak lagi dihitung "aktif")

**Rating label per bintang:**
- 1 bintang → "Sangat Buruk"
- 2 bintang → "Buruk"
- 3 bintang → "Cukup"
- 4 bintang → "Bagus"
- 5 bintang → "Sangat Bagus!"

---

### S-041 · Lewati Rating

1. Di dialog rating, tap "Lewati"
2. Tidak ada insert ke `ratings`
3. Order tetap di tab "History"
4. Badge di bottom nav tetap aktif (order ini masih dihitung karena belum dirating)

---

### S-042 · Badge Bottom Nav — Logika Perhitungan

Badge di tab "Pesanan" menghitung:
- Order dengan status `pending`, `waiting_verification`, `processing`, `delivered` → langsung dihitung
- Order `completed` → dihitung **hanya kalau belum dirating** (cek tabel `ratings`)
- Order `cancelled` → tidak dihitung

Badge refresh saat:
- App pertama buka (initState MainScreen)
- Pelanggan tap tab "Pesanan"

---

## BAGIAN 9 — NOTIFIKASI PUSH (FCM)

---

### S-043 · Notifikasi ke Pelanggan — Lengkap

| Trigger | Judul | Tap Notif → |
|---------|-------|-------------|
| Bukti bayar diterima (status `waiting_verification`) | "🔍 Pembayaran Diverifikasi" | /my-orders |
| Pembayaran dikonfirmasi | "✅ Pembayaran Dikonfirmasi!" | /my-orders |
| Pembayaran ditolak | "❌ Pembayaran Ditolak" | /my-orders |
| Status → `processing` | "👨‍🍳 Pesanan Sedang Dimasak" | /my-orders |
| Status → `delivered` | "🛵 Pesanan Siap!" | /my-orders |
| Status → `completed` | "✅ Pesanan Selesai" | /my-orders |
| Status → `cancelled` | "❌ Pesanan Dibatalkan" | /my-orders |
| Pengingat bayar (15 menit) | "Jangan Lupa Bayar!" | /my-orders |
| Broadcast admin | sesuai judul broadcast | /home |

---

### S-044 · Notifikasi ke Admin — Lengkap

| Trigger | Judul | Tap Notif → |
|---------|-------|-------------|
| Order baru masuk | "🛒 Pesanan Baru!" | /admin-orders |
| Pelanggan upload bukti bayar | "💳 Bukti Bayar Masuk!" | /admin-orders |
| Pelanggan batalkan pesanan | "❌ Pesanan Dibatalkan" | /admin-orders |

---

### S-045 · Pengingat Otomatis 15 Menit

1. Cron job berjalan setiap menit (`remind-pending-orders` Edge Function)
2. Cari order `pending` dengan `created_at` sudah > 15 menit dan `reminder_sent = false`
3. Kirim FCM ke pelanggan: "Jangan Lupa Bayar!"
4. Set `orders.reminder_sent = true` → tidak kirim ulang

---

### S-046 · Notif Saat App Foreground

1. FCM diterima saat app sedang dibuka
2. `flutter_local_notifications` tampilkan popup notifikasi lokal (tidak silent)
3. Pelanggan tap popup → `_handleNotificationTap` → navigate sesuai type

---

### S-047 · Notif Saat App di Background atau Killed

1. FCM diterima saat app ditutup
2. Android tampilkan notifikasi di notification bar
3. Pelanggan tap → app dibuka → `getInitialMessage` atau `onMessageOpenedApp` handle routing
4. Delay 1 detik sebelum navigate (tunggu app fully init)

---

## BAGIAN 10 — CHAT

---

### S-048 · Pelanggan Mulai Chat

1. Tab Akun → "Chat dengan Admin" → **ChatScreen** tampil
2. Kalau belum punya record di `chats` → otomatis dibuat (insert)
3. Kalau belum ada session `open` → belum bisa kirim pesan (tunggu session dibuat)
4. Sebenarnya: saat pelanggan kirim pesan pertama → session `open` otomatis dibuat

---

### S-049 · Kirim Pesan Chat

1. Pelanggan ketik pesan → tap send
2. Insert ke `chat_messages` (sender_type = `customer`)
3. Realtime: pesan langsung muncul di sisi admin (AdminChatDetailScreen)
4. Badge chat di AdminDashboard bertambah

---

### S-050 · Attach Order ke Chat

1. Pelanggan tap ikon lampiran di ChatScreen
2. Pilih pesanan dari daftar order aktif
3. Pesan dikirim dengan `order_id` → tampil sebagai kartu pesanan (bukan teks biasa)
4. Admin bisa tap kartu pesanan → melihat detail order tersebut

---

### S-051 · Admin Balas Chat

1. AdminChatsScreen menampilkan daftar chat semua pelanggan
2. Tap chat pelanggan → **AdminChatDetailScreen**
3. Admin ketik balasan → tap send
4. Insert ke `chat_messages` (sender_type = `admin`)
5. Realtime: pesan muncul di ChatScreen pelanggan

---

### S-052 · Buka Chat dari MyOrdersScreen

1. Di detail order (tap order di MyOrders) → tombol "Chat tentang Pesanan ini"
2. Navigasi ke **ChatScreen** dengan `order_id` sebagai argument
3. ChatScreen otomatis attach kartu order tersebut ke pesan pertama

---

### S-053 · Auto-Delete Chat Lama

1. Cron job tiap jam 1 pagi
2. Hapus `chat_sessions` yang status `closed` dan `closed_at` > 30 hari lalu
3. Hapus record di `chats` yang tidak punya session aktif

---

## BAGIAN 11 — PROFIL PELANGGAN

---

### S-054 · Edit Nama & Nomor HP

1. Tab Akun → "Edit Profil" → ubah nama atau nomor HP → tap "Simpan"
2. Update `users.name` dan `users.phone`
3. Kalau nomor HP diubah → email Supabase Auth juga diupdate ke `{nomorBaruHP}@gemoykitchen.com`

---

### S-055 · Upload Foto Profil

1. Tap foto profil → pilih galeri
2. Crop foto (rasio bebas)
3. Tap "Simpan"
4. File diupload ke Supabase Storage bucket `profile_photos` dengan nama `profile_{userId}_{timestamp}.jpg`
5. `users.photo_url` diupdate dengan URL publik foto baru

---

### S-056 · Ganti Password

1. Edit Profil → "Ganti Password" → isi password baru → konfirmasi
2. Supabase Auth `updateUser` dengan password baru
3. Session tetap aktif (tidak logout)

---

### S-057 · Saved Locations

1. Tab Akun → "Lokasi Tersimpan" → **SavedLocationsScreen**
2. Tap "+" → buka peta → pilih titik → isi label (contoh: "Rumah", "Kantor")
3. Insert ke `saved_locations`
4. Saat checkout, daftar saved locations tampil sebagai opsi cepat
5. Bisa set satu lokasi sebagai default (`is_default = true`)

---

## BAGIAN 12 — ADMIN: KELOLA MENU

---

### S-058 · Tambah Menu Baru

1. **AdminMenuScreen** → tab "Daftar Menu" → tap "+"
2. Isi nama, deskripsi, harga, pilih kategori (opsional)
3. Upload foto → pilih dari galeri → crop
4. Foto diupload ke bucket `menu-images` dengan nama `menu_{timestamp}.jpg`
5. Insert ke tabel `menus`, set `is_available = true`
6. Menu langsung muncul di daftar

---

### S-059 · Edit Menu

1. Tap menu di daftar → tap ikon edit
2. Ubah data → tap "Simpan"
3. Update `menus` record
4. Kalau ganti foto → foto baru diupload, URL diupdate

---

### S-060 · Nonaktifkan / Aktifkan Menu

1. Toggle `is_available` di daftar menu
2. Menu dengan `is_available = false` tidak muncul di HomeScreen pelanggan meski terjadwal

---

### S-061 · Hapus Menu

1. Tap ikon hapus → konfirmasi
2. Delete dari `menus` (CASCADE hapus `order_items` dan `menu_schedules` yang relasi)

---

### S-062 · Jadwalkan Menu untuk Hari Tertentu

1. Tab "Jadwal Mingguan" → navigasi ke tanggal target
2. Tap "+" → bottom sheet cari menu (search by nama)
3. Pilih menu → isi `max_qty`
4. Tap "Simpan" → insert ke `menu_schedules`
5. Hari yang sudah lewat: read-only, tidak bisa tambah/edit/hapus jadwal
6. Navigasi ke belakang dibatasi 90 hari

**Duplikat jadwal (menu yang sama di tanggal yang sama):**
- Sistem cek sebelum insert → muncul pesan "Menu ini sudah terjadwal di tanggal tersebut"

---

### S-063 · Atur Urutan Kategori

1. Tab "Kategori" → daftar kategori dengan tombol atas/bawah
2. Tap tombol ↑ atau ↓ untuk ubah urutan
3. Tap "Simpan Urutan" → update `sort_order` semua kategori secara atomic ke DB
4. Tunggu konfirmasi DB berhasil sebelum UI refresh (tidak optimistic update)

---

## BAGIAN 13 — ADMIN: PENGATURAN TOKO

---

### S-064 · Buka / Tutup Toko Manual

**Tutup manual:**
1. Toggle → konfirmasi → set `is_open = false`, `manually_closed_date = today`
2. Toko tutup sampai tengah malam → besok cron sync reset otomatis

**Buka manual:**
1. Toggle → konfirmasi → set `is_open = true`, `manually_opened = true`
2. Toko buka paksa meski di luar jam operasional
3. Kalau jam tutup lewat dan `manually_opened = true` → cron sync auto-tutup

---

### S-065 · Update Jam Buka & Tutup

1. Tap jam → time picker → pilih jam
2. Tap "Simpan Pengaturan"
3. Toko otomatis buka/tutup sesuai jam baru mulai hari berikutnya

---

### S-066 · Update Info Rekening Bank

1. Ubah nama bank / nomor rekening / nama pemilik → Simpan
2. Info baru langsung tampil di PaymentScreen pelanggan yang order berikutnya

---

### S-067 · Upload Gambar QRIS Baru

1. Tap area QRIS → pilih gambar dari galeri → crop (1:1)
2. Upload ke bucket `menu-images` (disimpan di sana karena tidak ada bucket khusus)
3. `store_settings.qris_image_url` diupdate

---

### S-068 · Update Pengaturan Ongkir

1. Ubah `free_km`, biaya per km, `max_delivery_km` → Simpan
2. Contoh kalkulasi live tampil di bawah form
3. Checkout berikutnya menggunakan rumus ongkir yang baru

---

### S-069 · Update Nomor WhatsApp Admin

1. Ubah nomor WA → Simpan
2. Nomor ini digunakan di tombol WA di OrderDetailScreen, PaymentScreen, dan AdminOrdersScreen

---

## BAGIAN 14 — ADMIN: LAPORAN

---

### S-070 · Lihat Statistik Dashboard

1. AdminDashboardScreen tampil:
   - Total order hari ini
   - Total pendapatan hari ini
   - Order pending (butuh aksi)
   - Menu terlaris
   - Pesanan terbaru (5 terakhir)
   - Badge chat open
2. Realtime: order baru masuk → stats update + muncul snackbar

---

### S-071 · Export Laporan Excel

1. **AdminReportsScreen** → pilih rentang tanggal → tap "Export Excel"
2. File `.xlsx` ter-generate dengan data:
   - ID pesanan, nama pelanggan, item, total, status, metode pembayaran, tanggal
3. File disimpan ke penyimpanan perangkat / di-share via share sheet
4. Nama file: `Laporan_WarungGemoy_{tanggalAwal}_{tanggalAkhir}.xlsx`

---

### S-072 · Export Laporan PDF

1. Tap "Export PDF"
2. PDF ter-generate dengan:
   - Header: logo + "LAPORAN WARUNG GEMOY"
   - Tabel data order
   - Footer: "Laporan ini digenerate otomatis oleh sistem Warung Gemoy"
3. Bisa langsung di-share atau print via Share

---

## BAGIAN 15 — ADMIN: MANAJEMEN AKUN PELANGGAN

---

### S-073 · Lihat Daftar Pelanggan

1. Dashboard → Pengaturan → "Akun Pelanggan" → **AdminCustomerAccountsScreen**
2. Daftar semua user di tabel `users` + status aktif/nonaktif

---

### S-074 · Nonaktifkan Akun Pelanggan

1. Tap pelanggan → tap "Nonaktifkan"
2. `users.is_active` → `false`
3. Pelanggan yang sedang login: saat app-nya refresh/restart → tidak bisa login, muncul pesan "Akun dinonaktifkan"
4. Aksi tercatat di `admin_audit_logs`

---

### S-075 · Aktifkan Kembali Akun

1. Tap pelanggan yang nonaktif → "Aktifkan"
2. `users.is_active` → `true`
3. Tercatat di audit log

---

### S-076 · Reset Password Pelanggan

1. Tap "Reset Password" → isi password baru
2. RPC `reset_user_password` dipanggil (SECURITY DEFINER) → update Supabase Auth
3. Tercatat di audit log dengan detail "Reset password untuk [nama]"

---

### S-077 · Hapus Akun Pelanggan

1. Tap "Hapus Akun" → konfirmasi 2x (dialog serius)
2. RPC `delete_user_account` dipanggil:
   - Hapus dari `public.users` dulu
   - Lalu hapus dari `auth.users`
3. Semua data terkait (orders, ratings, dll) tetap ada (FK ke user_id, tidak CASCADE delete)
4. Tercatat di audit log

---

### S-078 · Audit Log Admin

1. Dashboard → Pengaturan → "Riwayat Aktivitas" → **AdminAuditLogScreen**
2. Tampil semua aksi admin: jenis aksi, target, timestamp, device info (brand + model + Android ver)
3. Bisa search berdasarkan nama / nomor HP
4. Filter chips per jenis aksi (nonaktifkan, aktifkan, reset PW, hapus, dll)
5. Cron job hapus log > 90 hari tiap tengah malam

---

## BAGIAN 16 — ADMIN: PROFIL

---

### S-079 · Edit Profil Admin

1. AdminDashboard → icon profil → "Edit Profil"
2. Ubah nama / email → Simpan → update `admins.name` / `admins.email`
3. Ganti password → update via Supabase Auth
4. Semua perubahan tercatat di `admin_audit_logs`

---

## BAGIAN 17 — ADMIN: BROADCAST

---

### S-080 · Kirim Broadcast ke Semua Pelanggan

1. Dashboard → "Broadcast" → **AdminBroadcastScreen**
2. Isi judul + isi pesan → tap "Kirim"
3. Insert ke `broadcast_messages`
4. Supabase Realtime trigger di HomeScreen semua pelanggan → snackbar muncul
5. FCM dikirim ke semua `users.fcm_token` yang tidak null
6. Riwayat broadcast bisa dilihat di **BroadcastScreen** pelanggan

---

## RINGKASAN ALUR LENGKAP — SATU SIKLUS PESANAN

Berikut alur lengkap satu pesanan dari awal sampai selesai (jalur normal):

```
[PELANGGAN]                          [ADMIN]
    |                                    |
    | Buka app → HomeScreen              |
    | Lihat menu harian                  |
    | Tambah ke cart                     |
    | Checkout (pilih delivery/pickup)   |
    | Pilih lokasi + hitung ongkir       |
    | Tap "Pesan Sekarang"               |
    |   → order dibuat di DB             |
    |   → stok di-increment (atomic)     |
    |   → notif masuk ke admin ─────────→ Notif: "Pesanan Baru"
    |                                    |
    | PaymentScreen                      |
    | Upload bukti bayar                 |
    |   → status: waiting_verification   |
    |   → notif ke admin ───────────────→ Notif: "Bukti Bayar Masuk"
    |                                    |
    | Tunggu verifikasi...          Cek bukti bayar
    |                               Tap "Verifikasi & Mulai Masak"
    |                                    → status: processing
    | ←─── Notif: "Sedang Dimasak" ──────|
    | OrderStatusScreen update otomatis  |
    |                               Masak pesanan
    |                               Tap "Tandai Dikirim/Siap Diambil"
    |                                    → status: delivered
    | ←─── Notif: "Pesanan Siap!" ───────|
    |                               Serahkan pesanan
    |                               Tap "Tandai Selesai"
    |                                    → status: completed
    | ←─── Notif: "Pesanan Selesai" ─────|
    |                                    |
    | Tab "Diterima" di MyOrders         |
    | Tap "Konfirmasi Terima"            |
    |   → customer_confirmed: true       |
    |   → order pindah ke "History"      |
    |                                    |
    | Dialog rating muncul               |
    | Beri bintang + komentar            |
    | Tap "Kirim Rating"                 |
    |   → insert ke tabel ratings        |
    |   → badge bottom nav hilang        |
```

---

*Dokumen ini harus diupdate setiap ada perubahan alur bisnis, fitur baru, atau perubahan struktur DB.*
