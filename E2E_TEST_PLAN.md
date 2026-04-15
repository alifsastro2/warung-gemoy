# E2E Test Plan — Warung Gemoy

Dokumen ini berisi skenario pengujian end-to-end yang harus dilakukan sebelum rilis atau setelah ada perubahan besar.

---

## Cara Baca

- **Prasyarat** — kondisi yang harus ada sebelum test dimulai
- **Langkah** — urutan aksi yang dilakukan
- **Expected** — hasil yang seharusnya terjadi
- ✅ = wajib lulus sebelum rilis
- ⚠️ = penting tapi bisa dilakukan paralel

---

## 1. Autentikasi

### 1.1 ✅ Register pelanggan baru
**Prasyarat:** nomor HP belum pernah dipakai  
**Langkah:**
1. Buka app → tap "Daftar"
2. Isi nama, nomor HP, password
3. Tap "Daftar Sekarang"

**Expected:**
- Berhasil masuk ke HomeScreen
- Data muncul di tabel `users` Supabase
- FCM token tersimpan di `users.fcm_token`

---

### 1.2 ✅ Login pelanggan
**Prasyarat:** akun sudah terdaftar  
**Langkah:**
1. Buka app → isi nomor HP + password → tap "Masuk"

**Expected:**
- Langsung masuk ke HomeScreen
- Session persistent — tutup & buka app lagi tetap login

---

### 1.3 ✅ Auto-login (persistent session)
**Langkah:**
1. Login → paksa tutup app (swipe kill)
2. Buka app lagi

**Expected:** langsung masuk HomeScreen, tidak ke SplashScreen login

---

### 1.4 ✅ Login admin
**Prasyarat:** akun admin ada di tabel `admins`  
**Langkah:**
1. Di HomeScreen, tap logo app 7x → tahan 5 detik
2. Isi email + password admin
3. Tap "Masuk"

**Expected:** masuk ke AdminDashboard, bukan HomeScreen pelanggan

---

### 1.5 ✅ Logout
**Langkah:** Tab Akun → Keluar (pelanggan) / Admin Profil → Keluar (admin)

**Expected:**
- Kembali ke LoginScreen
- FCM token dihapus dari DB (`fcm_token = null`)
- Buka app lagi → tidak auto-login

---

## 2. Menu & Cart

### 2.1 ✅ Tampil menu hari ini
**Prasyarat:** ada menu terjadwal untuk hari ini dengan `used_qty < max_qty`  
**Langkah:** Buka HomeScreen → lihat daftar menu

**Expected:**
- Menu dengan stok tersedia tampil normal
- Menu habis (`used_qty >= max_qty`) tampil disabled/greyed out

---

### 2.2 ✅ Tambah menu ke cart
**Langkah:**
1. Tap menu → tap "+"
2. Coba tambah lebih dari stok yang tersisa

**Expected:**
- Di bawah stok → berhasil ditambah
- Melebihi stok → muncul pesan "Stok tidak cukup" atau tombol "+" disabled

---

### 2.3 ✅ Validasi stok realtime di CartScreen
**Prasyarat:** 2 device (device A = user biasa, device B = user lain atau admin)  
**Langkah:**
1. Device A: buka CartScreen, ada item di cart
2. Device B: order menu yang sama sampai stok habis
3. Device A: tap "Checkout"

**Expected:** Device A mendapat pesan stok tidak cukup, tidak bisa checkout

---

### 2.4 ✅ Hapus item dari cart
**Langkah:** Di CartScreen, kurangi qty sampai 0 atau swipe hapus

**Expected:** item hilang dari cart, total diupdate

---

## 3. Checkout & Ongkir

### 3.1 ✅ Checkout — pengiriman (delivery)
**Prasyarat:** toko buka, ada menu di cart  
**Langkah:**
1. Tap "Checkout"
2. Pilih "Diantar"
3. Izinkan GPS → pilih lokasi via maps
4. Konfirmasi alamat
5. Tap "Pesan Sekarang"

**Expected:**
- Ongkir terhitung otomatis berdasarkan jarak
- Kalau jarak ≤ `free_km` → ongkir Rp 0 / "Gratis"
- Kalau jarak > `max_delivery_km` → muncul peringatan tidak bisa dipesan
- Order berhasil dibuat → masuk ke PaymentScreen

---

### 3.2 ✅ Checkout — ambil sendiri (pickup)
**Langkah:**
1. Tap "Checkout" → pilih "Ambil Sendiri"
2. Tap "Pesan Sekarang"

**Expected:**
- Tidak ada kolom ongkir / ongkir Rp 0
- Order berhasil → masuk ke PaymentScreen
- Di OrderStatusScreen label "delivered" menjadi "Siap Diambil"

---

### 3.3 ✅ Pakai saved location
**Prasyarat:** sudah ada lokasi tersimpan di profil  
**Langkah:** Di CheckoutScreen, pilih dari daftar "Lokasi Tersimpan"

**Expected:** alamat & koordinat terisi otomatis, ongkir langsung terhitung

---

### 3.4 ✅ Validasi max order per hari
**Prasyarat:** `max_orders_per_day` di store_settings sudah hampir penuh  
**Expected:** saat checkout, muncul pesan toko sudah penuh jika batas tercapai

---

## 4. Pembayaran

### 4.1 ✅ Pembayaran Transfer Bank
**Langkah:**
1. Di PaymentScreen pilih "Transfer Bank"
2. Salin nomor rekening → lakukan transfer (simulasi)
3. Upload foto bukti bayar
4. Tap "Kirim Bukti Pembayaran"

**Expected:**
- Foto terupload ke bucket `payment-proofs`
- Status payment → `waiting_verification`
- Status order → `waiting_verification`
- Admin dapat notifikasi FCM "Bukti Bayar Masuk"

---

### 4.2 ✅ Pembayaran QRIS
**Langkah:** Pilih "QRIS" → gambar QRIS tampil → upload bukti

**Expected:** sama seperti 4.1

---

### 4.3 ✅ Pembayaran COD
**Langkah:** Pilih "Bayar di Tempat (COD)" → tap "Konfirmasi Pesanan COD"

**Expected:**
- Status order tetap `pending` (menunggu konfirmasi admin)
- Di tab "Pembayaran" MyOrders → tap order COD → masuk ke OrderStatusScreen (bukan PaymentScreen)
- Admin mendapat notifikasi pesanan baru

---

### 4.4 ✅ Timer auto-cancel
**Prasyarat:** buat order non-COD, JANGAN upload bukti bayar  
**Langkah:** Tunggu 30 menit (atau cepat-cepatkan via debug)

**Expected:**
- Countdown timer di PaymentScreen mencapai 0
- Order otomatis `cancelled`
- Stok dikembalikan (`used_qty` berkurang)

---

### 4.5 ✅ Upload bukti bayar setelah timer habis
**Langkah:** Tunggu expired → coba upload bukti

**Expected:** form upload disembunyikan, muncul tombol "Kembali ke Beranda"

---

## 5. Admin — Kelola Pesanan

### 5.1 ✅ Verifikasi pembayaran Transfer/QRIS
**Prasyarat:** ada order dengan status `waiting_verification`  
**Langkah:**
1. Admin buka AdminOrdersScreen → tab "Perlu Aksi"
2. Tap order → tap "✅ Verifikasi & Mulai Masak"

**Expected:**
- Status order → `processing`
- `payments.status` → `verified`, `payments.verified_at` terisi
- Pelanggan dapat notifikasi "Pesanan Sedang Dimasak"
- Order pindah ke tab "Diproses"

---

### 5.2 ✅ Tolak pembayaran
**Langkah:** Di tab "Perlu Aksi" → tap "❌ Tolak Pembayaran"

**Expected:**
- Status order → `cancelled`
- Stok dikembalikan
- Pelanggan dapat notifikasi "Pembayaran Ditolak"

---

### 5.3 ✅ Konfirmasi order COD
**Langkah:** Tab "Perlu Aksi" → order COD pending → "✅ Konfirmasi Pesanan Cash/Tunai"

**Expected:** status → `processing`, pelanggan dapat notif

---

### 5.4 ✅ Update status: processing → delivered → completed
**Langkah:**
1. Tab "Diproses" → tap order → "🛵 Tandai Sedang Dikirim"
2. Tab "Siap" → tap order → "✅ Tandai Selesai"

**Expected:**
- Setiap update: status berubah, notif terkirim ke pelanggan
- Order pindah tab sesuai status baru
- OrderStatusScreen pelanggan update realtime (tanpa refresh manual)

---

### 5.5 ✅ Batalkan pesanan dari status processing / delivered
**Langkah:** Di tab "Diproses" atau "Siap" → tap "❌ Batalkan Pesanan"

**Expected:**
- Muncul dialog konfirmasi
- Jika dikonfirmasi: status → `cancelled`, stok dikembalikan, notif ke pelanggan

---

### 5.6 ✅ Search order
**Langkah:** Ketik nama pelanggan / nomor HP / 8 karakter pertama order ID di search bar

**Expected:** daftar order difilter sesuai query

---

### 5.7 ✅ Badge tab admin
**Expected:** tab "Perlu Aksi" menampilkan jumlah order pending + waiting_verification

---

## 6. Tracking Status Pesanan (Pelanggan)

### 6.1 ✅ OrderStatusScreen realtime
**Prasyarat:** 2 device — pelanggan buka OrderStatusScreen, admin di AdminOrdersScreen  
**Langkah:** Admin update status order

**Expected:** OrderStatusScreen pelanggan berubah otomatis tanpa tap "Refresh"

---

### 6.2 ✅ Timeline riwayat status
**Langkah:** Buka OrderStatusScreen setelah order melewati beberapa status

**Expected:** Timeline menampilkan urutan status dari terbaru ke terlama, lengkap dengan timestamp

---

### 6.3 ✅ MyOrdersScreen realtime
**Langkah:** Pelanggan buka tab "Diproses" → admin update ke `delivered`

**Expected:** order otomatis pindah ke tab "Siap" tanpa refresh manual

---

## 7. Konfirmasi Penerimaan & Rating

### 7.1 ✅ Konfirmasi penerimaan pesanan
**Prasyarat:** order status `completed`  
**Langkah:** Tab "Diterima" → tap tombol "Konfirmasi Pesanan Diterima"

**Expected:**
- `orders.customer_confirmed` → `true`
- Order pindah dari tab "Diterima" ke tab "History"

---

### 7.2 ✅ Auto-konfirmasi 24 jam
**Prasyarat:** order `completed` lebih dari 24 jam, belum dikonfirmasi  
**Expected:** cron job otomatis set `customer_confirmed = true`

---

### 7.3 ✅ Rating & review
**Langkah:** Di tab "History" → tap order → tap bintang → isi komentar → "Kirim Rating"

**Expected:**
- Data tersimpan di tabel `ratings` (kolom `score` dan `review`)
- Rating tidak bisa disubmit ulang untuk order yang sama
- Badge di bottom nav berkurang

---

### 7.4 ✅ Lewati rating
**Langkah:** Di dialog rating → tap "Lewati"

**Expected:** order tetap di History, tidak diminta rating lagi

---

## 8. Pembatalan oleh Pelanggan

### 8.1 ✅ Batalkan order pending (non-COD)
**Prasyarat:** order masih `pending`, belum upload bukti  
**Langkah:** Tab "Pembayaran" → tap order → tombol "Batalkan Pesanan"

**Expected:**
- Muncul dialog konfirmasi
- Status → `cancelled`
- Stok dikembalikan
- Admin dapat notifikasi "Pesanan Dibatalkan"

---

## 9. Notifikasi Push (FCM)

### 9.1 ✅ Notif ke pelanggan per perubahan status
**Test semua status:**
- `waiting_verification` → "Pembayaran Diverifikasi"
- `processing` → "Pesanan Sedang Dimasak"
- `delivered` → "Pesanan Siap!"
- `completed` → "Pesanan Selesai"
- `cancelled` → "Pesanan Dibatalkan"
- payment rejected → "Pembayaran Ditolak"

**Expected:** Notifikasi muncul di device pelanggan, tap notif → buka `/my-orders`

---

### 9.2 ✅ Notif ke admin
- Order baru masuk → "Pesanan Baru"
- Pelanggan upload bukti → "Bukti Bayar Masuk"
- Pelanggan batalkan → "Pesanan Dibatalkan"

**Expected:** tap notif admin → buka `/admin-orders`

---

### 9.3 ✅ Notif pengingat pending 15 menit
**Prasyarat:** order pending sudah > 15 menit, `reminder_sent = false`  
**Expected:** pelanggan dapat FCM "Jangan Lupa Bayar!", `reminder_sent` → `true` (tidak kirim ulang)

---

### 9.4 ⚠️ Notif saat app di foreground
**Expected:** muncul popup notifikasi lokal (flutter_local_notifications), tidak hilang begitu saja

---

### 9.5 ⚠️ Notif saat app tertutup (killed)
**Expected:** notif tetap diterima, tap → buka app dan navigasi ke screen yang tepat

---

## 10. Fitur Chat

### 10.1 ✅ Pelanggan mulai chat
**Langkah:** Tab Akun → "Chat dengan Admin" → ketik pesan → kirim

**Expected:**
- Pesan muncul di sisi pelanggan
- Admin melihat chat baru di AdminChatsScreen
- Realtime: pesan muncul tanpa refresh

---

### 10.2 ✅ Attach order ke chat
**Langkah:** Di ChatScreen → tap ikon lampiran → pilih pesanan

**Expected:** kartu pesanan tampil di chat (bukan teks biasa)

---

### 10.3 ✅ Admin balas chat
**Langkah:** Admin buka AdminChatsScreen → pilih chat → ketik balasan

**Expected:**
- Pesan muncul realtime di sisi pelanggan
- Badge chat di dashboard admin berkurang kalau sudah dibuka

---

### 10.4 ⚠️ Auto-delete chat session setelah 30 hari
**Expected:** cron job hapus `chat_sessions` yang `closed` lebih dari 30 hari

---

## 11. Profil Pelanggan

### 11.1 ✅ Edit nama & nomor HP
**Langkah:** Tab Akun → Edit Profil → ubah nama / nomor HP → Simpan

**Expected:** data terupdate di tabel `users`

---

### 11.2 ✅ Upload foto profil
**Langkah:** Tap foto → pilih dari galeri → crop → Simpan

**Expected:**
- Foto terupload ke bucket `profile_photos`
- Foto baru tampil di profil
- URL tersimpan di `users.photo_url`

---

### 11.3 ✅ Ganti password
**Langkah:** Edit Profil → Ganti Password → isi password baru → Simpan

**Expected:** bisa login ulang dengan password baru

---

### 11.4 ✅ Kelola saved locations
**Langkah:** Tab Akun → Lokasi Tersimpan → tambah lokasi baru via maps

**Expected:** lokasi muncul di daftar, bisa dipilih saat checkout

---

## 12. Admin — Kelola Menu

### 12.1 ✅ Tambah menu baru
**Langkah:** AdminMenuScreen → "+" → isi nama, harga, deskripsi, foto → Simpan

**Expected:** menu muncul di daftar, foto terupload ke bucket `menu-images`

---

### 12.2 ✅ Jadwalkan menu untuk tanggal tertentu
**Langkah:** Tab "Jadwal Mingguan" → pilih hari → tap "+" → cari menu → isi max_qty → Simpan

**Expected:**
- Data tersimpan di `menu_schedules`
- Menu tampil di HomeScreen pelanggan pada tanggal yang dijadwalkan
- Hari yang sudah lewat read-only (tidak bisa diubah)

---

### 12.3 ✅ Edit & hapus menu
**Expected:** perubahan langsung tercermin di HomeScreen, foto lama tidak mengganggu

---

### 12.4 ✅ Atur urutan kategori
**Langkah:** Tab "Kategori" → drag atau naikkan/turunkan urutan → Simpan

**Expected:** urutan kategori di HomeScreen berubah sesuai `sort_order`

---

## 13. Admin — Pengaturan Toko

### 13.1 ✅ Buka / tutup toko manual
**Langkah:** AdminSettingsScreen → toggle "Toko Buka" → konfirmasi

**Expected:**
- Kalau tutup: pelanggan tidak bisa checkout, muncul pesan toko tutup
- Kalau buka: pelanggan bisa checkout kembali
- Kalau tutup hari ini → besok otomatis buka lagi (cek via cron sync)

---

### 13.2 ✅ Ubah jam buka/tutup
**Expected:** jam toko terupdate, toko otomatis tutup saat jam tutup lewat kalau `manually_opened`

---

### 13.3 ✅ Ubah info rekening & QRIS
**Langkah:** Ubah nama bank, nomor rekening, upload gambar QRIS baru → Simpan

**Expected:** info baru tampil di PaymentScreen pelanggan saat order berikutnya

---

### 13.4 ✅ Ubah pengaturan ongkir
**Langkah:** Ubah `free_km`, biaya per km, `max_delivery_km` → Simpan

**Expected:** ongkir terhitung ulang dengan rumus baru saat checkout berikutnya

---

## 14. Admin — Laporan

### 14.1 ✅ Export laporan Excel
**Langkah:** AdminReportsScreen → pilih rentang tanggal → "Export Excel"

**Expected:** file `.xlsx` terdownload berisi data order sesuai filter

---

### 14.2 ✅ Export laporan PDF
**Langkah:** "Export PDF" → Share / Print

**Expected:** PDF ter-generate dengan header logo + nama "LAPORAN WARUNG GEMOY", data benar

---

## 15. Admin — Manajemen Akun Pelanggan

### 15.1 ✅ Nonaktifkan akun pelanggan
**Expected:** pelanggan tidak bisa login (`is_active = false`), muncul pesan akun dinonaktifkan

---

### 15.2 ✅ Reset password pelanggan
**Expected:** RPC `reset_user_password` berhasil, pelanggan bisa login dengan password baru

---

### 15.3 ✅ Hapus akun pelanggan
**Expected:** data dihapus dari `public.users` dan `auth.users`, aksi tercatat di `admin_audit_logs`

---

### 15.4 ✅ Audit log
**Expected:** setiap aksi admin (nonaktifkan, reset PW, hapus) tercatat dengan timestamp + device info

---

## 16. Broadcast

### 16.1 ✅ Kirim broadcast
**Langkah:** AdminBroadcastScreen → isi judul & pesan → "Kirim"

**Expected:**
- Semua pelanggan aktif dapat FCM
- Snackbar notifikasi muncul di HomeScreen pelanggan secara realtime

---

## 17. Skenario Khusus / Edge Cases

### 17.1 ✅ Stok habis saat checkout (race condition)
**Langkah:** 2 user checkout item yang stoknya hanya 1 secara bersamaan

**Expected:** hanya 1 yang berhasil, yang lain mendapat error stok tidak cukup (RPC `increment_used_qty` atomic)

---

### 17.2 ✅ Order dengan beberapa item, salah satu stok habis saat checkout
**Expected:** seluruh order gagal, stok item yang sempat terincremen di-rollback

---

### 17.3 ✅ Lokasi di luar jangkauan max_delivery_km
**Expected:** checkout tidak bisa dilanjutkan, tampil pesan jarak terlalu jauh

---

### 17.4 ✅ Toko tutup saat user coba checkout
**Expected:** muncul pesan toko sedang tutup, cart tetap tersimpan

---

### 17.5 ⚠️ App dibuka setelah lama tidak dipakai (token expired)
**Expected:** auto-refresh session atau redirect ke login dengan pesan yang ramah

---

## Urutan Test yang Disarankan

Untuk test session singkat, ikuti urutan ini:

```
Register → Login → Lihat menu → Tambah cart → Checkout delivery 
→ Bayar transfer → Upload bukti → [Admin] Verifikasi 
→ [Admin] Update ke delivered → Pelanggan konfirmasi terima 
→ Rating → Cek badge hilang
```

Lalu test edge case:
```
COD order → Batalkan pesanan → Cek stok kembali
```

---

*Dokumen ini harus diupdate setiap ada fitur baru atau perubahan alur bisnis utama.*
