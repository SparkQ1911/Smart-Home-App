-- Co so du lieu he thong nha thong minh (Nhom 29)
CREATE DATABASE IF NOT EXISTS nha_thong_minh
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE nha_thong_minh;

-- Bang nguoi dung: tai khoan dang nhap va phan quyen
CREATE TABLE nguoi_dung (
  id INT AUTO_INCREMENT PRIMARY KEY,
  ten_dang_nhap VARCHAR(254) NOT NULL UNIQUE,
  mat_khau VARCHAR(255) NOT NULL,          -- luu mat khau da ma hoa, khong luu chu thuong
  vai_tro VARCHAR(20) NOT NULL DEFAULT 'user',
  ten_hien_thi VARCHAR(60) NOT NULL DEFAULT ''
);

-- Bang thiet bi: moi thiet bi thuoc ve mot nguoi dung
CREATE TABLE thiet_bi (
  id INT AUTO_INCREMENT PRIMARY KEY,
  ten_thiet_bi VARCHAR(100) NOT NULL,
  loai VARCHAR(50) NOT NULL,
  trang_thai VARCHAR(10) NOT NULL DEFAULT 'OFF',
  ma_thiet_bi VARCHAR(64) NULL,
  phong VARCHAR(100) NOT NULL DEFAULT '',
  thu_tu INT NOT NULL DEFAULT 9999,
  nguoi_dung_id INT NOT NULL,
  UNIQUE KEY uq_thiet_bi_ma_thiet_bi (ma_thiet_bi),
  FOREIGN KEY (nguoi_dung_id) REFERENCES nguoi_dung(id)
);

-- Bang lich su bat/tat cua thiet bi
CREATE TABLE lich_su_trang_thai (
  id INT AUTO_INCREMENT PRIMARY KEY,
  thiet_bi_id INT NOT NULL,
  trang_thai VARCHAR(10) NOT NULL,
  hanh_dong VARCHAR(64) NOT NULL DEFAULT 'reported',
  chi_tiet_json LONGTEXT NULL,
  thoi_gian DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (thiet_bi_id) REFERENCES thiet_bi(id)
);

-- Bang du lieu cam bien (nhiet do, do am)
CREATE TABLE du_lieu_cam_bien (
  id INT AUTO_INCREMENT PRIMARY KEY,
  thiet_bi_id INT NOT NULL,
  nhiet_do DECIMAL(5,2),
  do_am DECIMAL(5,2),
  thoi_gian DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (thiet_bi_id) REFERENCES thiet_bi(id)
);
