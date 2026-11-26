# API cảnh báo khẩn cấp DEMO

Cho phép **module cảnh báo bên ngoài** (camera `roi_monitor`, hay bất cứ chương trình nào) gọi một địa chỉ để Viegrand **phát cảnh báo khẩn cấp tới các tài khoản do chủ dự án chỉ định**, và hỏi lại một địa chỉ khác để biết **người nhận đã bấm "Tôi đã nhận" chưa** (để tắt chuông). Có **hai endpoint**: `POST /api/alert/trigger` và `GET /api/alert/status`. Dành cho demo: không ai ngoài danh sách nhận được gì, và tính năng tắt hẳn nếu chưa đặt khoá.

## 1. Luồng

```
module cảnh báo ──POST──► /api/alert/trigger        (Vercel, kiểm khoá x-alert-key)
                              │  rpc demo_alert_fire  (service role)
                              ▼
                     Supabase: demo_alert_targets (danh sách tài khoản được phép)
                               demo_alerts        (nhật ký + chống gửi trùng)
                              │  notify_push(type = demo_alert)
                              ▼
                     Edge Function `push` ──FCM, ưu tiên cao──► máy của các tài khoản đã chỉ định
                                                              │ mở app → màn đỏ "Cảnh báo khẩn cấp"
                                                              │ bấm "Tôi đã nhận" → rpc ack_demo_alert (đăng nhập của chính người đó)
                                                              ▼
module cảnh báo ──GET──► /api/alert/status?event_id=...  →  {state:"acked"} → module tắt chuông
```

Module ở sau mạng nhà (không có địa chỉ công khai) nên **module hỏi (poll) mỗi ~2 giây**, không để máy chủ gọi ngược vào module.

Tại sao thiết kế thế này:

- **Danh sách người nhận nằm ở máy chủ**, bên gọi chỉ biết "nhãn" (`me`, `ba-noi`...). Khoá bị lộ thì kẻ xấu cũng không bắn được vào tài khoản khác, chỉ bắn được vào các tài khoản demo.
- **Dùng lại đường push sẵn có** (cùng Edge Function, cùng FCM, cùng bảng mã thiết bị như SOS), nên không cần dịch vụ mới.
- **Chống nhầm và chống dồn dập**: trùng `event_id` thì bỏ qua (module gọi lại khi mất mạng không làm đổ chuông hai lần); cùng nguồn và cùng loại cảnh báo trong 10 giây thì chặn.
- Giống SOS: **bỏ qua tuỳ chọn thông báo và giờ yên tĩnh** của người nhận. Tiêu đề luôn có chữ `[DEMO]` để không ai tưởng là cảnh báo thật.

## 2. Giao diện gọi

`POST https://<tên-miền-vercel>/api/alert/trigger`

Header: `x-alert-key: <khoá>` (hoặc `Authorization: Bearer <khoá>`), `Content-Type: application/json`.

| Trường | Bắt buộc | Ý nghĩa |
|---|---|---|
| `kind` | không (mặc định `danger`) | `fall` ngã, `danger` nguy hiểm, `sos` khẩn cấp chung, `test` thử |
| `message` | không | Nội dung ngắn hiện trong thông báo, tối đa 200 ký tự |
| `camera` | không | Tên camera / vị trí, tối đa 60 ký tự |
| `event_id` | nên có | Mã duy nhất của sự kiện (6–80 ký tự `A-Za-z0-9_.:-`). Gọi lại cùng mã không gửi lại. Bỏ trống thì máy chủ tự sinh (khi đó không chống trùng được) |
| `source` | không (mặc định `api`) | Tên module gọi, chữ thường/số/`_`/`-`, dùng để chặn bắn dồn |
| `targets` | không | Danh sách nhãn muốn gửi (tối đa 10). Bỏ trống = tất cả tài khoản đang bật |
| `dry_run` | không | `true`: chỉ cho biết sẽ gửi cho bao nhiêu người, không gửi |

Trả về:

| Mã | Ý nghĩa |
|---|---|
| 200 `{ok, id, recipients, labels, event_id}` | Đã gửi. `duplicate:true` nghĩa là `event_id` đã xử lý trước đó. `dry:true` nếu là chạy thử |
| 400 `{error}` | Sai nội dung: `bad_json`, `bad_kind`, `bad_source`, `bad_event_id`, `bad_message`, `bad_camera`, `bad_targets`, `bad_dry_run` |
| 401 | Thiếu hoặc sai khoá |
| 404 `no_target` | Không có tài khoản hợp lệ nào (nhãn sai, hoặc tất cả đang tắt) |
| 405 | Không phải POST |
| 429 `cooldown` | Cùng `source` + `kind` vừa gửi dưới 10 giây, thử lại sau `retry_after` giây |
| 502 `upstream` | Lỗi phía cơ sở dữ liệu |
| 503 `alert_disabled` | Máy chủ chưa đặt `ALERT_API_KEY` |

### Endpoint 2: hỏi đã nhận chưa

`GET https://<tên-miền-vercel>/api/alert/status?event_id=<event_id đã gửi>` với cùng header `x-alert-key`.

| Mã | Ý nghĩa |
|---|---|
| 200 `{ok, event_id, state, acked, acked_at, acked_by, recipients, created_at}` | `state` là `pending` (chưa ai nhận) hoặc `acked` (đã có người bấm nhận). `acked_by` là **nhãn** tài khoản của người nhận đầu tiên. `recipients` là số tài khoản được gửi tới |
| 400 `bad_event_id` | Thiếu hoặc sai `event_id` |
| 401 / 503 | Như endpoint 1 |
| 404 `not_found` | `event_id` chưa từng được gửi thành công |

Người đầu tiên bấm nhận được ghi nhận, những người còn lại thấy tên người đó. Nếu không ai đăng nhập trên máy hoặc tắt thông báo thì `state` ở `pending` mãi: module cần có thời gian chờ tối đa (khuyến nghị ~120 giây) rồi tự quyết.

Ví dụ gọi endpoint 1:

```powershell
curl.exe -X POST https://<tên-miền>/api/alert/trigger `
  -H "x-alert-key: $env:ALERT_API_KEY" -H "Content-Type: application/json" `
  -d '{\"kind\":\"fall\",\"message\":\"Phát hiện người ngã\",\"camera\":\"Phòng ngủ\",\"event_id\":\"cam1-0001\",\"dry_run\":true}'
```

Gọi từ Python (module `roi_monitor` khi trạng thái `DANGER` kéo dài):

```python
import os, time, requests

def send_alert(kind="danger", message="", camera="", event_id=None):
    r = requests.post(
        os.environ["ALERT_URL"],  # https://<tên-miền>/api/alert/trigger
        headers={"x-alert-key": os.environ["ALERT_API_KEY"]},
        json={"kind": kind, "message": message, "camera": camera, "source": "roi_monitor",
              "event_id": event_id or f"roi-{int(time.time())}"},
        timeout=8,
    )
    return r.status_code, r.json()

def is_acked(event_id):
    r = requests.get(
        os.environ["ALERT_URL"].replace("/trigger", "/status"),
        headers={"x-alert-key": os.environ["ALERT_API_KEY"]},
        params={"event_id": event_id}, timeout=8,
    )
    return r.status_code == 200 and r.json().get("acked") is True
```

**Client Python có sẵn** (nhánh ROI, thư mục `roi_monitor/` của checkout `viegrand_svthm`, chưa chạy với máy chủ thật): `alert_client.py` (`AlertClient.from_env()`, `.trigger(...)`, `.status(...)`, `AlertManager`), test `test_alert_client.py`. Bật bằng `python roi_monitor.py run --alert --camera-name "..."` (thêm `--alert-dry-run` để thử, cần đặt `ALERT_URL` và `ALERT_API_KEY`). Hiện module luôn gửi `kind: "danger"`, chỉ gửi khi DANGER kéo dài ≥ 5 giây, poll status mỗi 2 giây, quá 120 giây chưa ai nhận thì gửi event mới. Đã nhận rồi mà người vẫn nguy hiểm thì module im lặng cho tới khi hết nguy hiểm (chưa có "nhắc lại").

Khuyến nghị cho bên gọi: chỉ gọi khi `DANGER` kéo dài quá N giây (xem THIET_KE.md của `roi_monitor`, mục "Báo động"), dùng `event_id` cố định cho cùng một sự kiện để thử lại an toàn, và coi `429` là bình thường.

## 3. Cài đặt (chủ dự án làm một lần)

1. **Chạy migration** `supabase/migrations/0037_demo_alerts.sql` (gồm cả hàm nhận và hỏi trạng thái) trong SQL Editor của Supabase.
2. **Chỉ định tài khoản nhận** — cách dễ nhất (bản app mới): chạy thêm `supabase/migrations/0038_demo_alert_optin.sql`, rồi trên điện thoại vào **Hồ sơ → Thông báo → "Nhận cảnh báo thử nghiệm"** và bật. Công tắc tự thêm tài khoản đó vào danh sách, hiện **nhãn** (lấy từ tên đăng nhập, ví dụ `minh`) để đưa cho module nếu muốn gửi riêng bằng `targets`, và xin quyền thông báo luôn. Tắt công tắc thì ngừng nhận. Mỗi người chỉ bật/tắt được cho chính tài khoản của mình. Cách thủ công (không cần app mới): thay `tên_đăng_nhập` và nhãn cho đúng:
   ```sql
   insert into public.demo_alert_targets (label, user_id)
   select 'me', id from public.profiles where username = 'tên_đăng_nhập'
   on conflict (label) do update set user_id = excluded.user_id, enabled = true;
   ```
   Tắt một tài khoản: `update public.demo_alert_targets set enabled = false where label = 'me';`
   Xem danh sách: `select t.label, p.username, t.enabled from public.demo_alert_targets t join public.profiles p on p.id = t.user_id;`
3. **Đặt khoá** trong Vercel (Project → Settings → Environment Variables): `ALERT_API_KEY` = chuỗi ngẫu nhiên dài ít nhất 24 ký tự (ví dụ 40 ký tự hex). Nhiều khoá cách nhau dấu phẩy để xoay khoá. Redeploy.
4. **Triển khai lại Edge Function `push`** (để có nhánh `demo_alert`): `supabase functions deploy push`.
5. Tài khoản nhận phải **đã đăng nhập trên máy và cho phép thông báo** (mã thiết bị được lưu khi đăng nhập). Thử bằng `dry_run:true` để xem `recipients`, rồi gọi `kind:"test"`.

## 4. Phía app (bản mới sau b53, chưa phát hành)

- Đang mở app: nhận push `demo_alert` thì **tự bật màn đỏ** `/alert/:id` (`demo_alert_screen.dart`). App tắt hoặc chạy nền: hiện ở khay thông báo, bấm vào thì mở đúng màn đó.
- Màn đỏ có nút **Tôi đã nhận** (ghi `ack_demo_alert`), **Gọi cấp cứu 115** (chỉ mở bàn phím gọi, không tự gọi), và máy **rung lặp** cho tới khi có người nhận. Người khác nhận trước thì màn đổi sang xanh "đã có người nhận".
- Chỉ tài khoản nằm trong danh sách người nhận của đúng cảnh báo đó đọc và nhận được (kiểm ở cơ sở dữ liệu).

## 5. Giới hạn hiện tại

- Chưa có tiếng còi riêng: chỉ rung lặp, và âm thông báo mặc định của kênh `viegrand_default` khi app ở nền.
- Bản app cũ (≤ b53) không có màn này: vẫn nhận thông báo nhưng bấm vào chỉ mở app, và không nhận được.
- **Chưa thử trên máy thật.** Đã kiểm tra bằng test: kiểm khoá, kiểm nội dung, mã trả về của hai API (16 test), màn đỏ và nút nhận (Flutter test). Chưa chạy: migration trên cơ sở dữ liệu thật, nhánh `demo_alert` của Edge Function, FCM tới máy, việc app đang mở tự bật màn đỏ.
