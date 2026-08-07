# GUCCI (s-ui edition) — پنل s-ui روی Railway با اینباند نامحدود + TCP Proxy + Reality

این ریپازیتوری، **s-ui v1.5.4** (پنل Sing-Box ساخته alireza0 — همون پنلی که در آموزش‌های ClawCloud استفاده می‌شد) را به همراه یک nginx reverse proxy روی Railway اجرا می‌کند:

- ✅ پنل وب روی `/app/`، سابسکریپشن روی `/sub/` — هر دو از طریق **یک پورت واحد** (لبه Railway)
- ✅ **اینباند نامحدود**: مسیرهای `/in1` تا `/in50` (قابل افزایش) هر کدام به یک پورت داخلی مجزا
- ✅ **TCP Proxy خام** برای اینباند TCP (پورت 9090) با پشتیبانی از **Reality** و SNI جعلی
- ✅ **مسیریابی دامنه اختصاصی** (`HOST_ROUTES`) — هر دامنه، آدرس اختصاصی یک اینباند
- ✅ استتار کامل: ریشه دامنه صفحه سیاه، ساب با توکن اشتباه صفحه سیاه
- ✅ دیتابیس روی Volume → بعد از هر دیپلوی همه‌چیز حفظ می‌شود

> نسخه قبلی (3x-ui / پنل سنایی) در تاریخچه گیت همچنان موجود است.

---

## معماری و پورت‌ها

| سرویس | پورت داخلی | مسیر/نحوه دسترسی عمومی |
|---|---|---|
| پنل s-ui | 2095 (پشت nginx) | فقط `https://دامنه/app/` |
| سرویس سابسکریپشن | 443 (فقط loopback، cert خودامضا) | `https://دامنه/sub/{token}` |
| اینباند اصلی | 8080 | `https://دامنه/هرمسیر` (مثلاً `/cdn`) |
| اینباندهای اضافه | 8081 تا 8130 | `https://دامنه/in1` تا `https://دامنه/in50` |
| اینباند TCP خام (Reality) | 9090 | از طریق **Railway TCP Proxy** |

فرمول: مسیر `/inN` ↔ پورت داخلی `8080 + N`

> تعداد مسیرها با `INBOUND_COUNT` (پیش‌فرض 50) قابل افزایش است — بدون تغییر فایل.

---

## مراحل دیپلوی در Railway

1. **New Project → Deploy from GitHub repo** و انتخاب همین ریپازیتوری
2. **Settings → Networking → Generate Domain**
3. یک **Volume** به مسیر `/app/db` وصل کنید (دیتابیس پنل)
4. (اختیاری) **TCP Proxy** بسازید با پورت داخلی `9090`
5. ورود به پنل: `https://دامنه.up.railway.app/app/` — یوزر/پسورد پیش‌فرض: `admin` / `admin` — **فوراً عوض کنید**

---

## ساخت اینباند VLESS + WebSocket (روی دامنه اصلی)

در پنل → **Inbounds → Add Inbound**:

| فیلد | مقدار |
|---|---|
| Type | VLESS |
| Listen Port | برای `/inN` دقیقاً `8080+N` — برای اینباند اصلی `8080` |
| Transport | ws |
| Path | همان مسیر nginx، مثلاً `/in7` |
| TLS | خیر (TLS در لبه Railway است) |

در تنظیمات کلاینت/لینک: آدرس = دامنه Railway، پورت = 443، TLS فعال، SNI = دامنه.

> نکته: در s-ui برای اینکه لینک کلاینت با دامنه و پورت 443 ساخته شود، در تنظیمات اینباند (Addrs) آدرس و پورت عمومی را وارد کنید یا لینک را دستی بسازید:
> ```
> vless://UUID@دامنه.up.railway.app:443?encryption=none&security=tls&sni=دامنه&fp=chrome&type=ws&host=دامنه&path=%2Fin7#MyConfig
> ```

---

## 🆕 TCP Proxy + اینباند TCP (Reality)

1. در Railway: **Settings → Networking → TCP Proxy** با پورت داخلی **9090**
2. در پنل → Inbounds → Add Inbound:

| فیلد | مقدار |
|---|---|
| Type | VLESS |
| Listen Port | **9090** |
| Network | tcp |
| TLS | **Reality** |
| SNI/Dest | یکی از: `www.microsoft.com` ، `www.apple.com` ، `aws.amazon.com` ، `www.bing.com` ، `azure.microsoft.com` |

3. کلیدها (Private/Public/ShortId) را پنل تولید می‌کند.

لینک کلاینت:
```
vless://UUID@آدرس-tcp-proxy:پورت?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp#Reality
```

> ⚠️ Hysteria2 (UDP) در پنل s-ui هم مثل بقیه پنل‌ها روی Railway **کار نمی‌کند** چون Railway هیچ UDP ورودی‌ای ندارد. برای Hysteria2 به پلتفرم UDP‌دار (ClawCloud/Sealos یا VPS) نیاز است.

---

## 🆕 مسیریابی دامنه اختصاصی (HOST_ROUTES)

متغیر محیطی:
```
HOST_ROUTES=one.example.com:8081,two.example.com:8082
```
دامنه‌ها را به‌عنوان Custom Domain در Railway اضافه کنید؛ هر دامنه مستقیم به اینباند پورت خودش می‌رسد.

---

## متغیرهای محیطی

| متغیر | پیش‌فرض | توضیح |
|---|---|---|
| `INBOUND_COUNT` | `50` | تعداد مسیرهای `/in1..inN` |
| `INBOUND_BASE_PORT` | `8080` | پورت پایه |
| `TCP_INBOUND_PORT` | `9090` | پورت اینباند TCP خام (هدف TCP Proxy) |
| `HOST_ROUTES` | (خالی) | `host:port,...` برای دامنه‌های اختصاصی |

## تست سریع

```
https://دامنه/app/            → پنل s-ui
https://دامنه/                → صفحه سیاه
https://دامنه/sub/{token}     → سابسکریپشن (توکن اشتباه → صفحه سیاه)
https://دامنه/in7/...         → اینباند 7 (پورت 8087)
```

## نکات

- دیتابیس در Volume مسیر `/app/db` نگه داشته شود.
- لینک ساب داینامیک است: با هر دامنه‌ای که پنل باز شود، لینک ساب همان دامنه را می‌گیرد.
- TCP Proxy در هر سرویس Railway فقط یکی است؛ برای آدرس‌های بیشتر از `HOST_ROUTES` یا مسیرهای `/inN` استفاده کنید.
