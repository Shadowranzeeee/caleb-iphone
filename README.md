# Caleb для iPhone

Офлайн-чат на SwiftUI для iPhone с iOS 17 и новее. Caleb скачивает Qwen2.5 1.5B Instruct Q4_K_M при первом открытии. Генерация идёт через llama.cpp на GPU телефона с Metal. Сообщения и модель хранятся в контейнере приложения.

## Собрать на Mac

1. Установи Xcode и выбери его как активный через настройки Xcode или xcode-select. Установи XcodeGen командой brew install xcodegen.
2. В терминале открой папку проекта и выполни bash build-ipa.sh. Скрипт скачает официальную сборку llama.cpp, проверит SHA-256 и создаст dist/Caleb-unsigned.ipa.
3. Для установки напрямую через Xcode выполни bash build-ipa.sh --project-only, открой Caleb.xcodeproj, выбери свой Personal Team в Signing & Capabilities и запусти проект на подключённом iPhone.

## Собрать с Windows через GitHub Actions

1. Помести содержимое этой папки в корень своего репозитория GitHub, включая .github/workflows/build-ipa.yml.
2. В репозитории открой **Actions → Build Caleb IPA → Run workflow**.
3. После успешной сборки скачай артефакт **Caleb-unsigned**. Внутри будет **Caleb-unsigned.ipa**. Для установки подпиши его через [AltStore Classic для Windows](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows). Бесплатную подпись нужно [обновлять каждые 7 дней](https://faq.altstore.io/altstore-classic/your-altstore).

## Проверить на iPhone 14

1. Открой Caleb и нажми «Скачать модель». Для файла понадобится около 1 ГБ свободного места.
2. Когда появится чат, включи авиарежим и отключи Wi‑Fi, если он остался включён. Отправь сообщение на русском и проверь, что ответ появляется постепенно.
3. Попроси длинный ответ, нажми «Стоп» и отправь следующее сообщение.
4. Закрой и открой приложение. Отправленные сообщения должны появиться из локальной истории. Удалить её можно через меню в правом верхнем углу.

Движок и модель предоставлены проектами [llama.cpp](https://github.com/ggml-org/llama.cpp/releases/tag/b12248) и [Qwen](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF).
