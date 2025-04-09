#!/bin/bash

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Проверка root-доступа
if [ "$(id -u)" != "0" ]; then
    echo -e "${YELLOW}This script requires root access.${NC}"
    echo -e "${YELLOW}Please enter root mode using 'sudo -i', then rerun this script.${NC}"
    exec sudo -i
    exit 1
fi

# Пути
KEYS_FILE="/root/TNT/keys.txt"

# Проверка файла с ключами
if [ ! -f "$KEYS_FILE" ]; then
    echo -e "${YELLOW}keys.txt not found at $KEYS_FILE. Please create it first.${NC}"
    exit 1
fi

# Чтение ключей из файла
mapfile -t identity_keys < "$KEYS_FILE"

# Проверка количества ключей
if [ "${#identity_keys[@]}" -lt 5 ]; then
    echo -e "${YELLOW}Not enough identity keys in $KEYS_FILE. Please add at least 5.${NC}"
    exit 1
fi

# Настройки
storage_gb=50
start_port=1235
container_count=5

# Отключение IPv6 временно
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.lo.disable_ipv6=1

# Получение публичного IP
public_ip=$(curl -s ifconfig.me)

if [ -z "$public_ip" ]; then
    echo -e "${YELLOW}No public IP detected.${NC}"
    exit 1
fi

# Загрузка Docker-образа
echo -e "${GREEN}Pulling the Docker image nezha123/titan-edge...${NC}"
docker pull nezha123/titan-edge

# Настройка контейнеров
current_port=$start_port

for ((i=1; i<=container_count; i++)); do
    key="${identity_keys[$((i-1))]}"
    storage_path="/root/titan_storage_${public_ip}_${i}"

    echo -e "${GREEN}Setting up node $i with key: $key${NC}"

    # Создание хранилища
    sudo mkdir -p "$storage_path"
    sudo chmod -R 777 "$storage_path"

    # Запуск контейнера
    container_id=$(docker run -d --restart always -v "$storage_path:/root/.titanedge/storage" --name "titan_${public_ip}_${i}" --net=host nezha123/titan-edge)

    echo -e "${GREEN}Node titan_${public_ip}_${i} is running with container ID $container_id${NC}"

    sleep 30

    # Настройка config.toml
    docker exec $container_id bash -c "\
        sed -i 's/^[[:space:]]*#StorageGB = .*/StorageGB = $storage_gb/' /root/.titanedge/config.toml && \
        sed -i 's/^[[:space:]]*#ListenAddress = \"0.0.0.0:1234\"/ListenAddress = \"0.0.0.0:$current_port\"/' /root/.titanedge/config.toml && \
        echo 'Storage set to $storage_gb GB, Port: $current_port'"

    # Перезапуск контейнера
    docker restart $container_id

    # Привязка узла
    docker exec $container_id bash -c "\
        titan-edge bind --hash=$key https://api-test1.container1.titannet.io/api/v2/device/binding"

    echo -e "${GREEN}Node titan_${public_ip}_${i} initialized and bound with key $key.${NC}"

    current_port=$((current_port + 1))
done

echo -e "${GREEN}============================== All nodes have been set up and are running ===============================${NC}"
