-- ============================================================
-- Hospital Database Management System
-- รายวิชา Database System Concepts
-- คณะเทคโนโลยีสารสนเทศ สถาบันเทคโนโลยีพระจอมเกล้าเจ้าคุณทหารลาดกระบัง
-- ------------------------------------------------------------
-- ทดสอบกับ SQLite 3.x เขียนด้วย SQL มาตรฐานเป็นหลัก
-- SQLite: ต้องเปิดการตรวจ Foreign Key ก่อนรัน (ตั้งต่อการเชื่อมต่อ)
--   PRAGMA foreign_keys = ON;
-- ============================================================

-- ล้างของเดิม (ทำให้รันสคริปต์ซ้ำได้): ลบตารางลูกก่อนตารางแม่
DROP VIEW  IF EXISTS v_appointment_detail;
DROP TABLE IF EXISTS PAYMENTS;
DROP TABLE IF EXISTS APPOINTMENTS;
DROP TABLE IF EXISTS DOCTOR_SCHEDULES;
DROP TABLE IF EXISTS DEPARTMENTS;
DROP TABLE IF EXISTS STAFFS;
DROP TABLE IF EXISTS PATIENTS;
DROP TABLE IF EXISTS BEDS_ROOMS;
DROP TABLE IF EXISTS WARDS;
DROP TABLE IF EXISTS BUILDINGS;
DROP TABLE IF EXISTS ROOM_TYPE;

-- ============================================================
-- 1) สร้างฐานข้อมูล (SQL-DDL)
-- ============================================================

-- ------------------------------------------------------------
-- [DDL 1] สร้างตาราง ROOM_TYPE
-- ------------------------------------------------------------
-- ตารางประเภทห้อง (ตารางแม่ ไม่มี Foreign Key)
CREATE TABLE ROOM_TYPE (
    room_type_id  INT           NOT NULL,
    type_name     VARCHAR(50)   NOT NULL,
    daily_rate    DECIMAL(10,2) NOT NULL,
    description   VARCHAR(255),
    PRIMARY KEY (room_type_id),
    UNIQUE (type_name),
    CHECK (daily_rate >= 0)
);

-- ------------------------------------------------------------
-- [DDL 2] สร้างตาราง BUILDINGS
-- ------------------------------------------------------------
-- ตารางอาคาร (ตารางแม่ ไม่มี Foreign Key)
CREATE TABLE BUILDINGS (
    building_id    INT          NOT NULL,
    building_name  VARCHAR(100) NOT NULL,
    location_zone  VARCHAR(50),
    PRIMARY KEY (building_id),
    UNIQUE (building_name)
);

-- ------------------------------------------------------------
-- [DDL 3] สร้างตาราง WARDS
-- ------------------------------------------------------------
-- ตารางหอผู้ป่วย: 1 อาคารมีได้หลายหอผู้ป่วย (1:N)
CREATE TABLE WARDS (
    ward_id       INT          NOT NULL,
    building_id   INT          NOT NULL,
    ward_name     VARCHAR(100) NOT NULL,
    floor_number  INT          NOT NULL,
    capacity      INT          NOT NULL,
    PRIMARY KEY (ward_id),
    FOREIGN KEY (building_id) REFERENCES BUILDINGS (building_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (capacity > 0)
);

-- ------------------------------------------------------------
-- [DDL 4] สร้างตาราง BEDS_ROOMS
-- ------------------------------------------------------------
-- ตารางเตียง: เชื่อมกับหอผู้ป่วย อาคาร และประเภทห้อง
CREATE TABLE BEDS_ROOMS (
    bed_id        INT         NOT NULL,
    ward_id       INT         NOT NULL,
    building_id   INT         NOT NULL,
    room_type_id  INT         NOT NULL,
    bed_number    VARCHAR(10) NOT NULL,
    status        VARCHAR(20) NOT NULL DEFAULT 'available',
    PRIMARY KEY (bed_id),
    UNIQUE (ward_id, bed_number),
    FOREIGN KEY (ward_id)      REFERENCES WARDS (ward_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (building_id)  REFERENCES BUILDINGS (building_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (room_type_id) REFERENCES ROOM_TYPE (room_type_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (status IN ('available', 'occupied', 'reserved', 'maintenance'))
);

-- ------------------------------------------------------------
-- [DDL 5] สร้างตาราง PATIENTS
-- ------------------------------------------------------------
-- ตารางผู้ป่วย: hn_id คือรหัสประจำตัวผู้ป่วย
CREATE TABLE PATIENTS (
    hn_id          INT          NOT NULL,
    firstname      VARCHAR(50)  NOT NULL,
    lastname       VARCHAR(50)  NOT NULL,
    email          VARCHAR(100) NOT NULL,
    password       VARCHAR(255) NOT NULL,
    phonenumber    VARCHAR(20)  NOT NULL,
    personal_id    VARCHAR(13)  NOT NULL,
    date_of_birth  DATE         NOT NULL,
    PRIMARY KEY (hn_id),
    UNIQUE (email),
    UNIQUE (personal_id)
);

-- ------------------------------------------------------------
-- [DDL 6] สร้างตาราง STAFFS
-- ------------------------------------------------------------
-- ตารางบุคลากร: แพทย์ พยาบาล เจ้าหน้าที่ต้อนรับ การเงิน และผู้ดูแลระบบ
CREATE TABLE STAFFS (
    staff_id            INT          NOT NULL,
    firstname           VARCHAR(50)  NOT NULL,
    lastname            VARCHAR(50)  NOT NULL,
    staff_username      VARCHAR(50)  NOT NULL,
    password            VARCHAR(255) NOT NULL,
    phonenumber         VARCHAR(20),
    role                VARCHAR(30)  NOT NULL,
    medical_license_no  VARCHAR(20),
    PRIMARY KEY (staff_id),
    UNIQUE (staff_username),
    UNIQUE (medical_license_no),
    CHECK (role IN ('doctor', 'nurse', 'receptionist', 'cashier', 'admin'))
);

-- ------------------------------------------------------------
-- [DDL 7] สร้างตาราง DEPARTMENTS
-- ------------------------------------------------------------
-- ตารางแผนก: 1 อาคารมีได้หลายแผนก (1:N)
CREATE TABLE DEPARTMENTS (
    department_id    INT          NOT NULL,
    department_name  VARCHAR(100) NOT NULL,
    building_id      INT          NOT NULL,
    phone_extension  VARCHAR(10),
    PRIMARY KEY (department_id),
    UNIQUE (department_name),
    FOREIGN KEY (building_id) REFERENCES BUILDINGS (building_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ------------------------------------------------------------
-- [DDL 8] สร้างตาราง DOCTOR_SCHEDULES
-- ------------------------------------------------------------
-- ตารางการปฏิบัติงานของแพทย์ในแต่ละแผนก
CREATE TABLE DOCTOR_SCHEDULES (
    schedule_id    INT  NOT NULL,
    staff_id       INT  NOT NULL,
    department_id  INT  NOT NULL,
    shift_date     DATE NOT NULL,
    start_time     TIME NOT NULL,
    end_time       TIME NOT NULL,
    PRIMARY KEY (schedule_id),
    UNIQUE (staff_id, shift_date, start_time),
    FOREIGN KEY (staff_id)      REFERENCES STAFFS (staff_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (department_id) REFERENCES DEPARTMENTS (department_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (end_time > start_time)
);

-- ------------------------------------------------------------
-- [DDL 9] สร้างตาราง APPOINTMENTS
-- ------------------------------------------------------------
-- ตารางการนัดหมายระหว่างผู้ป่วยกับแพทย์ (bed_id เว้นว่างได้)
CREATE TABLE APPOINTMENTS (
    appointment_id        INT         NOT NULL,
    hn_id                 INT         NOT NULL,
    bed_id                INT,
    schedule_id           INT         NOT NULL,
    staff_id              INT         NOT NULL,
    appointment_datetime  DATETIME    NOT NULL,
    status                VARCHAR(20) NOT NULL DEFAULT 'scheduled',
    PRIMARY KEY (appointment_id),
    FOREIGN KEY (hn_id)       REFERENCES PATIENTS (hn_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (bed_id)      REFERENCES BEDS_ROOMS (bed_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (schedule_id) REFERENCES DOCTOR_SCHEDULES (schedule_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (staff_id)    REFERENCES STAFFS (staff_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (status IN ('scheduled', 'confirmed', 'completed', 'cancelled', 'no_show'))
);

-- ------------------------------------------------------------
-- [DDL 10] สร้างตาราง PAYMENTS
-- ------------------------------------------------------------
-- ตารางการชำระเงิน: การนัดหมาย 1 รายการ มีการชำระเงิน 1 รายการ (1:1)
CREATE TABLE PAYMENTS (
    payment_id        INT           NOT NULL,
    appointment_id    INT           NOT NULL,
    amount            DECIMAL(10,2) NOT NULL,
    payment_datetime  DATETIME,
    payment_method    VARCHAR(20),
    billing_status    VARCHAR(20)   NOT NULL DEFAULT 'pending',
    PRIMARY KEY (payment_id),
    UNIQUE (appointment_id),
    FOREIGN KEY (appointment_id) REFERENCES APPOINTMENTS (appointment_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (amount >= 0),
    CHECK (payment_method IN ('cash', 'credit_card', 'promptpay', 'insurance')),
    CHECK (billing_status IN ('pending', 'paid', 'refunded', 'cancelled'))
);

-- ------------------------------------------------------------
-- [DDL 11] สร้าง Index
-- ------------------------------------------------------------
-- Index สำหรับคอลัมน์ที่ใช้ค้นหา/เชื่อมตารางบ่อย
CREATE INDEX idx_appointments_hn       ON APPOINTMENTS (hn_id);
CREATE INDEX idx_appointments_datetime ON APPOINTMENTS (appointment_datetime);
CREATE INDEX idx_schedules_shift_date  ON DOCTOR_SCHEDULES (shift_date);
CREATE INDEX idx_beds_status           ON BEDS_ROOMS (status);

-- ------------------------------------------------------------
-- [DDL 12] สร้าง View v_appointment_detail
-- ------------------------------------------------------------
-- View สรุปรายละเอียดการนัดหมาย (เชื่อม 6 ตารางไว้ล่วงหน้า)
CREATE VIEW v_appointment_detail AS
SELECT a.appointment_id,
       a.appointment_datetime,
       a.status          AS appointment_status,
       p.hn_id,
       p.firstname       AS patient_firstname,
       p.lastname        AS patient_lastname,
       s.firstname       AS doctor_firstname,
       s.lastname        AS doctor_lastname,
       d.department_name,
       b.building_name,
       a.bed_id
FROM APPOINTMENTS a
JOIN PATIENTS p          ON p.hn_id = a.hn_id
JOIN DOCTOR_SCHEDULES ds ON ds.schedule_id = a.schedule_id
JOIN STAFFS s            ON s.staff_id = a.staff_id
JOIN DEPARTMENTS d       ON d.department_id = ds.department_id
JOIN BUILDINGS b         ON b.building_id = d.building_id;

-- ============================================================
-- 2) ข้อมูลตัวอย่าง (INSERT)
-- ============================================================

-- ------------------------------------------------------------
-- [DATA 1] เพิ่มข้อมูล ROOM_TYPE (4 แถว)
-- ------------------------------------------------------------
INSERT INTO ROOM_TYPE (room_type_id, type_name, daily_rate, description) VALUES
(1, 'General Ward',      800.00, 'ห้องรวม เตียงมาตรฐาน'),
(2, 'Private Room',     3500.00, 'ห้องพิเศษเดี่ยว พร้อมห้องน้ำในตัว'),
(3, 'Semi-Private Room', 2200.00, 'ห้องพิเศษคู่ พักร่วมกัน 2 เตียง'),
(4, 'ICU',              9000.00, 'ห้องผู้ป่วยวิกฤต ดูแลใกล้ชิดตลอด 24 ชั่วโมง');

-- ------------------------------------------------------------
-- [DATA 2] เพิ่มข้อมูล BUILDINGS (3 แถว)
-- ------------------------------------------------------------
INSERT INTO BUILDINGS (building_id, building_name, location_zone) VALUES
(1, 'Main Building',         'North Zone'),
(2, 'Outpatient Building',   'East Zone'),
(3, 'Special Care Building', 'South Zone');

-- ------------------------------------------------------------
-- [DATA 3] เพิ่มข้อมูล WARDS (6 แถว)
-- ------------------------------------------------------------
INSERT INTO WARDS (ward_id, building_id, ward_name, floor_number, capacity) VALUES
(1, 1, 'General Medicine Ward', 3, 6),
(2, 1, 'Surgical Ward',         4, 6),
(3, 1, 'Pediatric Ward',        5, 4),
(4, 3, 'VIP Ward',              2, 3),
(5, 3, 'Intensive Care Unit',   1, 4),
(6, 3, 'Semi-Private Ward',     3, 4);

-- ------------------------------------------------------------
-- [DATA 4] เพิ่มข้อมูล BEDS_ROOMS (18 แถว)
-- ------------------------------------------------------------
INSERT INTO BEDS_ROOMS (bed_id, ward_id, building_id, room_type_id, bed_number, status) VALUES
(1,  1, 1, 1, 'G3-01',  'occupied'),
(2,  1, 1, 1, 'G3-02',  'available'),
(3,  1, 1, 1, 'G3-03',  'occupied'),
(4,  1, 1, 1, 'G3-04',  'available'),
(5,  2, 1, 1, 'S4-01',  'reserved'),
(6,  2, 1, 1, 'S4-02',  'available'),
(7,  2, 1, 1, 'S4-03',  'maintenance'),
(8,  3, 1, 1, 'P5-01',  'available'),
(9,  3, 1, 1, 'P5-02',  'occupied'),
(10, 4, 3, 2, 'V2-01',  'available'),
(11, 4, 3, 2, 'V2-02',  'available'),
(12, 4, 3, 2, 'V2-03',  'reserved'),
(13, 5, 3, 4, 'ICU-01', 'occupied'),
(14, 5, 3, 4, 'ICU-02', 'available'),
(15, 5, 3, 4, 'ICU-03', 'available'),
(16, 6, 3, 3, 'SP3-01', 'available'),
(17, 6, 3, 3, 'SP3-02', 'available'),
(18, 6, 3, 3, 'SP3-03', 'maintenance');

-- ------------------------------------------------------------
-- [DATA 5] เพิ่มข้อมูล PATIENTS (12 แถว)
-- ------------------------------------------------------------
-- ข้อมูลสมมติ: อีเมลใช้โดเมน example.com และรหัสผ่านเป็นค่าตัวอย่างแทนค่าแฮช
INSERT INTO PATIENTS (hn_id, firstname, lastname, email, password, phonenumber, personal_id, date_of_birth) VALUES
(1,  'สมชาย',     'ใจดี',      'somchai.j@example.com',   'hashed_pw_p01', '0810000001', '0000000000001', '1988-03-14'),
(2,  'สมหญิง',    'รักสุข',    'somying.r@example.com',   'hashed_pw_p02', '0810000002', '0000000000002', '1992-07-21'),
(3,  'ประเสริฐ',   'มั่นคง',    'prasert.m@example.com',   'hashed_pw_p03', '0810000003', '0000000000003', '1975-11-02'),
(4,  'วิภา',       'แก้วใส',    'wipa.k@example.com',      'hashed_pw_p04', '0810000004', '0000000000004', '2001-01-30'),
(5,  'ธนากร',     'สุขสันต์',   'thanakorn.s@example.com', 'hashed_pw_p05', '0810000005', '0000000000005', '1983-09-09'),
(6,  'นภัสสร',    'พงษ์ไทย',   'napassorn.p@example.com', 'hashed_pw_p06', '0810000006', '0000000000006', '1996-05-18'),
(7,  'กิตติพงษ์',  'ศรีสุวรรณ', 'kittipong.s@example.com', 'hashed_pw_p07', '0810000007', '0000000000007', '1969-12-25'),
(8,  'ปรียา',      'เจริญผล',   'preeya.c@example.com',    'hashed_pw_p08', '0810000008', '0000000000008', '1990-04-04'),
(9,  'ภูมิ',        'วงศ์ใหญ่',   'poom.w@example.com',      'hashed_pw_p09', '0810000009', '0000000000009', '2018-08-15'),
(10, 'ใบเตย',      'ทองดี',     'baitoey.t@example.com',   'hashed_pw_p10', '0810000010', '0000000000010', '2020-02-29'),
(11, 'อนุชา',      'บุญมี',     'anucha.b@example.com',    'hashed_pw_p11', '0810000011', '0000000000011', '1958-06-10'),
(12, 'รัตนา',      'สายสุวรรณ', 'rattana.s@example.com',   'hashed_pw_p12', '0810000012', '0000000000012', '1979-10-01');

-- ------------------------------------------------------------
-- [DATA 6] เพิ่มข้อมูล STAFFS (12 แถว)
-- ------------------------------------------------------------
INSERT INTO STAFFS (staff_id, firstname, lastname, staff_username, password, phonenumber, role, medical_license_no) VALUES
(1,  'วีระ',      'ศรีประเสริฐ', 'dr.weera',          'hashed_pw_s01', '0820000001', 'doctor',       'MD-10001'),
(2,  'อรอุมา',    'พิทักษ์',     'dr.ornuma',         'hashed_pw_s02', '0820000002', 'doctor',       'MD-10002'),
(3,  'ณัฐพล',     'เกียรติกุล',  'dr.nattapon',       'hashed_pw_s03', '0820000003', 'doctor',       'MD-10003'),
(4,  'ปวีณา',     'ลิขิต',       'dr.paweena',        'hashed_pw_s04', '0820000004', 'doctor',       'MD-10004'),
(5,  'สุรชัย',    'อินทร์แก้ว',  'dr.surachai',       'hashed_pw_s05', '0820000005', 'doctor',       'MD-10005'),
(6,  'มณีรัตน์',  'จันทร์เพ็ญ',  'dr.maneerat',       'hashed_pw_s06', '0820000006', 'doctor',       'MD-10006'),
(7,  'ศิริพร',    'ใจเย็น',      'nurse.siriporn',    'hashed_pw_s07', '0820000007', 'nurse',        'RN-20001'),
(8,  'กมล',       'ทองสุข',      'nurse.kamol',       'hashed_pw_s08', '0820000008', 'nurse',        'RN-20002'),
(9,  'พิมพ์ชนก',  'สุขใจ',       'nurse.pimchanok',   'hashed_pw_s09', '0820000009', 'nurse',        'RN-20003'),
(10, 'อารีรัตน์', 'มีสุข',       'reception.areerat', 'hashed_pw_s10', '0820000010', 'receptionist', NULL),
(11, 'ชัยวัฒน์',  'เก่งการ',     'cashier.chaiwat',   'hashed_pw_s11', '0820000011', 'cashier',      NULL),
(12, 'ธีรพงษ์',   'ผู้ดูแล',      'admin.theerapong',  'hashed_pw_s12', '0820000012', 'admin',        NULL);

-- ------------------------------------------------------------
-- [DATA 7] เพิ่มข้อมูล DEPARTMENTS (6 แถว)
-- ------------------------------------------------------------
INSERT INTO DEPARTMENTS (department_id, department_name, building_id, phone_extension) VALUES
(1, 'Internal Medicine', 2, '2101'),
(2, 'Pediatrics',        2, '2102'),
(3, 'Orthopedics',       2, '2103'),
(4, 'Cardiology',        2, '2104'),
(5, 'Surgery',           1, '1201'),
(6, 'Emergency',         1, '1000');

-- ------------------------------------------------------------
-- [DATA 8] เพิ่มข้อมูล DOCTOR_SCHEDULES (15 แถว)
-- ------------------------------------------------------------
INSERT INTO DOCTOR_SCHEDULES (schedule_id, staff_id, department_id, shift_date, start_time, end_time) VALUES
(1,  1, 1, '2026-10-12', '09:00:00', '12:00:00'),
(2,  1, 1, '2026-10-14', '13:00:00', '16:00:00'),
(3,  2, 2, '2026-10-12', '09:00:00', '12:00:00'),
(4,  2, 2, '2026-10-13', '13:00:00', '16:00:00'),
(5,  3, 3, '2026-10-13', '09:00:00', '12:00:00'),
(6,  3, 3, '2026-10-15', '09:00:00', '12:00:00'),
(7,  4, 4, '2026-10-14', '09:00:00', '12:00:00'),
(8,  4, 4, '2026-10-16', '13:00:00', '16:00:00'),
(9,  5, 5, '2026-10-12', '13:00:00', '16:00:00'),
(10, 5, 5, '2026-10-15', '13:00:00', '16:00:00'),
(11, 6, 6, '2026-10-12', '16:00:00', '23:00:00'),
(12, 6, 6, '2026-10-13', '16:00:00', '23:00:00'),
(13, 1, 1, '2026-10-09', '09:00:00', '12:00:00'),
(14, 2, 2, '2026-10-08', '09:00:00', '12:00:00'),
(15, 4, 4, '2026-10-09', '13:00:00', '16:00:00');

-- ------------------------------------------------------------
-- [DATA 9] เพิ่มข้อมูล APPOINTMENTS (20 แถว)
-- ------------------------------------------------------------
INSERT INTO APPOINTMENTS (appointment_id, hn_id, bed_id, schedule_id, staff_id, appointment_datetime, status) VALUES
(1,  1,  NULL, 13, 1, '2026-10-09 09:30:00', 'completed'),
(2,  3,  NULL, 13, 1, '2026-10-09 10:00:00', 'completed'),
(3,  5,  1,    13, 1, '2026-10-09 10:30:00', 'completed'),
(4,  4,  NULL, 13, 1, '2026-10-09 11:30:00', 'no_show'),
(5,  9,  NULL, 14, 2, '2026-10-08 09:15:00', 'completed'),
(6,  10, 9,    14, 2, '2026-10-08 10:00:00', 'completed'),
(7,  7,  NULL, 15, 4, '2026-10-09 13:30:00', 'completed'),
(8,  11, 13,   15, 4, '2026-10-09 14:00:00', 'completed'),
(9,  2,  3,    13, 1, '2026-10-09 11:00:00', 'completed'),
(10, 1,  NULL, 1,  1, '2026-10-12 09:30:00', 'confirmed'),
(11, 6,  NULL, 1,  1, '2026-10-12 10:00:00', 'scheduled'),
(12, 9,  NULL, 3,  2, '2026-10-12 10:00:00', 'scheduled'),
(13, 10, NULL, 4,  2, '2026-10-13 13:30:00', 'confirmed'),
(14, 12, NULL, 5,  3, '2026-10-13 09:30:00', 'confirmed'),
(15, 8,  NULL, 5,  3, '2026-10-13 10:00:00', 'scheduled'),
(16, 11, NULL, 7,  4, '2026-10-14 09:30:00', 'confirmed'),
(17, 7,  NULL, 7,  4, '2026-10-14 10:00:00', 'cancelled'),
(18, 3,  NULL, 9,  5, '2026-10-12 13:30:00', 'scheduled'),
(19, 12, 5,    10, 5, '2026-10-15 13:30:00', 'confirmed'),
(20, 4,  NULL, 2,  1, '2026-10-14 13:30:00', 'scheduled');

-- ------------------------------------------------------------
-- [DATA 10] เพิ่มข้อมูล PAYMENTS (13 แถว)
-- ------------------------------------------------------------
INSERT INTO PAYMENTS (payment_id, appointment_id, amount, payment_datetime, payment_method, billing_status) VALUES
(1,  1,  500.00,  '2026-10-09 10:15:00', 'cash',        'paid'),
(2,  2,  500.00,  '2026-10-09 10:40:00', 'promptpay',   'paid'),
(3,  3,  1300.00, '2026-10-09 12:00:00', 'credit_card', 'paid'),
(4,  5,  450.00,  '2026-10-08 09:50:00', 'cash',        'paid'),
(5,  6,  1250.00, NULL,                  NULL,          'pending'),
(6,  7,  1200.00, '2026-10-09 14:30:00', 'insurance',   'paid'),
(7,  8,  9500.00, NULL,                  NULL,          'pending'),
(8,  9,  1300.00, '2026-10-09 11:45:00', 'promptpay',   'paid'),
(9,  10, 500.00,  NULL,                  NULL,          'pending'),
(10, 11, 500.00,  NULL,                  NULL,          'pending'),
(11, 13, 450.00,  NULL,                  NULL,          'pending'),
(12, 16, 1200.00, NULL,                  NULL,          'pending'),
(13, 17, 500.00,  NULL,                  NULL,          'cancelled');

-- ============================================================
-- 3) คำสั่งทดสอบ ระดับง่าย
-- ============================================================

-- ------------------------------------------------------------
-- [EASY 1] แสดงข้อมูลผู้ป่วยทั้งหมด
-- ------------------------------------------------------------
-- แสดงข้อมูลผู้ป่วยทั้งหมด
SELECT hn_id, firstname, lastname, email, phonenumber, date_of_birth
FROM PATIENTS;

-- ------------------------------------------------------------
-- [EASY 2] ผู้ป่วยที่เกิดตั้งแต่ปี 2000
-- ------------------------------------------------------------
-- ผู้ป่วยที่เกิดตั้งแต่ปี 2000 เรียงจากเก่าไปใหม่
SELECT hn_id, firstname, lastname, date_of_birth
FROM PATIENTS
WHERE date_of_birth >= '2000-01-01'
ORDER BY date_of_birth;

-- ------------------------------------------------------------
-- [EASY 3] รายชื่อแพทย์
-- ------------------------------------------------------------
-- รายชื่อบุคลากรที่เป็นแพทย์
SELECT staff_id, firstname, lastname, medical_license_no
FROM STAFFS
WHERE role = 'doctor'
ORDER BY staff_id;

-- ------------------------------------------------------------
-- [EASY 4] นับจำนวนเตียงที่ว่าง
-- ------------------------------------------------------------
-- จำนวนเตียงที่ว่างอยู่ในขณะนี้
SELECT COUNT(*) AS available_beds
FROM BEDS_ROOMS
WHERE status = 'available';

-- ------------------------------------------------------------
-- [EASY 5] การนัดหมายของวันที่ 12 ต.ค. 2569
-- ------------------------------------------------------------
-- การนัดหมายทั้งหมดของวันที่ 12 ตุลาคม 2569
SELECT appointment_id, hn_id, appointment_datetime, status
FROM APPOINTMENTS
WHERE appointment_datetime BETWEEN '2026-10-12 00:00:00' AND '2026-10-12 23:59:59'
ORDER BY appointment_datetime;

-- ------------------------------------------------------------
-- [EASY 6] เพิ่มผู้ป่วยใหม่ (INSERT)
-- ------------------------------------------------------------
-- เพิ่มผู้ป่วยใหม่ 1 คน
INSERT INTO PATIENTS (hn_id, firstname, lastname, email, password, phonenumber, personal_id, date_of_birth)
VALUES (13, 'ทดสอบ', 'ระบบ', 'test.patient@example.com', 'hashed_pw_p13', '0810000013', '0000000000013', '1995-05-05');

-- ------------------------------------------------------------
-- [EASY 7] แก้ไขเบอร์โทรผู้ป่วย (UPDATE)
-- ------------------------------------------------------------
-- แก้ไขเบอร์โทรศัพท์ของผู้ป่วยรหัส 13
UPDATE PATIENTS
SET phonenumber = '0899999999'
WHERE hn_id = 13;

-- ------------------------------------------------------------
-- [EASY 8] ลบผู้ป่วยทดสอบ (DELETE)
-- ------------------------------------------------------------
-- ลบผู้ป่วยทดสอบที่เพิ่มไว้ในขั้นก่อนหน้า
DELETE FROM PATIENTS
WHERE hn_id = 13;

-- ------------------------------------------------------------
-- [EASY 9] แก้ไขโครงสร้างตาราง (ALTER TABLE)
-- ------------------------------------------------------------
-- สร้างตารางทดลอง เพิ่มคอลัมน์ภายหลัง ใส่ข้อมูล ดูผล แล้วลบทิ้ง
CREATE TABLE LAB_ROOMS (
    room_id    INT NOT NULL,
    room_name  VARCHAR(50),
    PRIMARY KEY (room_id)
);
ALTER TABLE LAB_ROOMS ADD COLUMN floor_number INT;
INSERT INTO LAB_ROOMS (room_id, room_name, floor_number) VALUES (1, 'Lab A', 2);
SELECT * FROM LAB_ROOMS;
DROP TABLE LAB_ROOMS;

-- ------------------------------------------------------------
-- [EASY 10] คัดลอกตารางด้วย CREATE TABLE ... AS SELECT
-- ------------------------------------------------------------
-- สร้างตารางสำรองข้อมูลผู้ป่วย นับแถว แล้วลบทิ้ง
CREATE TABLE PATIENTS_BACKUP AS
SELECT hn_id, firstname, lastname FROM PATIENTS;

SELECT COUNT(*) AS copied_rows FROM PATIENTS_BACKUP;

DROP TABLE PATIENTS_BACKUP;

-- ============================================================
-- 4) คำสั่งทดสอบ ระดับปานกลาง
-- ============================================================

-- ------------------------------------------------------------
-- [MEDIUM 1] รายการนัดหมายพร้อมชื่อผู้ป่วยและแพทย์
-- ------------------------------------------------------------
-- รายการนัดหมายพร้อมชื่อผู้ป่วยและชื่อแพทย์
SELECT a.appointment_id,
       p.firstname AS patient_firstname, p.lastname AS patient_lastname,
       s.firstname AS doctor_firstname,  s.lastname AS doctor_lastname,
       a.appointment_datetime, a.status
FROM APPOINTMENTS a
INNER JOIN PATIENTS p ON a.hn_id = p.hn_id
INNER JOIN STAFFS   s ON a.staff_id = s.staff_id
ORDER BY a.appointment_datetime;

-- ------------------------------------------------------------
-- [MEDIUM 2] นับการนัดหมายแยกตามสถานะ
-- ------------------------------------------------------------
-- จำนวนการนัดหมายในแต่ละสถานะ
SELECT status, COUNT(*) AS total
FROM APPOINTMENTS
GROUP BY status
ORDER BY total DESC;

-- ------------------------------------------------------------
-- [MEDIUM 3] จำนวนเวรของแต่ละแผนก (รวมแผนกที่ไม่มีเวร)
-- ------------------------------------------------------------
-- จำนวนเวรของแต่ละแผนก
SELECT d.department_name, COUNT(ds.schedule_id) AS shift_count
FROM DEPARTMENTS d
LEFT JOIN DOCTOR_SCHEDULES ds ON ds.department_id = d.department_id
GROUP BY d.department_id, d.department_name
ORDER BY shift_count DESC, d.department_name;

-- ------------------------------------------------------------
-- [MEDIUM 4] สรุปจำนวนเตียงของแต่ละหอผู้ป่วย
-- ------------------------------------------------------------
-- จำนวนเตียงทั้งหมดและเตียงว่างของแต่ละหอผู้ป่วย
SELECT w.ward_name, b.building_name, w.capacity,
       COUNT(br.bed_id) AS bed_count,
       SUM(CASE WHEN br.status = 'available' THEN 1 ELSE 0 END) AS available_beds
FROM WARDS w
JOIN BUILDINGS b ON b.building_id = w.building_id
LEFT JOIN BEDS_ROOMS br ON br.ward_id = w.ward_id
GROUP BY w.ward_id, w.ward_name, b.building_name, w.capacity
ORDER BY w.ward_id;

-- ------------------------------------------------------------
-- [MEDIUM 5] แพทย์ที่มีการนัดหมายตั้งแต่ 4 รายการ
-- ------------------------------------------------------------
-- แพทย์ที่มีการนัดหมายตั้งแต่ 4 รายการขึ้นไป
SELECT s.staff_id, s.firstname, s.lastname, COUNT(*) AS appointment_count
FROM STAFFS s
JOIN APPOINTMENTS a ON a.staff_id = s.staff_id
GROUP BY s.staff_id, s.firstname, s.lastname
HAVING COUNT(*) >= 4
ORDER BY appointment_count DESC;

-- ------------------------------------------------------------
-- [MEDIUM 6] สรุปยอดการชำระเงินตามสถานะ
-- ------------------------------------------------------------
-- ยอดรวมและค่าเฉลี่ยของการชำระเงินแยกตามสถานะ
SELECT billing_status,
       COUNT(*)    AS payment_count,
       SUM(amount) AS total_amount,
       AVG(amount) AS avg_amount
FROM PAYMENTS
GROUP BY billing_status
ORDER BY total_amount DESC;

-- ------------------------------------------------------------
-- [MEDIUM 7] การนัดหมายที่ยังไม่มีข้อมูลการชำระเงิน
-- ------------------------------------------------------------
-- การนัดหมายที่ยังไม่มีรายการชำระเงิน
SELECT a.appointment_id, a.appointment_datetime, a.status
FROM APPOINTMENTS a
LEFT JOIN PAYMENTS pay ON pay.appointment_id = a.appointment_id
WHERE pay.payment_id IS NULL
ORDER BY a.appointment_id;

-- ------------------------------------------------------------
-- [MEDIUM 8] บันทึกการชำระเงิน (UPDATE หลายคอลัมน์)
-- ------------------------------------------------------------
-- บันทึกว่าผู้ป่วยชำระเงินรายการที่ 5 แล้ว
UPDATE PAYMENTS
SET billing_status   = 'paid',
    payment_method   = 'cash',
    payment_datetime = '2026-10-11 12:30:00'
WHERE payment_id = 5
  AND billing_status = 'pending';

-- ------------------------------------------------------------
-- [MEDIUM 9] ทดสอบ Key Constraint: Primary Key ซ้ำ
-- ------------------------------------------------------------
-- คำสั่งนี้ตั้งใจให้เกิด error เพื่อทดสอบเงื่อนไขบังคับ ลบ -- ออกเมื่อต้องการรันทีละคำสั่ง
-- -- ทดสอบ: เพิ่มอาคารที่มีรหัสซ้ำกับของเดิม (ต้องถูกปฏิเสธ)
-- INSERT INTO BUILDINGS (building_id, building_name, location_zone)
-- VALUES (1, 'Duplicate Building', 'West Zone');

-- ------------------------------------------------------------
-- [MEDIUM 10] ทดสอบ Null Constraint: NOT NULL
-- ------------------------------------------------------------
-- คำสั่งนี้ตั้งใจให้เกิด error เพื่อทดสอบเงื่อนไขบังคับ ลบ -- ออกเมื่อต้องการรันทีละคำสั่ง
-- -- ทดสอบ: เพิ่มผู้ป่วยโดยไม่ระบุนามสกุล (ต้องถูกปฏิเสธ)
-- INSERT INTO PATIENTS (hn_id, firstname, lastname, email, password, phonenumber, personal_id, date_of_birth)
-- VALUES (14, 'ทดสอบ', NULL, 'null.test@example.com', 'hashed_pw_p14', '0810000014', '0000000000014', '1990-01-01');

-- ------------------------------------------------------------
-- [MEDIUM 11] ทดสอบ Referential Integrity: Foreign Key
-- ------------------------------------------------------------
-- คำสั่งนี้ตั้งใจให้เกิด error เพื่อทดสอบเงื่อนไขบังคับ ลบ -- ออกเมื่อต้องการรันทีละคำสั่ง
-- -- ทดสอบ: นัดหมายให้ผู้ป่วยที่ไม่มีอยู่จริง (ต้องถูกปฏิเสธ)
-- INSERT INTO APPOINTMENTS (appointment_id, hn_id, bed_id, schedule_id, staff_id, appointment_datetime, status)
-- VALUES (99, 999, NULL, 1, 1, '2026-10-20 09:00:00', 'scheduled');

-- ------------------------------------------------------------
-- [MEDIUM 12] ทดสอบ Domain Constraint: CHECK
-- ------------------------------------------------------------
-- คำสั่งนี้ตั้งใจให้เกิด error เพื่อทดสอบเงื่อนไขบังคับ ลบ -- ออกเมื่อต้องการรันทีละคำสั่ง
-- -- ทดสอบ: เพิ่มประเภทห้องที่ราคาติดลบ (ต้องถูกปฏิเสธ)
-- INSERT INTO ROOM_TYPE (room_type_id, type_name, daily_rate, description)
-- VALUES (9, 'Invalid Room', -100, 'ราคาติดลบ');

-- ============================================================
-- 5) คำสั่งทดสอบ ระดับซับซ้อน
-- ============================================================

-- ------------------------------------------------------------
-- [COMPLEX 1] นัดหมายที่กำลังจะถึงพร้อมแผนกและอาคาร (JOIN 6 ตาราง)
-- ------------------------------------------------------------
-- นัดหมายตั้งแต่ 12 ต.ค. 2569 พร้อมแผนก อาคาร และช่วงเวลาเวร
SELECT a.appointment_id, a.appointment_datetime,
       p.firstname AS patient, s.firstname AS doctor,
       d.department_name, b.building_name,
       ds.shift_date, ds.start_time, ds.end_time
FROM APPOINTMENTS a
JOIN PATIENTS p          ON p.hn_id = a.hn_id
JOIN DOCTOR_SCHEDULES ds ON ds.schedule_id = a.schedule_id
JOIN STAFFS s            ON s.staff_id = ds.staff_id
JOIN DEPARTMENTS d       ON d.department_id = ds.department_id
JOIN BUILDINGS b         ON b.building_id = d.building_id
WHERE a.appointment_datetime >= '2026-10-12 00:00:00'
  AND a.status IN ('scheduled', 'confirmed')
ORDER BY a.appointment_datetime;

-- ------------------------------------------------------------
-- [COMPLEX 2] รายรับที่ชำระแล้วของแต่ละแผนก (CTE)
-- ------------------------------------------------------------
-- รายรับเฉพาะรายการที่ชำระแล้ว แยกตามแผนก
WITH paid AS (
    SELECT appointment_id, amount
    FROM PAYMENTS
    WHERE billing_status = 'paid'
)
SELECT d.department_name,
       COUNT(paid.appointment_id) AS paid_appointments,
       SUM(paid.amount)           AS revenue
FROM paid
JOIN APPOINTMENTS a      ON a.appointment_id = paid.appointment_id
JOIN DOCTOR_SCHEDULES ds ON ds.schedule_id = a.schedule_id
JOIN DEPARTMENTS d       ON d.department_id = ds.department_id
GROUP BY d.department_id, d.department_name
ORDER BY revenue DESC;

-- ------------------------------------------------------------
-- [COMPLEX 3] ผู้ป่วยที่ยอดค่าใช้จ่ายสูงกว่าค่าเฉลี่ย
-- ------------------------------------------------------------
-- ผู้ป่วยที่ยอดรวมของใบชำระเงินสูงกว่าค่าเฉลี่ยของทุกใบ
SELECT p.hn_id, p.firstname, p.lastname, SUM(pay.amount) AS total_billed
FROM PATIENTS p
JOIN APPOINTMENTS a ON a.hn_id = p.hn_id
JOIN PAYMENTS pay   ON pay.appointment_id = a.appointment_id
GROUP BY p.hn_id, p.firstname, p.lastname
HAVING SUM(pay.amount) > (SELECT AVG(amount) FROM PAYMENTS)
ORDER BY total_billed DESC;

-- ------------------------------------------------------------
-- [COMPLEX 4] จัดอันดับแพทย์ตามจำนวนนัดหมาย (Window Function)
-- ------------------------------------------------------------
-- จัดอันดับแพทย์ตามจำนวนการนัดหมาย (ยอดเท่ากันได้อันดับเดียวกัน)
SELECT s.staff_id, s.firstname, s.lastname,
       COUNT(a.appointment_id) AS appointment_count,
       RANK() OVER (ORDER BY COUNT(a.appointment_id) DESC) AS rank_no
FROM STAFFS s
LEFT JOIN APPOINTMENTS a ON a.staff_id = s.staff_id
WHERE s.role = 'doctor'
GROUP BY s.staff_id, s.firstname, s.lastname
ORDER BY rank_no, s.staff_id;

-- ------------------------------------------------------------
-- [COMPLEX 5] ตรวจหาเวรของแพทย์ที่เวลาซ้อนทับกัน (Self Join)
-- ------------------------------------------------------------
-- เวรของแพทย์คนเดียวกัน วันเดียวกัน ที่เวลาทับซ้อนกัน (ควรไม่พบ)
SELECT s1.schedule_id AS schedule_a,
       s2.schedule_id AS schedule_b,
       s1.staff_id, s1.shift_date
FROM DOCTOR_SCHEDULES s1
JOIN DOCTOR_SCHEDULES s2
  ON  s1.staff_id    = s2.staff_id
  AND s1.shift_date  = s2.shift_date
  AND s1.schedule_id < s2.schedule_id
WHERE s1.start_time < s2.end_time
  AND s2.start_time < s1.end_time;

-- ------------------------------------------------------------
-- [COMPLEX 6] แพทย์ที่ยังไม่มีการนัดหมายเลย (NOT EXISTS)
-- ------------------------------------------------------------
-- แพทย์ที่ยังไม่มีการนัดหมายเลย
SELECT s.staff_id, s.firstname, s.lastname
FROM STAFFS s
WHERE s.role = 'doctor'
  AND NOT EXISTS (
      SELECT 1
      FROM APPOINTMENTS a
      WHERE a.staff_id = s.staff_id
  );

-- ------------------------------------------------------------
-- [COMPLEX 7] ตรวจความถูกต้องของข้อมูลทั้งระบบ (UNION ALL)
-- ------------------------------------------------------------
-- ตรวจความสอดคล้องของข้อมูล: ผลทุกบรรทัดควรเป็น 0
SELECT 'appointment_staff_mismatch' AS check_name, COUNT(*) AS violations
FROM APPOINTMENTS a
JOIN DOCTOR_SCHEDULES ds ON ds.schedule_id = a.schedule_id
WHERE a.staff_id <> ds.staff_id
UNION ALL
SELECT 'appointment_outside_shift', COUNT(*)
FROM APPOINTMENTS a
JOIN DOCTOR_SCHEDULES ds ON ds.schedule_id = a.schedule_id
WHERE DATE(a.appointment_datetime) <> ds.shift_date
   OR TIME(a.appointment_datetime) <  ds.start_time
   OR TIME(a.appointment_datetime) >= ds.end_time
UNION ALL
SELECT 'bed_building_mismatch', COUNT(*)
FROM BEDS_ROOMS br
JOIN WARDS w ON w.ward_id = br.ward_id
WHERE br.building_id <> w.building_id
UNION ALL
SELECT 'ward_over_capacity', COUNT(*)
FROM (
    SELECT w.ward_id
    FROM WARDS w
    JOIN BEDS_ROOMS br ON br.ward_id = w.ward_id
    GROUP BY w.ward_id, w.capacity
    HAVING COUNT(br.bed_id) > w.capacity
) AS over_capacity;

-- ------------------------------------------------------------
-- [COMPLEX 8] สร้างใบชำระเงินที่ขาดให้อัตโนมัติ (INSERT ... SELECT)
-- ------------------------------------------------------------
-- สร้างใบชำระเงินสถานะ pending ให้นัดหมายที่ยังไม่มีใบชำระเงิน
INSERT INTO PAYMENTS (payment_id, appointment_id, amount, billing_status)
SELECT (SELECT MAX(payment_id) FROM PAYMENTS)
           + ROW_NUMBER() OVER (ORDER BY a.appointment_id),
       a.appointment_id,
       500.00,
       'pending'
FROM APPOINTMENTS a
LEFT JOIN PAYMENTS pay ON pay.appointment_id = a.appointment_id
WHERE pay.payment_id IS NULL
  AND a.status IN ('scheduled', 'confirmed');

SELECT payment_id, appointment_id, amount, billing_status
FROM PAYMENTS
ORDER BY payment_id;

-- ------------------------------------------------------------
-- [COMPLEX 9] จองเตียงให้การนัดหมาย (Transaction)
-- ------------------------------------------------------------
-- จองเตียง 2 ให้การนัดหมายที่ 11 โดยแก้ 2 ตารางพร้อมกัน
BEGIN;
UPDATE BEDS_ROOMS
SET status = 'reserved'
WHERE bed_id = 2 AND status = 'available';

UPDATE APPOINTMENTS
SET bed_id = 2, status = 'confirmed'
WHERE appointment_id = 11;
COMMIT;

SELECT a.appointment_id, a.bed_id, a.status AS appointment_status,
       b.bed_number, b.status AS bed_status
FROM APPOINTMENTS a
JOIN BEDS_ROOMS b ON b.bed_id = a.bed_id
WHERE a.appointment_id = 11;

-- ------------------------------------------------------------
-- [COMPLEX 10] สรุปการนัดหมายรายแผนกจาก View
-- ------------------------------------------------------------
-- สรุปการนัดหมายของแต่ละแผนกโดยใช้ View
SELECT department_name, building_name,
       COUNT(*) AS total_appointments,
       SUM(CASE WHEN appointment_status = 'completed' THEN 1 ELSE 0 END) AS completed,
       SUM(CASE WHEN appointment_status IN ('scheduled', 'confirmed') THEN 1 ELSE 0 END) AS upcoming
FROM v_appointment_detail
GROUP BY department_name, building_name
ORDER BY total_appointments DESC, department_name;
