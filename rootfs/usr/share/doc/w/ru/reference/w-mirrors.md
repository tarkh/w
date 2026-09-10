---
title: w-mirrors
section: reference
order: 0
summary: Поддержание списка зеркал pacman свежим — ранжирование по расписанию или вручную.
---

`w-mirrors` — Поддержание списка зеркал pacman свежим — ранжирование по расписанию или вручную.

## Использование

```
Использование: w-mirrors <команда>

Info: Поддержание списка зеркал pacman свежим — ранжирование по расписанию или вручную.

Команды:
  status [--porcelain]  Политика, текущий список и когда он ранжировался (по умолчанию)
  check [--quiet]       Проверить начало списка; ненулевой код, если данных нет ни от кого
  rank [--scheduled]    Переранжировать список сейчас (--scheduled = точка входа таймера)
  set <ключ> <знач>     Изменить один ключ политики (список ключей ниже)
  enable | disable      Включить/выключить таймер периодического ранжирования
  apply                 Применить состояние таймера из конфига (для apply.sh --mirrors)
  help                  Показать эту справку

Источник политики: /etc/w/mirrors.conf поверх /usr/share/w/defaults/mirrors.conf
Ключи: COUNTRY PROTOCOL AGE SCORE COUNT THREADS CONNECT_TIMEOUT DOWNLOAD_TIMEOUT
       INTERVAL_DAYS SKIP_METERED   (`w-conf cat mirrors` покажет слитый результат)

Коды выхода:
  0  Успех   1  Ошибка выполнения   2  Ошибка вызова

Примеры:
  w-mirrors status
  sudo w-mirrors rank
  sudo w-mirrors set COUNTRY Germany
```

Эта страница генерируется из собственной справки команды (w-docs-refgen). Живая
версия того же текста на машине с W: `w-mirrors help`.
