import base64
import hashlib
import hmac
import json
import math
import os
import re
import secrets
import threading
import time
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

from mysql.connector import IntegrityError, Error as MySQLError
from mysql.connector.pooling import MySQLConnectionPool

if __package__:
    from .mqtt_bridge import BridgeUnavailableError, MqttBridge
else:
    from mqtt_bridge import BridgeUnavailableError, MqttBridge


PASSWORD_ITERATIONS = 600_000
TOKEN_LIFETIME_SECONDS = 30 * 24 * 60 * 60


class AccountExistsError(ValueError):
    pass


class PendingCommandError(ValueError):
    pass


def _b64url(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _hash_password(password, salt=None):
    salt = salt or secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, PASSWORD_ITERATIONS
    )
    return f"pbkdf2_sha256${PASSWORD_ITERATIONS}${_b64url(salt)}${_b64url(digest)}"


def _verify_password(password, encoded):
    try:
        algorithm, iterations, salt, expected = encoded.split("$")
        if algorithm != "pbkdf2_sha256":
            return False
        digest = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode("utf-8"),
            base64.urlsafe_b64decode(salt + "=" * (-len(salt) % 4)),
            int(iterations),
        )
        return hmac.compare_digest(_b64url(digest), expected)
    except (ValueError, TypeError):
        return False


def _public_user(user):
    return {key: user[key] for key in ("id", "name", "email")}


def _issue_token(user_id, secret):
    payload = _b64url(
        json.dumps(
            {"sub": user_id, "exp": int(time.time()) + TOKEN_LIFETIME_SECONDS},
            separators=(",", ":"),
        ).encode("utf-8")
    )
    signature = _b64url(
        hmac.new(secret, payload.encode("ascii"), hashlib.sha256).digest()
    )
    return f"{payload}.{signature}"


def _token_user_id(token, secret):
    try:
        payload, signature = token.split(".", 1)
        expected = _b64url(
            hmac.new(secret, payload.encode("ascii"), hashlib.sha256).digest()
        )
        if not hmac.compare_digest(signature, expected):
            return None
        decoded = base64.urlsafe_b64decode(
            payload + "=" * (-len(payload) % 4)
        )
        data = json.loads(decoded)
        if not isinstance(data, dict) or data.get("exp", 0) <= time.time():
            return None
        user_id = data.get("sub")
        return user_id if isinstance(user_id, str) else None
    except (ValueError, TypeError, json.JSONDecodeError):
        return None


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class SmartHomeStore:
    def __init__(self):
        self.lock = threading.RLock()
        self.devices = [
            {
                "id": "yellow",
                "name": "Đèn vàng",
                "type": "light",
                "status": "ON",
                "room": "Phòng khách",
            },
            {
                "id": "green",
                "name": "Đèn xanh lá",
                "type": "light",
                "status": "OFF",
                "room": "Phòng ngủ",
            },
            {
                "id": "red",
                "name": "Đèn đỏ",
                "type": "light",
                "status": "OFF",
                "room": "Phòng tắm",
            },
            {
                "id": "blue",
                "name": "Đèn xanh dương",
                "type": "light",
                "status": "OFF",
                "room": "Chưa phân loại",
            },
        ]
        self.rooms = []
        self.updated_at = None
        self.history = []
        self.users = {}
        self.commands = {}

    def health(self):
        return {"status": "ok", "storage": "memory"}

    def list_devices(self):
        with self.lock:
            return [dict(device) for device in self.devices]

    def get_device(self, device_id):
        with self.lock:
            device = next(
                (item for item in self.devices if item["id"] == device_id),
                None,
            )
            return dict(device) if device else None

    def get_latest_sensors(self):
        with self.lock:
            return {
                "rooms": [dict(room) for room in self.rooms],
                "updatedAt": self.updated_at,
            }

    def list_history(self):
        with self.lock:
            return [dict(entry) for entry in self.history]

    def publish_sensors(self, rooms, updated_at):
        with self.lock:
            self.rooms = rooms
            self.updated_at = updated_at

    def set_device_state(self, device_id, state):
        with self.lock:
            device = next(
                (item for item in self.devices if item["id"] == device_id),
                None,
            )
            if device is None:
                return None
            device["status"] = state
            self.record(f"turned_{state.lower()}", device=device)
            return dict(device)

    def enqueue_device_command(self, device_id, state):
        with self.lock:
            if not any(item["id"] == device_id for item in self.devices):
                return None
            self._expire_stale_commands(device_id)
            if any(
                command["deviceId"] == device_id
                and command["status"] == "pending"
                for command in self.commands.values()
            ):
                raise PendingCommandError("Thiết bị đang có một lệnh chờ xử lý.")
            command = {
                "id": str(uuid.uuid4()),
                "deviceId": device_id,
                "desiredState": state,
                "status": "pending",
                "createdAt": now_iso(),
                "reportedState": None,
                "reportedAt": None,
            }
            self.commands[command["id"]] = command
            return dict(command)

    def _expire_stale_commands(self, device_id):
        expiry = datetime.now(timezone.utc).timestamp() - 30
        for command in self.commands.values():
            if command["deviceId"] != device_id or command["status"] != "pending":
                continue
            created_at = datetime.fromisoformat(
                command["createdAt"].replace("Z", "+00:00")
            )
            if created_at.timestamp() < expiry:
                command["status"] = "expired"

    def get_pending_device_command(self, device_id):
        with self.lock:
            self._expire_stale_commands(device_id)
            pending = [
                command
                for command in self.commands.values()
                if command["deviceId"] == device_id
                and command["status"] == "pending"
            ]
            return dict(pending[0]) if pending else None

    def get_device_command(self, device_id, command_id):
        with self.lock:
            command = self.commands.get(command_id)
            if command is None or command["deviceId"] != device_id:
                return None
            return dict(command)

    def cancel_device_command(self, device_id, command_id):
        with self.lock:
            command = self.commands.get(command_id)
            if command is None or command["deviceId"] != device_id:
                return
            if command["status"] == "pending":
                command["status"] = "failed"

    def report_device_state(self, device_id, state, command_id=None):
        with self.lock:
            device = next(
                (item for item in self.devices if item["id"] == device_id),
                None,
            )
            if device is None:
                return None
            command = self.commands.get(command_id) if command_id else None
            if command_id and (
                command is None or command["deviceId"] != device_id
            ):
                return None
            previous_state = device["status"]
            device["status"] = state
            if command is not None and command["status"] == "pending":
                command["reportedState"] = state
                command["reportedAt"] = now_iso()
                command["status"] = (
                    "completed" if command["desiredState"] == state else "failed"
                )
            if previous_state != state:
                self.record(f"reported_{state.lower()}", device=device)
            return dict(device)

    def record(self, action, device=None, details=None):
        self.history.insert(
            0,
            {
                "id": f"{int(datetime.now().timestamp() * 1000)}-{len(self.history)}",
                "deviceId": device["id"] if device else None,
                "deviceName": device["name"] if device else None,
                "action": action,
                "details": details or {},
                "createdAt": now_iso(),
            },
        )
        del self.history[100:]

    def create_user(self, name, email, password):
        with self.lock:
            if any(user["email"] == email for user in self.users.values()):
                raise AccountExistsError("Email này đã được đăng ký.")
            user = {
                "id": str(uuid.uuid4()),
                "name": name,
                "email": email,
                "passwordHash": _hash_password(password),
                "createdAt": now_iso(),
            }
            self.users[user["id"]] = user
            return _public_user(user)

    def authenticate_user(self, email, password):
        with self.lock:
            user = next(
                (item for item in self.users.values() if item["email"] == email),
                None,
            )
            if user is None or not _verify_password(password, user["passwordHash"]):
                return None
            return _public_user(user)

    def get_user(self, user_id):
        with self.lock:
            user = self.users.get(user_id)
            return _public_user(user) if user else None

    def delete_user(self, user_id):
        with self.lock:
            return self.users.pop(user_id, None) is not None


class MySQLStore(SmartHomeStore):
    def __init__(self, connection_pool):
        super().__init__()
        self.connection_pool = connection_pool
        self._initialize_database()
        self._load_persistent_state()

    @contextmanager
    def _connection(self):
        connection = self.connection_pool.get_connection()
        try:
            yield connection
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    def _initialize_database(self):
        with self._connection() as connection:
            cursor = connection.cursor()
            try:
                for table in (
                    "nguoi_dung",
                    "thiet_bi",
                    "lich_su_trang_thai",
                    "du_lieu_cam_bien",
                ):
                    cursor.execute("SHOW TABLES LIKE %s", (table,))
                    if cursor.fetchone() is None:
                        raise RuntimeError(
                            "Thiếu bảng SQL trong tao_csdl.sql; hãy tạo database "
                            "bằng file này trước khi chạy server."
                        )

                migrations = {
                    "nguoi_dung": (
                        ("ten_hien_thi", "VARCHAR(60) NOT NULL DEFAULT ''"),
                    ),
                    "thiet_bi": (
                        ("ma_thiet_bi", "VARCHAR(64) NULL"),
                        ("phong", "VARCHAR(100) NOT NULL DEFAULT ''"),
                        ("thu_tu", "INT NOT NULL DEFAULT 9999"),
                    ),
                    "lich_su_trang_thai": (
                        ("hanh_dong", "VARCHAR(64) NOT NULL DEFAULT 'reported'"),
                        ("chi_tiet_json", "LONGTEXT NULL"),
                    ),
                }
                for table, columns in migrations.items():
                    for column, definition in columns:
                        cursor.execute(
                            f"SHOW COLUMNS FROM {table} LIKE %s", (column,)
                        )
                        if cursor.fetchone() is None:
                            cursor.execute(
                                f"ALTER TABLE {table} ADD COLUMN {column} {definition}"
                            )
                cursor.execute(
                    "SHOW COLUMNS FROM nguoi_dung LIKE %s", ("ten_dang_nhap",)
                )
                login_column = cursor.fetchone()
                login_type = (
                    login_column["Type"]
                    if isinstance(login_column, dict)
                    else login_column[1]
                )
                if login_type.lower() != "varchar(254)":
                    cursor.execute(
                        "ALTER TABLE nguoi_dung "
                        "MODIFY COLUMN ten_dang_nhap VARCHAR(254) NOT NULL"
                    )
                cursor.execute(
                    "SHOW INDEX FROM thiet_bi WHERE Key_name = %s",
                    ("uq_thiet_bi_ma_thiet_bi",),
                )
                if cursor.fetchone() is None:
                    cursor.execute(
                        "CREATE UNIQUE INDEX uq_thiet_bi_ma_thiet_bi "
                        "ON thiet_bi (ma_thiet_bi)"
                    )

                cursor.execute(
                    "SELECT id FROM nguoi_dung WHERE ten_dang_nhap = %s",
                    ("system@smart-home.local",),
                )
                system_user = cursor.fetchone()
                if system_user is None:
                    cursor.execute(
                        """
                        INSERT INTO nguoi_dung
                            (ten_dang_nhap, mat_khau, vai_tro, ten_hien_thi)
                        VALUES (%s, %s, 'system', %s)
                        """,
                        (
                            "system@smart-home.local",
                            _hash_password(secrets.token_urlsafe(32)),
                            "Smart Home System",
                        ),
                    )
                    system_user_id = cursor.lastrowid
                else:
                    system_user_id = (
                        system_user["id"]
                        if isinstance(system_user, dict)
                        else system_user[0]
                    )

                legacy_devices = [
                    ("living-light", "yellow", "Đèn vàng", "Phòng khách", 0),
                    ("kitchen-fan", "blue", "Đèn xanh dương", "Chưa phân loại", 1),
                    ("bedroom-ac", "green", "Đèn xanh lá", "Phòng ngủ", 2),
                    ("bathroom-light", "red", "Đèn đỏ", "Phòng tắm", 3),
                ]
                for old_id, new_id, name, room, order in legacy_devices:
                    cursor.execute(
                        """
                        SELECT id FROM thiet_bi
                        WHERE ma_thiet_bi = %s AND nguoi_dung_id = %s
                        """,
                        (old_id, system_user_id),
                    )
                    legacy = cursor.fetchone()
                    if legacy is None:
                        continue
                    legacy_row_id = legacy[0]
                    cursor.execute(
                        "SELECT id FROM thiet_bi WHERE ma_thiet_bi = %s",
                        (new_id,),
                    )
                    target = cursor.fetchone()
                    if target is None:
                        cursor.execute(
                            """
                            UPDATE thiet_bi
                            SET ma_thiet_bi = %s, ten_thiet_bi = %s, loai = 'light',
                                phong = %s, thu_tu = %s
                            WHERE id = %s
                            """,
                            (new_id, name, room, order, legacy_row_id),
                        )
                    else:
                        target_row_id = target[0]
                        cursor.execute(
                            "UPDATE lich_su_trang_thai SET thiet_bi_id = %s "
                            "WHERE thiet_bi_id = %s",
                            (target_row_id, legacy_row_id),
                        )
                        cursor.execute(
                            "UPDATE du_lieu_cam_bien SET thiet_bi_id = %s "
                            "WHERE thiet_bi_id = %s",
                            (target_row_id, legacy_row_id),
                        )
                        cursor.execute(
                            "DELETE FROM thiet_bi WHERE id = %s",
                            (legacy_row_id,),
                        )

                devices = [
                    (
                        "yellow",
                        "Đèn vàng",
                        "light",
                        "ON",
                        "Phòng khách",
                        0,
                    ),
                    (
                        "green",
                        "Đèn xanh lá",
                        "light",
                        "OFF",
                        "Phòng ngủ",
                        2,
                    ),
                    (
                        "red",
                        "Đèn đỏ",
                        "light",
                        "OFF",
                        "Phòng tắm",
                        3,
                    ),
                    (
                        "blue",
                        "Đèn xanh dương",
                        "light",
                        "OFF",
                        "Chưa phân loại",
                        1,
                    ),
                    (
                        "sensor-" + hashlib.sha256("Phòng khách".encode()).hexdigest()[:32],
                        "Cảm biến DHT22",
                        "sensor",
                        "OFF",
                        "Phòng khách",
                        10000,
                    ),
                ]
                cursor.executemany(
                    """
                    INSERT INTO thiet_bi
                        (ma_thiet_bi, ten_thiet_bi, loai, trang_thai,
                         phong, thu_tu, nguoi_dung_id)
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                    ON DUPLICATE KEY UPDATE
                        ten_thiet_bi = VALUES(ten_thiet_bi),
                        loai = VALUES(loai),
                        phong = VALUES(phong),
                        thu_tu = VALUES(thu_tu)
                    """,
                    [
                        (*device, system_user_id) for device in devices
                    ],
                )
                connection.commit()
            finally:
                cursor.close()

    def _load_persistent_state(self):
        with self._connection() as connection:
            cursor = connection.cursor(dictionary=True)
            try:
                cursor.execute(
                    """
                    SELECT ma_thiet_bi AS id, ten_thiet_bi AS name,
                           loai AS type, trang_thai AS status, phong AS room
                    FROM thiet_bi
                    WHERE ma_thiet_bi IS NOT NULL AND loai <> 'sensor'
                    ORDER BY thu_tu, id
                    """
                )
                self.devices = cursor.fetchall()
                cursor.execute(
                    """
                    SELECT sensor.phong AS room, reading.nhiet_do AS temperature,
                           reading.do_am AS humidity, reading.thoi_gian AS updated_at
                    FROM du_lieu_cam_bien AS reading
                    INNER JOIN thiet_bi AS sensor ON sensor.id = reading.thiet_bi_id
                    WHERE sensor.loai = 'sensor'
                      AND reading.id IN (
                          SELECT MAX(latest.id)
                          FROM du_lieu_cam_bien AS latest
                          GROUP BY latest.thiet_bi_id
                      )
                    ORDER BY reading.id
                    """
                )
                readings = cursor.fetchall()
                self.rooms = [
                    {
                        "room": item["room"],
                        "temperature": (
                            float(item["temperature"])
                            if item["temperature"] is not None
                            else None
                        ),
                        "humidity": (
                            float(item["humidity"])
                            if item["humidity"] is not None
                            else None
                        ),
                        "updatedAt": self._format_database_time(
                            item["updated_at"]
                        ),
                    }
                    for item in readings
                ]
                self.updated_at = (
                    max(
                        (
                            self._format_database_time(item["updated_at"])
                            for item in readings
                        ),
                        default=None,
                    )
                )
                cursor.execute(
                    """
                    SELECT history.id, device.ma_thiet_bi AS device_id,
                           device.ten_thiet_bi AS device_name,
                           history.trang_thai, history.hanh_dong,
                           history.chi_tiet_json, history.thoi_gian
                    FROM lich_su_trang_thai AS history
                    INNER JOIN thiet_bi AS device ON device.id = history.thiet_bi_id
                    ORDER BY history.thoi_gian DESC, history.id DESC
                    LIMIT 100
                    """
                )
                self.history = [
                    {
                        "id": str(item["id"]),
                        "deviceId": item["device_id"],
                        "deviceName": item["device_name"],
                        "status": item["trang_thai"],
                        "action": item["hanh_dong"],
                        "details": (
                            json.loads(item["chi_tiet_json"])
                            if item["chi_tiet_json"]
                            else {}
                        ),
                        "createdAt": self._format_database_time(
                            item["thoi_gian"]
                        ),
                    }
                    for item in cursor.fetchall()
                ]
            finally:
                cursor.close()

    @staticmethod
    def _format_database_time(value):
        if isinstance(value, datetime):
            if value.tzinfo is None:
                value = value.replace(tzinfo=timezone.utc)
            return value.isoformat(timespec="seconds")
        return str(value)

    @staticmethod
    def _parse_database_time(value):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except (AttributeError, ValueError) as error:
            raise ValueError("updatedAt phải là thời gian ISO-8601 hợp lệ.") from error
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc).replace(tzinfo=None)

    def health(self):
        with self._connection() as connection:
            cursor = connection.cursor()
            try:
                cursor.execute("SELECT 1")
                cursor.fetchone()
            finally:
                cursor.close()
        return {"status": "ok", "storage": "mysql"}

    def publish_sensors(self, rooms, updated_at):
        with self.lock, self._connection() as connection:
            cursor = connection.cursor(dictionary=True)
            try:
                for room in rooms:
                    sensor_key = "sensor-" + hashlib.sha256(
                        room["room"].encode("utf-8")
                    ).hexdigest()[:32]
                    cursor.execute(
                        """
                        SELECT id FROM thiet_bi
                        WHERE ma_thiet_bi = %s AND loai = 'sensor'
                        """,
                        (sensor_key,),
                    )
                    sensor = cursor.fetchone()
                    if sensor is None:
                        cursor.execute(
                            """
                            INSERT INTO thiet_bi
                                (ma_thiet_bi, ten_thiet_bi, loai, trang_thai,
                                 phong, thu_tu, nguoi_dung_id)
                            SELECT %s, %s, 'sensor', 'OFF', %s, 10000, id
                            FROM nguoi_dung
                            WHERE ten_dang_nhap = 'system@smart-home.local'
                            """,
                            (sensor_key, f"Cảm biến {room['room']}", room["room"]),
                        )
                        cursor.execute(
                            "SELECT id FROM thiet_bi WHERE ma_thiet_bi = %s",
                            (sensor_key,),
                        )
                        sensor = cursor.fetchone()
                    if sensor is None:
                        raise RuntimeError("Không thể tạo thiết bị cảm biến trong SQL.")
                    sensor_id = (
                        sensor["id"] if isinstance(sensor, dict) else sensor[0]
                    )
                    cursor.execute(
                        """
                        INSERT INTO du_lieu_cam_bien
                            (thiet_bi_id, nhiet_do, do_am, thoi_gian)
                        VALUES (%s, %s, %s, %s)
                        """,
                        (
                            sensor_id,
                            room.get("temperature"),
                            room.get("humidity"),
                            self._parse_database_time(updated_at),
                        ),
                    )
                connection.commit()
            finally:
                cursor.close()
            super().publish_sensors(rooms, updated_at)

    def _insert_history(self, cursor, action, device, details):
        created_at = now_iso()
        cursor.execute(
            "SELECT id FROM thiet_bi WHERE ma_thiet_bi = %s",
            (device["id"],),
        )
        db_device = cursor.fetchone()
        if db_device is None:
            raise RuntimeError("Không tìm thấy thiết bị để lưu lịch sử SQL.")
        db_device_id = (
            db_device["id"] if isinstance(db_device, dict) else db_device[0]
        )
        cursor.execute(
            """
            INSERT INTO lich_su_trang_thai
                (thiet_bi_id, trang_thai, hanh_dong, chi_tiet_json, thoi_gian)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (
                db_device_id,
                device["status"],
                action,
                json.dumps(details or {}, ensure_ascii=False),
                self._parse_database_time(created_at),
            ),
        )
        return {
            "id": cursor.lastrowid,
            "deviceId": device["id"],
            "deviceName": device["name"],
            "status": device["status"],
            "action": action,
            "details": details or {},
            "createdAt": created_at,
        }

    def _append_history(self, entry):
        if entry is not None:
            self.history.insert(0, entry)
            del self.history[100:]

    def record(self, action, device=None, details=None):
        if device is None:
            return super().record(action, device, details)
        with self.lock, self._connection() as connection:
            cursor = connection.cursor()
            try:
                entry = self._insert_history(cursor, action, device, details)
                connection.commit()
            finally:
                cursor.close()
            self._append_history(entry)

    def set_device_state(self, device_id, state):
        with self.lock:
            device = next(
                (item for item in self.devices if item["id"] == device_id),
                None,
            )
            if device is None:
                return None
            previous_state = device["status"]
            updated_device = {**device, "status": state}
            with self._connection() as connection:
                cursor = connection.cursor()
                try:
                    cursor.execute(
                        "UPDATE thiet_bi SET trang_thai = %s WHERE ma_thiet_bi = %s",
                        (state, device_id),
                    )
                    entry = (
                        self._insert_history(
                            cursor,
                            f"turned_{state.lower()}",
                            updated_device,
                            None,
                        )
                        if previous_state != state
                        else None
                    )
                    connection.commit()
                finally:
                    cursor.close()
            device["status"] = state
            self._append_history(entry)
            return dict(device)

    def report_device_state(self, device_id, state, command_id=None):
        with self.lock:
            device = next(
                (item for item in self.devices if item["id"] == device_id),
                None,
            )
            command = self.commands.get(command_id) if command_id else None
            if device is None or (
                command_id
                and (command is None or command["deviceId"] != device_id)
            ):
                return None
            previous_state = device["status"]
            updated_device = {**device, "status": state}
            with self._connection() as connection:
                cursor = connection.cursor()
                try:
                    cursor.execute(
                        "UPDATE thiet_bi SET trang_thai = %s WHERE ma_thiet_bi = %s",
                        (state, device_id),
                    )
                    entry = (
                        self._insert_history(
                            cursor,
                            f"reported_{state.lower()}",
                            updated_device,
                            None,
                        )
                        if previous_state != state
                        else None
                    )
                    connection.commit()
                finally:
                    cursor.close()
            device["status"] = state
            if command is not None and command["status"] == "pending":
                command["reportedState"] = state
                command["reportedAt"] = now_iso()
                command["status"] = (
                    "completed" if command["desiredState"] == state else "failed"
                )
            self._append_history(entry)
            return dict(device)

    def create_user(self, name, email, password):
        try:
            with self._connection() as connection:
                cursor = connection.cursor()
                try:
                    cursor.execute(
                        """
                        INSERT INTO nguoi_dung
                            (ten_dang_nhap, mat_khau, vai_tro, ten_hien_thi)
                        VALUES (%s, %s, 'user', %s)
                        """,
                        (
                            email,
                            _hash_password(password),
                            name,
                        ),
                    )
                    connection.commit()
                    user = {
                        "id": str(cursor.lastrowid),
                        "name": name,
                        "email": email,
                    }
                finally:
                    cursor.close()
        except IntegrityError as error:
            raise AccountExistsError("Email này đã được đăng ký.") from error
        return _public_user(user)

    def authenticate_user(self, email, password):
        with self._connection() as connection:
            cursor = connection.cursor(dictionary=True)
            try:
                cursor.execute(
                    """
                    SELECT id, ten_hien_thi AS name,
                           ten_dang_nhap AS email, mat_khau AS password_hash
                    FROM nguoi_dung
                    WHERE ten_dang_nhap = %s
                    """,
                    (email,),
                )
                user = cursor.fetchone()
            finally:
                cursor.close()
        if user is None or not _verify_password(password, user["password_hash"]):
            return None
        return _public_user({**user, "id": str(user["id"])})

    def get_user(self, user_id):
        with self._connection() as connection:
            cursor = connection.cursor(dictionary=True)
            try:
                cursor.execute(
                    """
                    SELECT id, ten_hien_thi AS name, ten_dang_nhap AS email
                    FROM nguoi_dung WHERE id = %s
                    """,
                    (self._user_id(user_id),),
                )
                user = cursor.fetchone()
            finally:
                cursor.close()
        return _public_user({**user, "id": str(user["id"])}) if user else None

    def delete_user(self, user_id):
        numeric_user_id = self._user_id(user_id)
        if numeric_user_id is None:
            return False
        with self._connection() as connection:
            cursor = connection.cursor()
            try:
                cursor.execute(
                    "DELETE FROM nguoi_dung WHERE id = %s", (numeric_user_id,)
                )
                deleted = cursor.rowcount > 0
                connection.commit()
                return deleted
            finally:
                cursor.close()

    @staticmethod
    def _user_id(user_id):
        try:
            return int(user_id)
        except (TypeError, ValueError):
            return None


def create_server(
    host="0.0.0.0",
    port=8080,
    store=None,
    auth_secret=None,
    device_key=None,
    mqtt_bridge=None,
):
    store = store or SmartHomeStore()
    auth_secret = auth_secret or os.environ.get("SMART_HOME_AUTH_SECRET")
    if not auth_secret or len(auth_secret) < 32:
        raise ValueError("SMART_HOME_AUTH_SECRET must contain at least 32 characters.")
    auth_secret = auth_secret.encode("utf-8")
    device_key = device_key or os.environ.get("SMART_HOME_DEVICE_KEY")
    if not device_key or len(device_key) < 32:
        raise ValueError("SMART_HOME_DEVICE_KEY must contain at least 32 characters.")
    device_key = device_key.encode("utf-8")

    class Handler(BaseHTTPRequestHandler):
        server_version = "SmartHomeSimulator/1.0"

        def _send_json(self, status, payload):
            body = json.dumps(payload, ensure_ascii=False, allow_nan=False).encode(
                "utf-8"
            )
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header(
                "Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS"
            )
            self.send_header(
                "Access-Control-Allow-Headers",
                "Content-Type, Accept, Authorization, X-Device-Key",
            )
            self.end_headers()
            self.wfile.write(body)

        def _read_json(self):
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError as error:
                raise ValueError("Content-Length không hợp lệ.") from error
            if length <= 0 or length > 65536:
                raise ValueError("Kích thước JSON phải từ 1 đến 65536 byte.")
            try:
                payload = json.loads(self.rfile.read(length))
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise ValueError("Request body phải là JSON hợp lệ.") from error
            if not isinstance(payload, dict):
                raise ValueError("Request JSON phải là object.")
            return payload

        def do_OPTIONS(self):
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header(
                "Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS"
            )
            self.send_header(
                "Access-Control-Allow-Headers",
                "Content-Type, Accept, Authorization, X-Device-Key",
            )
            self.send_header("Access-Control-Max-Age", "600")
            self.end_headers()

        def do_GET(self):
            try:
                self._handle_get()
            except MySQLError as error:
                print(f"Database request failed: {error}", flush=True)
                self._send_json(
                    503,
                    {"error": "Database unavailable; request was not completed."},
                )

        def _handle_get(self):
            path = urlparse(self.path).path.rstrip("/") or "/"
            if path == "/api/health":
                try:
                    storage = store.health()
                except MySQLError as error:
                    self._send_json(
                        503,
                        {"status": "error", "error": "Database unavailable."},
                    )
                    print(f"Health check failed: {error}", flush=True)
                    return
                self._send_json(
                    200,
                    {"server": self.server_version, **storage},
                )
                return
            if path == "/api/auth/me":
                user = self._authorized_user()
                if user is not None:
                    self._send_json(200, {"user": user})
                return
            parts = path.split("/")
            if (
                len(parts) == 7
                and parts[:4] == ["", "api", "iot", "devices"]
                and parts[5:] == ["commands", "pending"]
            ):
                if not self._authorized_device():
                    return
                command = store.get_pending_device_command(unquote(parts[4]))
                if command is None:
                    self._send_empty(204)
                else:
                    self._send_json(
                        200,
                        {
                            "commandId": command["id"],
                            "state": command["desiredState"],
                        },
                    )
                return
            if not self._authorized_user():
                return
            if path == "/api/devices":
                self._send_json(200, {"devices": store.list_devices()})
                return
            if path == "/api/sensors/latest":
                self._send_json(200, store.get_latest_sensors())
                return
            if path == "/api/history":
                self._send_json(200, {"history": store.list_history()})
                return
            parts = path.split("/")
            if (
                len(parts) == 6
                and parts[:3] == ["", "api", "devices"]
                and parts[4] == "commands"
            ):
                command = store.get_device_command(
                    unquote(parts[3]), unquote(parts[5])
                )
                if command is None:
                    self._send_json(404, {"error": "Không tìm thấy lệnh."})
                else:
                    self._send_json(200, command)
                return
            if len(parts) == 5 and parts[:3] == ["", "api", "devices"]:
                device_id = unquote(parts[3])
                if parts[4] == "status":
                    device = store.get_device(device_id)
                    if device is None:
                        self._send_json(404, {"error": "Không tìm thấy thiết bị."})
                    else:
                        self._send_json(200, {"status": device["status"]})
                    return
            self._send_json(404, {"error": "Không tìm thấy endpoint."})

        def do_POST(self):
            path = urlparse(self.path).path.rstrip("/")
            try:
                payload = self._read_json()
                if path == "/api/auth/register":
                    self._register(payload)
                    return
                if path == "/api/auth/login":
                    self._login(payload)
                    return
                if path == "/api/simulator/publish":
                    if not self._authorized_device():
                        return
                    self._publish(payload)
                    return
                parts = path.split("/")
                if (
                    len(parts) == 6
                    and parts[:4] == ["", "api", "iot", "devices"]
                    and parts[5] == "state"
                ):
                    if not self._authorized_device():
                        return
                    self._report_device_state(unquote(parts[4]), payload)
                    return
                if len(parts) == 5 and parts[:3] == ["", "api", "devices"] and parts[4] == "control":
                    if self._authorized_user() is None:
                        return
                    self._control(unquote(parts[3]), payload)
                    return
                self._send_json(404, {"error": "Không tìm thấy endpoint."})
            except AccountExistsError as error:
                self._send_json(409, {"error": str(error)})
            except PendingCommandError as error:
                self._send_json(409, {"error": str(error)})
            except ValueError as error:
                self._send_json(400, {"error": str(error)})
            except MySQLError as error:
                print(f"MySQL request failed: {error}", flush=True)
                self._send_json(
                    503,
                    {"error": "Database unavailable; request was not completed."},
                )
            except BridgeUnavailableError as error:
                self._send_json(503, {"error": str(error)})

        def _send_empty(self, status):
            self.send_response(status)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()

        def do_DELETE(self):
            path = urlparse(self.path).path.rstrip("/")
            if path != "/api/auth/me":
                self._send_json(404, {"error": "Không tìm thấy endpoint."})
                return
            try:
                payload = self._read_json()
                user = self._authorized_user()
                if user is None:
                    return
                password = payload.get("password")
                verified = (
                    store.authenticate_user(user["email"], password)
                    if isinstance(password, str)
                    else None
                )
                if verified is None or verified["id"] != user["id"]:
                    self._send_json(401, {"error": "Mật khẩu không đúng."})
                    return
                store.delete_user(user["id"])
                self._send_json(200, {"deleted": True})
            except ValueError as error:
                self._send_json(400, {"error": str(error)})
            except MySQLError as error:
                print(f"Account deletion failed: {error}", flush=True)
                self._send_json(
                    503,
                    {"error": "Database unavailable; account was not deleted."},
                )

        def _authorized_user(self):
            authorization = self.headers.get("Authorization", "")
            scheme, separator, token = authorization.partition(" ")
            user_id = (
                _token_user_id(token, auth_secret)
                if separator and scheme.lower() == "bearer"
                else None
            )
            user = store.get_user(user_id) if user_id else None
            if user is None:
                self._send_json(401, {"error": "Vui lòng đăng nhập để tiếp tục."})
            return user

        def _authorized_device(self):
            provided = self.headers.get("X-Device-Key", "").encode("utf-8")
            if not hmac.compare_digest(provided, device_key):
                self._send_json(401, {"error": "Thiết bị chưa được xác thực."})
                return False
            return True

        def _register(self, payload):
            name = payload.get("name")
            email = payload.get("email")
            password = payload.get("password")
            if not isinstance(name, str) or not name.strip() or len(name.strip()) > 60:
                raise ValueError("Tên hiển thị phải có từ 1 đến 60 ký tự.")
            if (
                not isinstance(email, str)
                or len(email) > 254
                or not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email.strip())
            ):
                raise ValueError("Email không hợp lệ.")
            if not isinstance(password, str) or not 8 <= len(password) <= 128:
                raise ValueError("Mật khẩu phải có từ 8 đến 128 ký tự.")
            user = store.create_user(
                name.strip(), email.strip().lower(), password
            )
            self._send_auth_response(user)

        def _login(self, payload):
            email = payload.get("email")
            password = payload.get("password")
            if (
                not isinstance(email, str)
                or len(email) > 254
                or not isinstance(password, str)
                or not 8 <= len(password) <= 128
            ):
                raise ValueError("Email và mật khẩu là bắt buộc.")
            user = store.authenticate_user(email.strip().lower(), password)
            if user is None:
                self._send_json(401, {"error": "Email hoặc mật khẩu không đúng."})
                return
            self._send_auth_response(user)

        def _send_auth_response(self, user):
            self._send_json(
                200,
                {"token": _issue_token(user["id"], auth_secret), "user": user},
            )

        def _publish(self, payload):
            rooms = payload.get("rooms")
            if not isinstance(rooms, list) or not rooms:
                raise ValueError("rooms phải là danh sách có ít nhất một phòng.")
            normalized = []
            updated_at = payload.get("updatedAt") or now_iso()
            if not isinstance(updated_at, str) or len(updated_at) > 40:
                raise ValueError("updatedAt phải là chuỗi thời gian ISO-8601.")
            for room in rooms:
                if not isinstance(room, dict):
                    raise ValueError("Mỗi phòng phải là một JSON object.")
                name = room.get("room") or room.get("area")
                if (
                    not isinstance(name, str)
                    or not name.strip()
                    or len(name.strip()) > 90
                ):
                    raise ValueError("Tên phòng phải có từ 1 đến 90 ký tự.")
                item = {"room": name.strip(), "updatedAt": updated_at}
                for field in ("temperature", "humidity"):
                    value = room.get(field)
                    if value is not None:
                        if isinstance(value, bool) or not isinstance(value, (int, float)):
                            raise ValueError(f"{field} phải là số.")
                        if not math.isfinite(value):
                            raise ValueError(f"{field} phải là số hữu hạn.")
                        item[field] = value
                for key, value in room.items():
                    if key not in {
                        "room",
                        "area",
                        "temperature",
                        "humidity",
                        "updatedAt",
                    }:
                        item[key] = value
                normalized.append(item)
            store.publish_sensors(normalized, updated_at)
            self._send_json(
                202,
                {
                    "accepted": True,
                    "rooms": len(normalized),
                    "updatedAt": updated_at,
                },
            )

        def _control(self, device_id, payload):
            state = payload.get("state", payload.get("status"))
            if isinstance(state, bool):
                state = "ON" if state else "OFF"
            if not isinstance(state, str) or state.upper() not in {"ON", "OFF"}:
                raise ValueError("state phải là ON hoặc OFF.")
            if mqtt_bridge is not None:
                command = store.enqueue_device_command(device_id, state.upper())
                if command is None:
                    self._send_json(404, {"error": "Không tìm thấy thiết bị."})
                    return
                try:
                    mqtt_bridge.publish_command(device_id, command["desiredState"])
                except BridgeUnavailableError:
                    store.cancel_device_command(device_id, command["id"])
                    raise
                self._send_json(
                    202,
                    {
                        "commandId": command["id"],
                        "status": "pending",
                        "desiredState": command["desiredState"],
                    },
                )
                return
            command = store.enqueue_device_command(device_id, state.upper())
            if command is None:
                self._send_json(404, {"error": "Không tìm thấy thiết bị."})
                return
            self._send_json(
                202,
                {
                    "commandId": command["id"],
                    "status": "pending",
                    "desiredState": command["desiredState"],
                },
            )

        def _report_device_state(self, device_id, payload):
            state = payload.get("state")
            command_id = payload.get("commandId")
            if not isinstance(state, str) or state.upper() not in {"ON", "OFF"}:
                raise ValueError("state phải là ON hoặc OFF.")
            if command_id is not None and not isinstance(command_id, str):
                raise ValueError("commandId không hợp lệ.")
            device = store.report_device_state(
                device_id,
                state.upper(),
                command_id,
            )
            if device is None:
                self._send_json(404, {"error": "Không tìm thấy thiết bị hoặc lệnh."})
                return
            self._send_json(200, {"status": device["status"]})

        def log_message(self, fmt, *args):
            print(f"{self.address_string()} - {fmt % args}", flush=True)

    class Server(ThreadingHTTPServer):
        daemon_threads = True
        allow_reuse_address = True

    return Server((host, port), Handler)


def main():
    host = os.environ.get("SMART_HOME_HOST", "0.0.0.0")
    port = int(os.environ.get("SMART_HOME_PORT", os.environ.get("PORT", "8080")))
    auth_secret = os.environ.get("SMART_HOME_AUTH_SECRET", "")
    if len(auth_secret) < 32:
        raise SystemExit(
            "SMART_HOME_AUTH_SECRET must contain at least 32 characters."
        )
    device_key = os.environ.get("SMART_HOME_DEVICE_KEY", "")
    if len(device_key) < 32:
        raise SystemExit(
            "SMART_HOME_DEVICE_KEY must contain at least 32 characters."
        )
    required = ("MYSQL_HOST", "MYSQL_DATABASE", "MYSQL_USER", "MYSQL_PASSWORD")
    missing = [key for key in required if not os.environ.get(key)]
    if missing:
        raise SystemExit(
            "Thiếu cấu hình MySQL: " + ", ".join(missing) + "."
        )
    pool = MySQLConnectionPool(
        pool_name="smart_home_api",
        pool_size=10,
        host=os.environ["MYSQL_HOST"],
        port=int(os.environ.get("MYSQL_PORT", "3306")),
        database=os.environ["MYSQL_DATABASE"],
        user=os.environ["MYSQL_USER"],
        password=os.environ["MYSQL_PASSWORD"],
        connection_timeout=5,
    )
    store = MySQLStore(pool)
    mqtt_bridge = MqttBridge.from_environment(store)
    if mqtt_bridge is None:
        print(
            "MQTT bridge is disabled; set MQTT_USERNAME and MQTT_PASSWORD to enable it.",
            flush=True,
        )
    else:
        mqtt_bridge.start()
    server = create_server(
        host, port, store, auth_secret, device_key, mqtt_bridge=mqtt_bridge
    )
    print(f"Smart Home API đang nghe tại http://{host}:{port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nĐang dừng Smart Home API...", flush=True)
    finally:
        server.server_close()
        if mqtt_bridge is not None:
            mqtt_bridge.stop()


if __name__ == "__main__":
    main()
