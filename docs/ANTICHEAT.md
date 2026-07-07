# Обход GameGuard — техническое описание

## Метод: DLL Hijacking + IAT Hooking

### Почему старый метод (CreateRemoteThread) не работал

GameGuard работает как kernel-level драйвер и хукает `NtCreateThreadEx`.
Любой вызов `CreateRemoteThread` + `LoadLibraryA` виден мгновенно:
- GG мониторит handle-операции к процессу L2
- GG сканирует список загруженных модулей через PEB
- GG проверяет байты системных DLL (ws2_32, wininet) на изменения

### Новый метод

```
Старый (детектируется):          Новый (обходит GG):

rebull2_injector.exe             Пользователь кладёт файлы в папку L2:
→ OpenProcess                      L2\version.dll   (наш прокси)
→ CreateRemoteThread               L2\rebull2.dll   (наш payload)
→ LoadLibraryA
→ inline JMP patch ws2_32       При запуске L2.exe:
                                   Windows грузит L2\version.dll ПЕРВОЙ
                                   (до GameGuard — он стартует позже)
                                   version.dll → грузит rebull2.dll
                                   rebull2.dll → ждёт CMD_START от UI
                                   После GG-инициализации → IAT hook
```

### DLL Hijacking — как работает

Windows ищет DLL по порядку:
1. Папка с exe-файлом ← **мы кладём сюда нашу version.dll**
2. System32
3. Windows
4. ...

`version.dll` — хороший кандидат: грузится при старте L2 для проверки версий DirectX, содержит всего 12 функций, все форвардятся на `System32\version.dll`.

### IAT Hooking — почему не inline patch

| | Inline patch | IAT hook |
|---|---|---|
| Что меняем | Байты `ws2_32.dll` | Указатели в IAT `L2.exe` |
| GG видит | ДА — сканирует байты ws2_32 | Реже — IAT L2.exe не первоочередная цель |
| ws2_32.dll | Повреждён | Нетронут |
| Откат | Сложно | Простая запись оригинального адреса |

### Тайминг хуков

rebull2.dll при загрузке **не ставит хуки сразу** — только запускает Pipe-сервер.
Хуки ставятся только после `CMD_START` от UI (когда пользователь нажимает Старт).
Это даёт GameGuard время завершить инициализацию.

### Что GG всё ещё может засечь

- Наша DLL в памяти (если GG сканирует все загруженные модули)
- Изменения в IAT L2.exe при активном сканировании
- Named Pipe с подозрительным именем

### Возможные улучшения (Фаза 3+)

- Скрыть DLL из PEB (обнуление записи в списке модулей)
- Рандомизация имени Pipe
- Шифрование строк в DLL (анти-строковый анализ)
- VEH (Vectored Exception Handler) hooking вместо IAT
