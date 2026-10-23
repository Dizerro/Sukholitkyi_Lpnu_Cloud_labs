# Notes API

Лабораторна робота 1 з хмарних технологій. Невеликий REST API для нотаток на FastAPI + PostgreSQL. Запакований в Docker, в AWS піднімається через Terraform.

Працює тут: http://notes-api-1576192979.eu-north-1.elb.amazonaws.com
(Swagger на `/docs`, перевірка стану на `/health`)

Після `terraform destroy` адреса зникає, при новому деплої вона буде іншою. Поточну можна подивитись командою `terraform output alb_dns`.

## Що це за застосунок

Звичайний CRUD: можна створити нотатку (заголовок і текст), подивитись список, відкрити одну або видалити. Таблиця `notes` створюється сама при старті.

- `GET /notes` список
- `POST /notes` створити, тіло `{"title": "...", "body": "..."}`
- `GET /notes/{id}` одна нотатка
- `DELETE /notes/{id}` видалити

Дані для підключення до бази застосунок бере зі змінних середовища (`DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`), у коді їх немає.

## Як запустити локально

Потрібен тільки Docker:

```bash
docker compose up --build -d
curl localhost:8000/health
```

База лежить у volume `pgdata`, тож після `docker compose down` дані нікуди не діваються.

## Як це влаштовано в AWS

Регіон eu-north-1. Запити приходять на ALB, він передає їх на два контейнери в ECS Fargate, а ті ходять у RDS PostgreSQL.

База стоїть у приватних підмережах, публічної адреси в неї немає. Її security group пускає тільки трафік від security group застосунку, а не від IP-адрес. Порт 8000 контейнерів відкритий лише для балансувальника.

Контейнери ECS стоять у публічних підмережах з публічним IP. Я зробив так, щоб не платити за NAT Gateway: інакше контейнерам нема як завантажити образ з ECR. З інтернету до них все одно не достукатись, бо їх закриває security group.

Пароль до бази генерує Terraform і кладе в Secrets Manager, в контейнер він потрапляє як змінна середовища.

## Структура проєкту

```
app/main.py          код застосунку
requirements.txt     залежності з зафіксованими версіями
Dockerfile           образ на python:3.12-slim-bookworm, працює не від root
compose.yaml         застосунок + postgres для локального запуску
terraform/
  main.tf            провайдер, змінні, реєстр ECR
  network.tf         VPC, підмережі, security groups
  rds.tf             база і пароль
  ecs.tf             кластер, сервіс, ролі IAM, логи
  alb.tf             балансувальник і health check
  outputs.tf         адреса ALB та URL реєстру
.github/workflows/deploy.yml   CI/CD
```

## Розгортання

Потрібні AWS CLI, Terraform і Docker. Спочатку створюється лише реєстр, бо ECS не стартує без образу:

```bash
cd terraform
echo 'github_repo = "Dizerro/Sukholitkyi_Lpnu_Cloud_labs"' > terraform.tfvars
terraform init
terraform apply -target=aws_ecr_repository.app
```

Потім збираю й пушу перший образ:

```bash
cd ..
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REG=$ACCOUNT.dkr.ecr.eu-north-1.amazonaws.com
aws ecr get-login-password --region eu-north-1 | docker login --username AWS --password-stdin $REG
docker build -t $REG/notes-api:v0 .
docker push $REG/notes-api:v0
```

І піднімаю все решту (база створюється хвилин 8):

```bash
cd terraform
terraform apply
```

Прибрати все: `terraform destroy`.

## CI/CD

У `deploy.yml` описано pipeline: push у `main`, збірка образу, пуш в ECR з тегом-хешем коміту, оновлення сервісу ECS. Авторизація в AWS має бути через OIDC, без ключів.

Зараз це не працює. Для OIDC треба створити IAM OIDC-провайдер, а в моєму акаунті це заборонено політикою організації (service control policy `p-muvfnqzm`), якою я не керую. Тому провайдер у Terraform не розгорнутий. Звернувся в підтримку AWS.
