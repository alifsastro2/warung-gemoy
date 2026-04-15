# CLAUDE.md — Gemoy Kitchen

File ini adalah konteks utama project. Selalu baca file ini di awal sesi baru.
Claude wajib update file ini setiap ada perubahan (fitur selesai, tabel baru, aturan baru).

---

## Identitas Project

- **Nama:** Gemoy Kitchen
- **Deskripsi:** Aplikasi katering rumahan — order menu harian, pembayaran, tracking pesanan
- **Platform:** Flutter (Android + Web)
- **Package ID:** `com.gemoykitchen.gemoy_kitchen`
- **Version:** 1.0.0+1

---

## Tech Stack

| Layer | Stack |
|-------|-------|
| Frontend | Flutter (Dart) |
| Backend | Supabase (PostgreSQL + Auth + Storage + Realtime + Edge Functions) |
| Notifikasi Push | Firebase FCM + flutter_local_notifications |
| Maps | Google Maps Flutter + Geolocator + Geocoding |
| State Management | Provider (CartProvider) |
| Export | excel, pdf, printing |

**Supabase URL:** `https://ncagalheqhcdgmsddaar.supabase.co`

**Dependencies utama (pubspec.yaml):**
supabase_flutter, provider, url_launcher, image_picker, image_cropper,
google_maps_flutter, geolocator, geocoding, http, excel, pdf, printing,
path_provider, share_plus, intl, firebase_core, firebase_messaging,
flutter_local_notifications, device_info_plus, flutter_launcher_icons (dev)

---

## Struktur Folder

```
lib/
├── models/
│   ├── menu_model.dart
│   └── cart_item_model.dart
├── screens/
│   ├── splash_screen.dart
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── register_screen.dart
│   ├── home/
│   │   ├── home_screen.dart         ← TIDAK BOLEH update database
│   │   └── broadcast_screen.dart
│   ├── order/
│   │   ├── cart_screen.dart
│   │   ├── checkout_screen.dart
│   │   ├── payment_screen.dart
│   │   ├── order_status_screen.dart
│   │   ├── order_detail_screen.dart
│   │   ├── my_orders_screen.dart
│   │   └── location_picker_screen.dart
│   ├── profile/
│   │   ├── profile_screen.dart
│   │   └── saved_locations_screen.dart
│   ├── chat/
│   │   └── chat_screen.dart
│   ├── admin/
│   │   ├── admin_login_screen.dart
│   │   ├── admin_profile_screen.dart
│   │   ├── admin_broadcast_screen.dart
│   │   ├── admin_reports_screen.dart
│   │   ├── dashboard/admin_dashboard_screen.dart
│   │   ├── orders/admin_orders_screen.dart
│   │   ├── menu/admin_menu_screen.dart
│   │   ├── settings/admin_settings_screen.dart
│   │   ├── settings/admin_customer_accounts_screen.dart
│   │   ├── settings/admin_audit_log_screen.dart
│   │   └── chat/
│   │       ├── admin_chats_screen.dart
│   │       └── admin_chat_detail_screen.dart
│   └── main_screen.dart
└── services/
    ├── cart_provider.dart
    ├── fcm_service.dart
    └── notification_service.dart
```

---

## Routing

```
/splash              → SplashScreen
/login               → LoginScreen
/register            → RegisterScreen
/home                → MainScreen (bottom nav: Home, Pesanan, Akun)
/cart                → CartScreen
/checkout            → CheckoutScreen
/payment             → PaymentScreen
/order-status        → OrderStatusScreen
/order-detail        → OrderDetailScreen
/my-orders           → MyOrdersScreen
/location-picker     → LocationPickerScreen
/admin-login         → AdminLoginScreen
/admin-dashboard     → AdminDashboardScreen
/admin-orders        → AdminOrdersScreen
/admin-menus         → AdminMenuScreen
/admin-settings      → AdminSettingsScreen
/admin-broadcast     → AdminBroadcastScreen
/admin-reports       → AdminReportsScreen
```

---

## Database Tables

### Tabel lengkap dengan kolom

**`users`**
| Kolom | Tipe |
|-------|------|
| id | uuid (FK → auth.users) |
| name | text |
| phone | text |
| photo_url | text |
| fcm_token | text |
| is_active | boolean DEFAULT true |
| created_at | timestamp without time zone |

**`admins`**
| Kolom | Tipe |
|-------|------|
| id | uuid |
| name | text |
| email | text |
| fcm_token | text |
| created_at | timestamptz |

**`orders`**
| Kolom | Tipe |
|-------|------|
| id | uuid |
| user_id | uuid (FK → users) |
| status | text |
| delivery_method | text |
| delivery_address | text |
| delivery_lat | double precision |
| delivery_lng | double precision |
| delivery_fee | integer |
| total | integer |
| notes | text |
| customer_confirmed | boolean |
| customer_confirmed_at | timestamptz |
| reminder_sent | boolean DEFAULT false |
| created_at | timestamp without time zone |

**`order_items`**
| Kolom | Tipe |
|-------|------|
| id | uuid |
| order_id | uuid (FK → orders CASCADE) |
| menu_id | uuid (FK → menus) |
| qty | integer |
| price | integer |
| notes | text |

**`payments`**
| Kolom | Tipe |
|-------|------|
| id | uuid |
| order_id | uuid (FK → orders) |
| method | text (transfer/qris/cod) |
| status | text |
| proof_url | text |
| verified_at | timestamptz |
| expired_at | timestamptz |
| created_at | timestamptz |

**`menus`**
| Kolom | Tipe |
|-------|------|
| id | uuid |
| name | text |
| description | text |
| price | integer |
| image_url | text |
| is_available | boolean |
| category_id | uuid (FK → menu_categories, nullable) |
| created_at | timestamptz |

**`menu_categories`**
| Kolom | Tipe |
|-------|------|
| id | uuid |
| name | text |
| sort_order | integer |
| created_at | timestamptz |

**`menu_schedules`**
| Kolom | Tipe |
|-------|------|
| id | uuid |
| menu_id | uuid (FK → menus) |
| scheduled_date | date |
| max_qty | integer |
| used_qty | integer DEFAULT 0 |

**`order_status_history`**
| Kolom | Tipe |
|-------|------|
| id | uuid |
| order_id | uuid (FK → orders) |
| status | text |
| note | text |
| created_at | timestamptz |

Trigger aktif: `on_order_status_change` — setiap UPDATE status di `orders` → auto INSERT ke `order_status_history`.

**`ratings`**
| Kolom | Tipe |
|-------|------|
| id | uuid |
| order_id | uuid (FK → orders) |
| user_id | uuid (FK → users) |
| score | integer (1-5) ← bukan `rating` |
| review | text ← bukan `comment` |
| created_at | timestamptz |

**`broadcast_messages`**
| Kolom | Tipe |
|-------|------|
| id | uuid |
| title | text |
| body | text |
| created_at | timestamptz |

**`broadcast_reads`**
| Kolom | Tipe |
|-------|------|
| id | uuid |
| broadcast_id | uuid (FK → broadcast_messages) |
| user_id | uuid (FK → users) |

**`store_settings`**
| Kolom | Tipe |
|-------|------|
| id | uuid |
| is_open | boolean |
| open_time | time |
| close_time | time |
| bank_name | text |
| bank_account | text |
| bank_holder | text |
| qris_image_url | text |
| whatsapp_number | text |
| delivery_fee_per_km | integer |
| free_km | integer |
| max_delivery_km | integer |
| max_orders_per_day | integer |
| manually_opened | boolean |
| manually_closed_date | date |
| store_lat | double precision |
| store_lng | double precision |

**`saved_locations`**
| Kolom | Tipe |
|-------|------|
| id | uuid |
| user_id | uuid (FK → users) |
| label | text |
| address | text |
| latitude | double precision |
| longitude | double precision |
| is_default | boolean |

**`chats`**
| Kolom | Tipe |
|-------|------|
| id | uuid |
| user_id | uuid (FK → users, UNIQUE) |
| created_at | timestamptz |

**`chat_sessions`**
| Kolom | Tipe |
|-------|------|
| id | uuid |
| chat_id | uuid (FK → chats) |
| order_id | uuid (FK → orders, nullable) |
| status | text (open/closed) |
| opened_at | timestamptz |
| closed_at | timestamptz |

**`chat_messages`**
| Kolom | Tipe |
|-------|------|
| id | uuid |
| session_id | uuid (FK → chat_sessions) |
| sender_type | text (customer/admin) |
| message | text |
| order_id | uuid (FK → orders, nullable) |
| created_at | timestamptz |

**`admin_audit_logs`**
| Kolom | Tipe |
|-------|------|
| id | uuid |
| admin_id | uuid (FK → admins) |
| action | text |
| target_user_id | uuid |
| target_user_phone | text |
| detail | text |
| device_info | text |
| created_at | timestamptz |

---

## RPC Functions

| Nama | Parameter | Fungsi |
|------|-----------|--------|
| `increment_used_qty` | p_menu_id uuid, p_date text, p_qty int | Atomic increment dengan FOR UPDATE row lock. Throw exception jika stok tidak cukup. |
| `decrement_used_qty` | p_menu_id uuid, p_date text, p_qty int | Kembalikan stok saat order dibatalkan |
| `reset_user_password` | user_id uuid, new_password text | Reset password pelanggan (SECURITY DEFINER) |
| `delete_user_account` | user_id uuid | Hapus dari public.users dulu, lalu auth.users (SECURITY DEFINER) |

---

## Realtime Subscriptions

| Channel | Table | Events | Digunakan Di |
|---------|-------|--------|-------------|
| `public:broadcast_messages` | broadcast_messages | INSERT | HomeScreen — snackbar broadcast baru |
| `public:orders` | orders | INSERT | AdminDashboard — notif + reload stats |
| `dashboard:chat_sessions` | chat_sessions | INSERT, UPDATE | AdminDashboard — update badge open chats |
| `menu_schedules_changes` | menu_schedules | UPDATE | CartScreen — validasi stok realtime |
| `my_orders_$userId` | orders | UPDATE | MyOrdersScreen — auto pindah tab saat status berubah |
| `chat_$chatId` | chat_messages, chat_sessions | INSERT, UPDATE | ChatScreen (pelanggan) |
| `admin_chat_$chatId` | chat_messages, chat_sessions | INSERT, UPDATE | AdminChatDetailScreen |
| `admin:chats` | chat_messages | INSERT | AdminChatsScreen — reload list chat |

---

## Storage Buckets

| Bucket | Path | Digunakan Di |
|--------|------|-------------|
| `payment-proofs` | proof_{orderId}_{timestamp}.jpg | PaymentScreen |
| `menu-images` | menu_{timestamp}.jpg | AdminMenuScreen |
| `profile_photos` | profile_{userId}_{timestamp}.jpg | ProfileScreen |

---

## Notifikasi FCM

**Jenis notifikasi ke pelanggan:**
| Trigger | Judul | Body |
|---------|-------|------|
| Status → waiting_verification | Pembayaran Diterima | Sedang diverifikasi |
| Status → processing | Pesanan Diproses | Sedang dimasak |
| Status → delivered | Pesanan Dikirim | Sedang dalam perjalanan / siap diambil |
| Status → completed | Pesanan Selesai | - |
| Status → cancelled | Pesanan Dibatalkan | - |
| Payment verified | Pembayaran Dikonfirmasi | - |
| Payment rejected | Pembayaran Ditolak | - |
| Pending 15 menit | Jangan Lupa Bayar! | Via Edge Function remind-pending-orders |

**Jenis notifikasi ke admin:**
| Trigger | Judul |
|---------|-------|
| Order baru masuk | Pesanan Baru |
| Pelanggan upload bukti bayar | Bukti Pembayaran Masuk |
| Pelanggan batalkan pesanan | Pesanan Dibatalkan |

**FCM Token:** disimpan di `users.fcm_token` (pelanggan) dan `admins.fcm_token` (admin). Dual-table lookup di `fcm_service.dart` dan `notification_service.dart`.

**Edge Function:** `send-reminder-notification` — FCM v1 API dengan service account JWT (Deno/TypeScript).

---

## Cron Jobs Aktif

| ID | Nama | Jadwal | Fungsi |
|----|------|--------|--------|
| 6 | auto-confirm-orders | tiap jam | Auto-konfirmasi pesanan completed > 24 jam |
| 7 | delete-old-audit-logs | tiap tengah malam (0 0 * * *) | Hapus admin_audit_logs > 90 hari |
| 8 | delete-old-chats | tiap jam 1 pagi (0 1 * * *) | Hapus chat_sessions closed > 30 hari |
| 9 | delete-old-chats-table | tiap jam 1 pagi | Hapus chats tanpa session aktif |
| 10 | delete-old-schedules | tiap tengah malam (0 0 * * *) | Hapus menu_schedules > 90 hari |
| - | remind-pending-orders | tiap menit (* * * * *) | Kirim FCM reminder via Edge Function |

---

## Alur Bisnis Penting

- **Login pelanggan:** fake email format `{nomor_hp}@gemoykitchen.com`
- **Admin login:** halaman tersembunyi — tap logo 7x + tahan 5 detik
- **Ongkir:** ceiling per km, gratis X km pertama, ada batas `max_delivery_km`
- **Auto-cancel:** pesanan pending otomatis dibatalkan setelah 30 menit (timer di payment_screen + cron)
- **Status pesanan:** `pending` → `waiting_verification` → `processing` → `delivered` → `completed` / `cancelled`
- **Stok menu:** `used_qty` di-increment atomic via RPC saat checkout, di-decrement saat cancel
- **Chat:** 1 chat per akun pelanggan, bisa banyak sessions. Session bisa dikaitkan dengan order. Pesan bisa attach order card.
- **Jadwal mingguan:** hari lewat read-only, navigasi dibatasi 90 hari ke belakang

---

## Status Fitur

### Selesai
- [x] Login/Register via nomor HP
- [x] Menu harian + stok + jadwal mingguan + kategori
- [x] Cart + validasi stok realtime
- [x] Checkout + Google Maps + ongkir otomatis + atomic stock increment
- [x] Saved locations + max_delivery_km
- [x] Payment (transfer/QRIS/COD) + upload bukti + timer auto-cancel
- [x] Order status tracking (5 tab: Pembayaran, Diproses, Siap, Diterima, History)
- [x] Riwayat status pesanan — tabel `order_status_history` + trigger + timeline UI
- [x] Rating & Review (wajib setelah konfirmasi, opsional lewati)
- [x] Konfirmasi penerimaan pesanan + auto-konfirmasi 24 jam (cron ID: 6)
- [x] Push Notification (FCM) + deep linking (semua status + admin events)
- [x] Notifikasi pengingat otomatis 15 menit (Edge Function + cron per menit)
- [x] Auto login (persistent session) + routing fix admin/pelanggan
- [x] Badge di tab Pesanan Saya, bottom nav, dan dashboard admin
- [x] Realtime order status update di MyOrdersScreen
- [x] Edit Profil (foto, nama, HP, password)
- [x] Broadcast pesan dari admin ke semua pelanggan + notifikasi in-app
- [x] Admin: dashboard (stats, recent orders, badge chat, Realtime)
- [x] Admin: kelola pesanan (6 tab, search, update status, verifikasi bayar)
- [x] Admin: kelola menu (CRUD, foto, kategori, atur urutan, jadwal mingguan)
- [x] Admin: jadwal mingguan (hari lewat read-only, batas 90 hari, search menu)
- [x] Admin: laporan + export Excel/PDF
- [x] Admin: Pengaturan Toko (jam buka, rekening, QRIS, ongkir)
- [x] Admin Account Management (kelola pelanggan, nonaktifkan/aktifkan/reset PW/hapus)
- [x] Admin Audit Log (search + filter, auto-delete 90 hari, device info)
- [x] Admin Profil (edit nama, email, password — tercatat di audit log)
- [x] Dashboard accordion (Pengaturan expandable: Toko, Akun Pelanggan, Riwayat Aktivitas)
- [x] Fitur Chat — 1 chat/akun, multi-session, order card mention, badge realtime, auto-delete 30 hari

### Belum Selesai
- [ ] **Fitur 10 — Icon aplikasi custom:** sudah dipasang (`icon-app.png`), menunggu asset final dari owner

---

## Aturan Coding

- **Jangan rewrite file penuh** kecuali diminta — selalu gunakan targeted edit (cari X ganti Y)
- **Konfirmasi dulu** sebelum perubahan besar (struktur DB baru, perubahan alur utama)
- **Sebelum menulis SQL**, tanya/cek struktur tabel yang relevan terlebih dahulu
- **Bahasa Indonesia** untuk semua komunikasi
- `home_screen.dart` **TIDAK BOLEH** melakukan update/insert/delete ke database
- Jangan tambah fitur, refactor, atau "improvement" di luar yang diminta

---

## Catatan Sesi

### Sesi 2026-04-07 (selesai)
- Bug fix: `my_orders_screen.dart` tambah Realtime listener → order cancelled otomatis pindah tab
- Bug fix: `admin_menu_screen.dart` — duplikat jadwal dicegah, dropdown filter menu sudah terjadwal
- Bug fix: `payment_screen.dart` — timer tidak fire berulang, form disembunyikan saat expired, tombol kembali muncul
- Bug fix: `admin_menu_screen.dart` — `_loadCategories` pakai `ascending: true` (default supabase_flutter adalah descending!)
- Bug fix: jadwal mingguan — hari lewat jadi read-only, FAB "+" hanya di tab Daftar Menu
- Fitur: search bottom sheet untuk pilih menu saat jadwalkan
- Fitur: navigasi jadwal mingguan dibatasi 90 hari ke belakang, cron ID 10
- Fitur: atur urutan kategori — save atomic (tunggu DB), tombol "+" pindah ke kiri
- Bug fix: `increment_used_qty` RPC diupdate jadi atomic dengan FOR UPDATE row lock
- Bug fix: `checkout_screen.dart` — urutan insert diperbaiki, error message bersih
- Bug fix: `admin_chat_detail_screen.dart` — `_load()` dipanggil langsung setelah send
- Bug fix: `admin_dashboard_screen.dart` — Realtime listener `chat_sessions` untuk badge akurat

### Sesi 2026-04-06 (selesai)
- Admin Account Management selesai dan ter-test
- File baru: `admin_customer_accounts_screen.dart`, `admin_audit_log_screen.dart`, `admin_profile_screen.dart`
- Tabel baru: `admin_audit_logs`, kolom baru: `users.is_active`
- RPC baru: `reset_user_password`, `delete_user_account`
- Dashboard: menu Pengaturan jadi accordion expandable (Toko, Akun Pelanggan, Riwayat Aktivitas)
- AppBar dashboard: icon profil dengan dropdown Edit Profil + Keluar
- Profil admin: ubah nama, email, password — semua tercatat di audit log
- Device info menggunakan `device_info_plus` → format "BRAND Model (Android X)"
- Audit log: search bar + filter chips per jenis aksi
- Cron job ID 7: auto-hapus audit log > 90 hari tiap tengah malam

### Sesi 2026-04-05 (selesai)
- Fitur Chat selesai (menggantikan sistem Komplain)
- Fitur Notifikasi Pengingat Otomatis (Edge Function FCM v1 API)
- App icon custom dengan flutter_launcher_icons
- FCM admin fix: dual-table lookup di semua service
- Auto-login routing fix: admin → `/admin-dashboard`
- Notif admin saat pelanggan upload bukti bayar dan batalkan pesanan
