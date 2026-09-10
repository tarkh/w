---
title: w-keyboard
section: reference
order: 0
summary: Управление кольцом раскладок клавиатуры Wayland-сессии (XKB).
---

`w-keyboard` — Управление кольцом раскладок клавиатуры Wayland-сессии (XKB).

## Использование

```
Использование: w-keyboard <команда> [аргументы]

Info: Управление кольцом раскладок клавиатуры Wayland-сессии (XKB).

Команды:
  status [--porcelain]        Текущее кольцо (раскладка / вариант / параметры)
  list [--porcelain]          Список доступных раскладок (код + описание)
  variants <код> [--porcelain]    Список вариантов раскладки
  add <код[:вариант]>         Добавить раскладку в кольцо (сразу и постоянно)
  remove <код>                Убрать раскладку из кольца (минимум одна остаётся)
  set-toggle <grp:*>          Клавиша переключения (XKB grp:*; сразу и постоянно)
  set-default <код>           Сделать раскладку дефолтной при входе (в начало кольца)
  set-repeat <частота> <задержка> Автоповтор: повторов/с (1-100) + задержка в мс (100-2000)
  set-numlock <on|off>        Включать NumLock при входе
  help                        Показать эту справку

Кольцо хранится в: $FRAG   Каталог: $LST

Коды выхода: 0 успех · 1 ошибка выполнения/проверки · 2 ошибка вызова

Примеры:
  w-keyboard add de
  w-keyboard add us:dvorak
  w-keyboard remove ru
  w-keyboard set-toggle grp:ctrl_shift_toggle
  w-keyboard set-repeat 30 400
  w-keyboard set-numlock on
```

Эта страница генерируется из собственной справки команды (w-docs-refgen). Живая
версия того же текста на машине с W: `w-keyboard help`.
