## 🚀 Cómo usar la API

### Endpoint
POST https://<api-id>.execute-api.<region>.amazonaws.com/stage/register

### 🧪 Ejemplo de solicitud con `curl`

```bash
curl -X POST \
  https://qlzqb4opwi.execute-api.us-east-1.amazonaws.com/stage/register \
  -H "Content-Type: application/json" \
  -d '{
    "id": "123",
    "name": "Juan Pérez",
    "email": "juan@example.com"
  }'
```