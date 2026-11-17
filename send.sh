#!/bin/bash

# 1. Подключаем внешний файл с ключом и ссылкой
CONFIG_FILE="config.env"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[ОШИБКА] Файл $CONFIG_FILE не найден!"
    echo "Создайте его и укажите API_KEY и TARGET_URL"
    exit 1
fi
source "$CONFIG_FILE"

# 2. Настройки гарантированной доставки
TIMEOUT_SEC=0.12          # 120 мс (жесткий лимит)
MAX_RETRIES=3             # Количество попыток
FAILED_QUEUE="failed_requests.log"  # Очередь на повторную отправку
SUCCESS_LOG="success.log"           # Журнал успешных доставок

PAYLOAD="{\"client_key\": \"${API_KEY}\"}"

# 3. Цикл отправки с попытками
for ((i=1; i<=MAX_RETRIES; i++)); do
    echo "[Попытка $i/$MAX_RETRIES] Отправка на $TARGET_URL..."
    
    # -s: тихий режим, -k: игнорировать SSL, -o /dev/null: НЕ скачивать тело ответа (экономит время!)
    # -w "%{http_code}": вывести только HTTP-код в конце
    HTTP_CODE=$(curl -s -k -X POST "$TARGET_URL" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        --max-time "$TIMEOUT_SEC" \
        --connect-timeout "$TIMEOUT_SEC" \
        -o /dev/null \
        -w "%{http_code}")
    
    if [[ "$HTTP_CODE" == "200" ]]; then
        echo "[УСПЕХ] Получен код: $HTTP_CODE"
        
        # Сохраняем факт успешной доставки (маскированный ключ + ссылка)
        SAFE_KEY="${API_KEY:0:4}***"
        echo "$(date -Iseconds) | OK | Key: $SAFE_KEY | URL: $TARGET_URL" >> "$SUCCESS_LOG"
        exit 0
        
    elif [[ "$HTTP_CODE" == "000" ]]; then
        echo "[ТАЙМАУТ] Превышено время ожидания (${TIMEOUT_SEC} с)"
    else
        echo "[ОШИБКА] Получен код: $HTTP_CODE"
    fi
    
    # Пауза 50 мс перед следующей попыткой
    if [[ $i -lt $MAX_RETRIES ]]; then
        sleep 0.05
    fi
done

# 4. Если все попытки исчерпаны, сохраняем в очередь для гарантированной доставки
echo "[СБОЙ] Все попытки исчерпаны. Запрос сохранен в $FAILED_QUEUE"
echo "$(date -Iseconds) | FAILED | URL: $TARGET_URL | Payload: $PAYLOAD" >> "$FAILED_QUEUE"
exit 1