---
title: w-dns
section: reference
order: 0
summary: Переключение DNS-провайдера и режима DNS-over-TLS (systemd-resolved).
---

`w-dns` — Переключение DNS-провайдера и режима DNS-over-TLS (systemd-resolved).

## Использование

```
Использование: w-dns <команда>

Info: Переключение DNS-провайдера и режима DNS-over-TLS (systemd-resolved).

Команды:
  status            Показать выбор + состояние резолвера (resolvectl status)
  list              Список доступных DoT-провайдеров из каталога (* = активный)
  provider <имя>    Сменить резолвер (напр. quad9 cloudflare mullvad adguard)
  on                DoT = opportunistic  (дефолт W; откатывается, если блокируется)
  strict            DoT = yes            (шифрование гарантировано; ломает captive)
  off               Системный дефолт: DNS по DHCP на линках (снять W-настройку)
  apply             Перегенерировать из $CONF (после ручной правки каталога)
  help              Показать эту справку

Каталог и выбор: $CONF   Сгенерированный результат: $DROPIN

Коды выхода:
  0  Успех   1  Ошибка выполнения   2  Ошибка вызова

Примеры:
  w-dns status
  sudo w-dns provider cloudflare
  sudo w-dns strict
```

Эта страница генерируется из собственной справки команды (w-docs-refgen). Живая
версия того же текста на машине с W: `w-dns help`.
