# Gemini Image Generation API Response Specification (RESTful)

## 1. 概述

本文档定义了 `gemini-3-pro-image-preview` 模型在通过 REST API 生成图像时的返回报文格式，涵盖 **Unary (一次性)** 与 **Stream (流式)** 两种模式。

## 2. 数据结构定义 (TypeScript 风格)

TypeScript

```TypeScript
interface GeminiImageResponse {
  candidates: Candidate[];
  usageMetadata: UsageMetadata;
}

interface Candidate {
  content: {
    role: "model";
    parts: Part[];
  };
  finishReason: "STOP" | "SAFETY" | "RECITATION" | "OTHER";
  index: number;
  safetyRatings: SafetyRating[];
}

type Part = TextPart | InlineDataPart;

interface TextPart {
  text: string; // 模型的文字描述或提示
}

interface InlineDataPart {
  inlineData: {
    mimeType: string; // 示例: "image/png"
    data: string;     // Base64 编码的图像二进制数据
  };
}

interface SafetyRating {
  category: string;
  probability: "NEGLIGIBLE" | "LOW" | "MEDIUM" | "HIGH";
}
```

------

## 3. 场景报文示例

### 3.1 成功响应 (Unary)

**特点**：包含完整的 Base64 数据，**不包含文件名**。

JSON

```json
{
  "candidates": [
    {
      "content": {
        "role": "model",
        "parts": [
          { "text": "Generated image based on your prompt:" },
          {
            "inlineData": {
              "mimeType": "image/png",
              "data": "iVBORw0KGgoAAAANSUhEUgAA..." 
            }
          }
        ]
      },
      "finishReason": "STOP"
    }
  ]
}
```

### 3.2 流式响应 (Stream)

**特点**：响应体为 JSON 数组。通常文本先出，图片数据在后续的 Chunk 中完整出现。

JSON

```json
[
  {
    "candidates": [{ "content": { "parts": [{ "text": "Generating..." }] } }]
  },
  {
    "candidates": [
      {
        "content": {
          "parts": [
            {
              "inlineData": {
                "mimeType": "image/png",
                "data": "iVBORw0KGgoAAAANSUhEUgAA..."
              }
            }
          ]
        },
        "finishReason": "STOP"
      }
    ]
  }
]
```

### 3.3 异常响应 (Error/Safety)

**安全拦截（业务级）：**

JSON

```json
{
  "candidates": [
    {
      "finishReason": "SAFETY",
      "safetyRatings": [{ "category": "HARM_CATEGORY_DANGEROUS_CONTENT", "probability": "HIGH" }]
    }
  ]
}
```

**接口/授权错误（系统级）：**

JSON

```json
{
  "error": {
    "code": 403,
    "message": "The caller does not have permission",
    "status": "PERMISSION_DENIED"
  }
}
```

------

## 4. 关键逻辑提示 (针对 Code Assist)

1. **文件名处理**：API 响应**不提供文件名**。开发者需在处理 `inlineData` 时，根据业务逻辑自拟文件名（如 `UUID.png` 或 `timestamp.png`）。
2. **Base64 解码**：必须提取 `parts` 中包含 `inlineData` 的项，并将其 `data` 字段从 Base64 转为二进制流存储。
3. **安全检查**：在处理 `parts` 前，必须先检查 `finishReason`。若为 `SAFETY`，则 `parts` 可能为空。