# Gemini API 调用说明

## 获取模型参数

获取当前可用的模型及其详细参数。

**请求方式**
- **Method:** `GET`
- **Endpoint:** `{服务端点}/v1beta/models`
- **Headers:** 
    - `Authorization: Bearer {token}`

**请求示例**
```cURL
curl -X GET "https://api.yyds168.net/v1beta/models" \
  -H "Authorization: Bearer sk-84zEq1QH9JLQxSTNWYZAsjx9xMrs03rmbekEPz1utAz7yxJF"
```

**响应格式**
响应为 JSON 对象，包含一个 `models` 数组。

**响应示例**
```json
{
  "models": [
    {
      "name": "gemini-1.5-pro",
      "version": "v1beta",
      "displayName": "Gemini 1.5 Pro",
      "description": "Mid-size multimodal model that optimizes for a wide-range of reasoning tasks.",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 8192,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens"
      ]
    }
  ]
}
```

> **注意**: 在测试中发现，直接访问 `{服务端点}/models` 可能会返回 HTML 页面。建议使用 `/v1beta/models` 路径以获取正确的 JSON 格式响应。