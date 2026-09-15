-- DDL
CREATE TABLE stand (
    id_stand SERIAL PRIMARY KEY,
    nama_stand VARCHAR(100) NOT NULL,
    no_kios VARCHAR(10) NOT NULL,
    nama_pemilik VARCHAR(100),
    no_telepon VARCHAR(20)
);

CREATE TABLE kategori (
    id_kategori SERIAL PRIMARY KEY,
    nama_kategori VARCHAR(50) NOT NULL
);

CREATE TABLE menu (
    id_menu SERIAL PRIMARY KEY,
    id_stand INT NOT NULL REFERENCES stand(id_stand) ON DELETE CASCADE,
    id_kategori INT NOT NULL REFERENCES kategori(id_kategori) ON DELETE RESTRICT,
    nama_menu VARCHAR(100) NOT NULL,
    harga NUMERIC(10,2) NOT NULL,
    status VARCHAR(20) DEFAULT 'tersedia' CHECK (status IN ('tersedia', 'habis'))
);

CREATE TABLE transaksi (
    id_transaksi SERIAL PRIMARY KEY,
    kode_transaksi VARCHAR(30) UNIQUE NOT NULL,
    nama_pembeli VARCHAR(50) DEFAULT 'Umum',
    nomor_meja VARCHAR(10),
    total_bayar NUMERIC(10,2) NOT NULL DEFAULT 0,
    metode_bayar VARCHAR(20) DEFAULT 'tunai' CHECK (metode_bayar IN ('tunai', 'qris', 'debit')),
    status_bayar VARCHAR(20) DEFAULT 'lunas' CHECK (status_bayar IN ('lunas', 'batal')),
    waktu_transaksi TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE detail_transaksi (
    id_detail SERIAL PRIMARY KEY,
    id_transaksi INT NOT NULL REFERENCES transaksi(id_transaksi) ON DELETE CASCADE,
    id_menu INT NOT NULL REFERENCES menu(id_menu) ON DELETE RESTRICT,
    jumlah INT NOT NULL,
    harga_satuan NUMERIC(10,2) NOT NULL,
    subtotal NUMERIC(10,2) NOT NULL,
    catatan VARCHAR(100)
);

-- SEED DATA
INSERT INTO stand (nama_stand, no_kios, nama_pemilik, no_telepon) VALUES
('Soto & Sop Barokah', 'K-01', 'Pak Joko', '081234567801'),
('Ayam Geprek Nampol', 'K-02', 'Bu Sri', '081234567802'),
('Bakso & Mie Ayam Podomoro', 'K-03', 'Mas Wahyu', '081234567803'),
('Kedai Nasi Goreng 88', 'K-04', 'Bang Dedi', '081234567804'),
('Aneka Minuman & Kopi Segar', 'K-05', 'Mbak Fitri', '081234567805'),
('Gorengan & Snack Makmur', 'K-06', 'Pak Hendra', '081234567806');

INSERT INTO kategori (nama_kategori) VALUES
('Makanan Berat'),
('Minuman Dingin'),
('Minuman Hangat'),
('Camilan'),
('Ekstra');

INSERT INTO menu (id_stand, id_kategori, nama_menu, harga, status) VALUES
(1, 1, 'Soto Ayam Lamongan', 15000, 'tersedia'),
(1, 1, 'Soto Daging Sapi', 20000, 'tersedia'),
(1, 1, 'Sop Iga Sapi', 28000, 'tersedia'),
(1, 5, 'Nasi Putih', 5000, 'tersedia'),
(1, 5, 'Kerupuk Kaleng', 2000, 'tersedia'),
(2, 1, 'Paket Ayam Geprek Sambal Korek', 18000, 'tersedia'),
(2, 1, 'Paket Ayam Geprek Keju', 22000, 'tersedia'),
(2, 1, 'Ayam Bakar Madu', 20000, 'tersedia'),
(2, 5, 'Tahu & Tempe Goreng', 4000, 'tersedia'),
(2, 5, 'Ekstra Sambal', 3000, 'tersedia'),
(3, 1, 'Bakso Urat Jumbo', 18000, 'tersedia'),
(3, 1, 'Bakso Telur', 16000, 'tersedia'),
(3, 1, 'Mie Ayam Solo', 13000, 'tersedia'),
(3, 1, 'Mie Ayam Bakso', 17000, 'tersedia'),
(3, 4, 'Pangsit Goreng Porsi', 6000, 'tersedia'),
(4, 1, 'Nasi Goreng Spesial', 17000, 'tersedia'),
(4, 1, 'Nasi Goreng Mawut', 16000, 'tersedia'),
(4, 1, 'Mie Goreng Seafood', 20000, 'tersedia'),
(4, 1, 'Kwetiau Goreng Sapi', 22000, 'tersedia'),
(4, 1, 'Bihun Goreng Ayam', 16000, 'tersedia'),
(5, 2, 'Es Teh Manis', 4000, 'tersedia'),
(5, 3, 'Teh Tarik Hangat', 6000, 'tersedia'),
(5, 2, 'Es Jeruk Peras', 6000, 'tersedia'),
(5, 2, 'Jus Alpukat', 12000, 'tersedia'),
(5, 2, 'Jus Mangga', 10000, 'tersedia'),
(5, 3, 'Kopi Tubruk', 5000, 'tersedia'),
(5, 2, 'Es Kopi Susu Aren', 13000, 'tersedia'),
(6, 4, 'Bakwan Jagung (3 pcs)', 5000, 'tersedia'),
(6, 4, 'Pisang Goreng Crispy', 7000, 'tersedia'),
(6, 4, 'Tempe Mendoan (4 pcs)', 8000, 'tersedia'),
(6, 4, 'Cireng Bumbu Rujak', 10000, 'tersedia'),
(6, 4, 'Dimsum Ayam (4 pcs)', 14000, 'tersedia');

INSERT INTO transaksi (kode_transaksi, nama_pembeli, nomor_meja, total_bayar, metode_bayar, status_bayar, waktu_transaksi) VALUES
('TRX-001', 'Rian Pratama', '01', 19000, 'qris', 'lunas', '2026-09-10 10:15:00'),
('TRX-002', 'Dina Kurnia', '04', 22000, 'tunai', 'lunas', '2026-09-10 10:25:00'),
('TRX-003', 'Agus Susanto', '02', 17000, 'qris', 'lunas', '2026-09-10 11:00:00'),
('TRX-004', 'Putri Ayu', '07', 25000, 'debit', 'lunas', '2026-09-10 11:15:00'),
('TRX-005', 'Bambang Tri', '03', 21000, 'tunai', 'lunas', '2026-09-10 11:30:00'),
('TRX-006', 'Siti Fatimah', '05', 22000, 'qris', 'lunas', '2026-09-10 11:45:00'),
('TRX-007', 'Doni Kusuma', '09', 24000, 'tunai', 'lunas', '2026-09-10 12:00:00'),
('TRX-008', 'Rina Wati', '06', 33000, 'qris', 'lunas', '2026-09-10 12:10:00'),
('TRX-009', 'Eko Purnomo', '08', 21000, 'qris', 'lunas', '2026-09-10 12:20:00'),
('TRX-010', 'Bayu Setiawan', '10', 26000, 'tunai', 'lunas', '2026-09-10 12:35:00'),
('TRX-011', 'Lestari', '01', 17000, 'tunai', 'lunas', '2026-09-10 12:45:00'),
('TRX-012', 'Fajar Sidik', '02', 20000, 'qris', 'lunas', '2026-09-10 13:00:00'),
('TRX-013', 'Maya Indah', '11', 28000, 'debit', 'lunas', '2026-09-10 13:15:00'),
('TRX-014', 'Hendra Gunawan', '12', 17000, 'tunai', 'lunas', '2026-09-10 13:30:00'),
('TRX-015', 'Dewi Lestari', '03', 14000, 'qris', 'lunas', '2026-09-10 13:45:00'),
('TRX-016', 'Rizky Fadilah', '14', 21000, 'tunai', 'lunas', '2026-09-11 11:10:00'),
('TRX-017', 'Tia Rosalina', '05', 18000, 'qris', 'lunas', '2026-09-11 11:30:00'),
('TRX-018', 'Arief Budiman', '07', 24000, 'tunai', 'lunas', '2026-09-11 11:55:00'),
('TRX-019', 'Nadia Safitri', '08', 19000, 'qris', 'lunas', '2026-09-11 12:05:00'),
('TRX-020', 'Galih Permana', '04', 26000, 'debit', 'lunas', '2026-09-11 12:20:00'),
('TRX-021', 'Anisa Rahma', '15', 12000, 'tunai', 'lunas', '2026-09-11 12:40:00'),
('TRX-022', 'Fandy Ahmad', '02', 21000, 'qris', 'lunas', '2026-09-11 13:00:00'),
('TRX-023', 'Yuni Astuti', '09', 28000, 'qris', 'lunas', '2026-09-11 13:20:00'),
('TRX-024', 'Reza Pahlevi', '06', 22000, 'tunai', 'lunas', '2026-09-11 13:40:00'),
('TRX-025', 'Indah Permata', '10', 16000, 'qris', 'lunas', '2026-09-11 14:00:00'),
('TRX-026', 'Gilang Ramadhan', '13', 25000, 'tunai', 'lunas', '2026-09-12 11:40:00'),
('TRX-027', 'Widya Ningsih', '03', 19000, 'qris', 'lunas', '2026-09-12 12:15:00'),
('TRX-028', 'Wahyu Hidayat', '11', 23000, 'tunai', 'lunas', '2026-09-12 12:35:00'),
('TRX-029', 'Taufik Ismail', '01', 34000, 'debit', 'lunas', '2026-09-12 13:10:00'),
('TRX-030', 'Mega Utami', '05', 18000, 'qris', 'lunas', '2026-09-12 13:45:00');

INSERT INTO detail_transaksi (id_transaksi, id_menu, jumlah, harga_satuan, subtotal, catatan) VALUES
(1, 1, 1, 15000, 15000, 'Kuah dipisah'),
(1, 21, 1, 4000, 4000, 'Manis sedang'),
(2, 6, 1, 18000, 18000, 'Level 2 pedas'),
(2, 21, 1, 4000, 4000, 'Gula batu'),
(3, 13, 1, 13000, 13000, 'Banyakin sawi'),
(3, 21, 1, 4000, 4000, 'Tawar'),
(4, 16, 1, 17000, 17000, 'Pedas manis'),
(4, 30, 1, 8000, 8000, 'Hangat'),
(5, 11, 1, 18000, 18000, 'Jangan pakai seledri'),
(5, 10, 1, 3000, 3000, NULL),
(6, 7, 1, 22000, 22000, 'Keju banyakin'),
(7, 8, 1, 20000, 20000, 'Paha atas'),
(7, 21, 1, 4000, 4000, 'Es sedikit'),
(8, 3, 1, 28000, 28000, NULL),
(8, 4, 1, 5000, 5000, NULL),
(9, 14, 1, 17000, 17000, 'Tanpa mecin'),
(9, 21, 1, 4000, 4000, NULL),
(10, 18, 1, 20000, 20000, 'Udang banyakin'),
(10, 23, 1, 6000, 6000, 'Manis dingin'),
(11, 17, 1, 16000, 16000, 'Sedang'),
(11, 5, 1, 1000, 1000, NULL),
(12, 6, 1, 18000, 18000, 'Sambal dipisah'),
(12, 5, 1, 2000, 2000, NULL),
(13, 19, 1, 22000, 22000, 'Pedas banget'),
(13, 22, 1, 6000, 6000, 'Hangat kuku'),
(14, 1, 1, 15000, 15000, NULL),
(14, 5, 1, 2000, 2000, NULL),
(15, 32, 1, 14000, 14000, 'Saus sambal ekstra'),
(16, 12, 1, 16000, 16000, 'Kuah panas'),
(16, 28, 1, 5000, 5000, NULL),
(17, 6, 1, 18000, 18000, 'Level 1'),
(18, 2, 1, 20000, 20000, NULL),
(18, 21, 1, 4000, 4000, 'Es teh tawar'),
(19, 1, 1, 15000, 15000, 'Koya banyak'),
(19, 21, 1, 4000, 4000, NULL),
(20, 18, 1, 20000, 20000, 'Jangan pakai cumi'),
(20, 23, 1, 6000, 6000, NULL);