# GUCCI v2 — پنل 3x-ui روی Railway با اینباند نامحدود + TCP Proxy + Reality

این ریپازیتوری، 3x-ui (نسخه **v2.9.4**) را به همراه یک nginx reverse proxy روی Railway اجرا می‌کند:

- ✅ پنل وب، سابسکریپشن و اینباندهای VLESS/WebSocket همه از طریق **یک پورت واحد** (پورت لبه Railway)
- ✅ **اینباند نامحدود**: مسیرهای `/in1` تا `/in50` (قابل افزایش تا هر تعداد) هر کدام به یک پورت داخلی مجزا
- ✅ **TCP Proxy خام** برای VLESS (با پشتیبانی از **Reality** و SNI جعلی — مثل آموزش‌های ClawCloud)
- ✅ **مسیریابی دامنه اختصاصی**: هر دامنه/ساب‌دامنه می‌تواند آدرس اختصاصی یک اینباند باشد
- ✅ استتار کامل: ریشه دامنه صفحه سیاه، ساب با لینک اشتباه صفحه سیاه

---

## معماری و پورت‌ها

| سرویس | پورت داخلی | مسیر/نحوه دسترسی عمومی |
|---|---|---|
| پنل 3x-ui | 2053 (پشت nginx) | فقط `https://دامنه/gucci/` |
| سرویس سابسکریپشن | 443 (فقط loopback) | `https://دامنه/sub/{subId}` |
| ساب Clash | 443 (فقط loopback) | `https://دامنه/clash/{subId}` |
| اینباند اصلی VLESS/WS | 8080 | `https://دامنه/هرمسیر` (مثلاً `/cdn`) |
| اینباندهای اضافه | 8081 تا 8130 | `https://دامنه/in1` تا `https://دامنه/in50` |
| اینباند TCP خام (Reality) | 9090 | از طریق **Railway TCP Proxy** (دامنه+پورت جداگانه) |

فرمول کلی اینباندهای اضافه: مسیر `/inN` ↔ پورت داخلی `8080 + N`

> تعداد مسیرها با متغیر محیطی `INBOUND_COUNT` (پیش‌فرض 50) تغییر می‌کند. مثلاً `INBOUND_COUNT=100` بگذارید تا `/in1..in100` روی پورت‌های `8081..8180` ساخته شود. هیچ تغییری در فایل‌ها لازم نیست.

---

## مراحل دیپلوی

### ۱. در Railway
1. **New Project → Deploy from GitHub repo** و همین ریپازیتوری را انتخاب کنید
2. Railway به‌طور خودکار `Dockerfile` را تشخیص و بیلد می‌کند
3. بعد از اتمام دیپلوی: **Settings → Networking → Generate Domain**
4. یک **Volume** به مسیر `/etc/x-ui/` وصل کنید تا دیتابیس بعد از هر دیپلوی حفظ شود

### ۲. ورود به پنل
```
https://دامنه‌شما.up.railway.app/gucci/
```
یوزرنیم/پسورد پیش‌فرض: `admin/admin` — **فوراً تغییرش دهید.**

---

## ساخت اینباند VLESS + WebSocket (روی دامنه اصلی)

در پنل → Inbounds → Add Inbound:

| فیلد | مقدار |
|---|---|
| Protocol | VLESS |
| Listen Port | برای مسیرهای `/inN` دقیقاً پورت `8080+N` (مثلاً `/in7` → پورت `8087`) — برای اینباند اصلی `/cdn` پورت `8080` |
| Network | ws |
| Security (TLS) | none — TLS در لبه Railway تمام می‌شود |
| Path | هر مسیر دلخواه، مثلاً `/cdn` |

لینک کلاینت:
```
vless://UUID@دامنه.up.railway.app:443?encryption=none&security=tls&sni=دامنه.up.railway.app&fp=chrome&type=ws&host=دامنه.up.railway.app&path=%2Fcdn#MyConfig
```

> ⚠️ پورت اینباند باید دقیقاً با جدول بالا مطابقت داشته باشد؛ nginx بر اساس همان پورت‌ها مسیریابی می‌کند.

---

## 🆕 TCP Proxy + اینباند TCP خام (VLESS ساده یا Reality)

Railway برای هر سرویس **یک TCP Proxy** می‌دهد (Layer 4، بدون خاتمه TLS). این یعنی ترافیک **خام** به کانتینر شما می‌رسد — پس می‌توانید:

### حالت ۱: VLESS + Reality (توصیه می‌شود — مقاوم‌ترین حالت)
1. در Railway: **Settings → Networking → TCP Proxy → New TCP Proxy** و پورت داخلی را **9090** بگذارید. Railway یک دامنه+پورت مثل `shuttle.proxy.rlwy.net:12345` می‌دهد.
2. در پنل → Add Inbound:

| فیلد | مقدار |
|---|---|
| Protocol | VLESS |
| Listen Port | **9090** |
| Security | **reality** |
| uTLS / Fingerprint | chrome |
| SNI (Dest) | یکی از دامنه‌های جعلی معتبر (فهرست پایین) |
| Dest Address | همان دامنه SNI با پورت 443 (مثلاً `www.microsoft.com:443`) |

3. کلیدهای Private/Public Key و Short ID را پنل تولید می‌کند؛ در کانفیگ کلاینت وارد کنید.

لینک کلاینت:
```
vless://UUID@آدرس-tcp-proxy:پورت?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp#Reality
```

**فهرست دامنه‌های مناسب برای SNI جعلی (از آموزش‌های رایج):**
```
www.microsoft.com    www.apple.com       aws.amazon.com
www.bing.com         go.microsoft.com    cdn-dynmedia-1.microsoft.com
azure.microsoft.com  devblogs.microsoft.com  snap.licdn.com
catalog.gamepass.com amd.com             fpinit.itunes.apple.com
```

### حالت ۲: VLESS + TCP ساده (بدون رمزنگاری TLS)
همان اینباند پورت 9090 با `security=none`. ساده‌تر است ولی **خیلی راحت‌تر شناسایی می‌شود**؛ فقط برای تست یا وقتی Reality در کلاینت پشتیبانی نمی‌شود.

```
vless://UUID@آدرس-tcp-proxy:پورت?encryption=none&security=none&type=tcp#TCP
```

> 💡 اگر TCP Proxy را با پورت داخلی دیگری می‌خواهید، متغیر `TCP_INBOUND_PORT` را در Railway عوض کنید و اینباند پنل را هم روی همان پورت بسازید.

---

## 🆕 مسیریابی دامنه اختصاصی (HOST_ROUTES) — مثل ClawCloud، هر کانفیگ یک آدرس مجزا

اگر دامنه شخصی دارید و می‌خواهید هر ساب‌دامنه، آدرس اختصاصی یک اینباند باشد (بدون مسیر `/inN`):

1. در Railway دامنه(‌ها) را به سرویس اضافه کنید (**Settings → Networking → Custom Domain**) و DNS را طبق راهنمای Railway تنظیم کنید.
2. متغیر محیطی `HOST_ROUTES` را بسازید:
```
HOST_ROUTES=one.example.com:8081,two.example.com:8082
```
3. در پنل اینباندها را روی پورت‌های 8081 و 8082 بسازید.

حالا `https://one.example.com/...` مستقیماً به اینباند پورت 8081 می‌رسد (و به همین ترتیب بقیه). با هر بار تغییر `HOST_ROUTES` و Redeploy، مسیرها به‌روز می‌شوند.

---

## ❌ چرا Hysteria2 روی Railway کار نمی‌کند؟

- Hysteria2 فقط روی **UDP/QUIC** کار می‌کند و حالت TCP ندارد.
- Railway **هیچ UDP ورودی‌ای** ندارد (نه پورت عمومی، نه TCP Proxy — فقط TCP).

پس هیچ راهی برای Hysteria2 استاندارد روی Railway وجود ندارد. جایگزین‌ها:
- همین ترکیب **VLESS+Reality روی TCP Proxy** (نزدیک‌ترین تجربه به نودهای ClawCloud، با سرعت و مقاومت عالی)
- برای Hysteria2: پلتفرم‌هایی که پورت UDP می‌دهند (ClawCloud/Sealos مثل قبل) یا یک VPS ارزان

---

## مقاومت در برابر فیلترینگ

**انجام‌شده:**
- ✅ همه‌چیز (پنل، ساب و اینباندهای WS) روی 443/TLS با ظاهر HTTPS عادی
- ✅ VLESS+Reality روی TCP Proxy — بدون نیاز به گواهی، با SNI جعلی؛ عملاً غیرقابل تشخیص از ترافیک واقعی مایکروسافت/اپل/...
- ✅ پنل مخفی: ریشه صفحه سیاه، پنل روی پورت داخلی غیرمعمول و مسیر `/gucci/`
- ✅ ساب با لینک اشتباه → صفحه سیاه
- ✅ `fp=chrome` در لینک‌ها
- ✅ ۵۰ مسیر اینباند جایگزین (`/in1..in50`) — اگر مسیری بسته شد، سریع عوض کنید

**صداقت کامل:** هیچ پروکسی‌ای تضمین ۱۰۰٪ نمی‌دهد. اگر مسیری بسته شد:
1. مسیر WebSocket اینباند را عوض کنید (بدون تغییر پورت)
2. از یکی از مسیرهای `/inN` دیگر استفاده کنید
3. اینباند TCP خام را بین Reality/none جابه‌جا کنید یا SNI جعلی را عوض کنید

---

## متغیرهای محیطی (Railway → Variables)

| متغیر | پیش‌فرض | توضیح |
|---|---|---|
| `INBOUND_COUNT` | `50` | تعداد مسیرهای `/in1..inN` |
| `INBOUND_BASE_PORT` | `8080` | پورت پایه (مسیر N → پورت BASE+N) |
| `TCP_INBOUND_PORT` | `9090` | پورت داخلی برای TCP Proxy (اینbاند TCP خام) |
| `HOST_ROUTES` | (خالی) | `host1:port1,host2:port2` برای دامنه‌های اختصاصی |

## تست سریع

```bash
# پنل (فقط همین مسیر)
https://دامنه.up.railway.app/gucci/

# تست اینباند اصلی (باید Bad Request از Xray ببینید)
https://دامنه.up.railway.app/cdn

# تست ساب (با subId واقعی از پنل)
https://دامنه.up.railway.app/sub/{subId}

# تست TCP Proxy (بعد از ساخت اینباند 9090): کانفیگ کلاینت را با آدرس TCP Proxy تست کنید
```

## نکات مهم

- دیتابیس (`/etc/x-ui`) را حتماً روی **Volume** نگه دارید تا کاربران/اینباندها/subId بعد از دیپلوی پاک نشوند.
- با Custom Domain، متغیر `RAILWAY_PUBLIC_DOMAIN` خودکار دامنه شما را می‌گیرد و لینک ساب درست ساخته می‌شود.
- TCP Proxy فقط **یکی** در هر سرویس Railway ممکن است؛ برای چند آدرس TCP مجزا، یا از `HOST_ROUTES` استفاده کنید یا سرویس‌های Railway جداگانه بسازید.
