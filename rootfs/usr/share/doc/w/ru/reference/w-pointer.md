---
title: w-pointer
section: reference
order: 0
summary: Настройки мыши, тачпада и жестов Wayland-сессии.
---

`w-pointer` — Настройки мыши, тачпада и жестов Wayland-сессии.

## Использование

```
Использование: w-pointer <команда> [аргументы]

Info: Настройки мыши, тачпада и жестов Wayland-сессии.

Команды:
  status [--porcelain]   Показать все настройки (+ есть ли тачпад)
  list [--porcelain]     Список активных указательных устройств (мышь / тачпад)
  get <ключ>             Напечатать одну настройку
  set <ключ> <значение>  Изменить одну настройку (сразу и постоянно)
  detect                 Пересканировать тачпады и запомнить имена их устройств
  reset [<область>|--all]  Вернуть дефолты (mouse | touchpad | gestures | cursor)
  keys                   Список задаваемых ключей с допустимыми значениями
  help                   Показать эту справку

Конфиг хранится в: $FRAG

Коды выхода: 0 успех · 1 ошибка выполнения/проверки · 2 ошибка вызова

Примеры:
  w-pointer set mouse.sensitivity 0.3
  w-pointer set touchpad.tap_to_click on
  w-pointer set gestures.workspace_fingers 4
  w-pointer set cursor.menu_timeout 0.1
  w-pointer reset touchpad
```

Эта страница генерируется из собственной справки команды (w-docs-refgen). Живая
версия того же текста на машине с W: `w-pointer help`.
