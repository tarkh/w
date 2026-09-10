---
title: w-secureboot
section: reference
order: 0
summary: Настройка и управление Secure Boot (ключи sbctl + хеш Limine).
---

`w-secureboot` — Настройка и управление Secure Boot (ключи sbctl + хеш Limine).

## Использование

```
Использование: w-secureboot <команда>

Info: Настройка и управление Secure Boot (ключи sbctl + хеш Limine).

Команды:
  status [--porcelain]   Состояние setup-mode/занесения sbctl и подписанные файлы
  enable                 Включить Secure Boot: занести ключи + подписать Limine. В два
                          этапа — первый вызов заносит ключи и просит перезагрузку;
                          после неё запустите снова, чтобы переустановить авторазблокировку
                          диска TPM2 (PCR7 обновляется только на той перезагрузке, не сразу)
  disable                Выключить Secure Boot: снять разблокировку TPM2 + сбросить ключи (Setup Mode)
  setup                  Разовое включение: создать+занести ключи (Setup Mode) + подписать Limine, хеш
  sign                   Переподписать все отслеживаемые sbctl бинарники (после обновления Limine)
  reenroll               Заново занести хеш конфига Limine (после правки limine.conf)
  help                   Показать эту справку

Коды выхода:
  0 Успех   1 Ошибка выполнения   2 Ошибка вызова

Примеры:
  sudo w-secureboot enable
  w-secureboot status --porcelain
```

Эта страница генерируется из собственной справки команды (w-docs-refgen). Живая
версия того же текста на машине с W: `w-secureboot help`.
