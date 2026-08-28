# 备份格式（kabao-backup）

本文档描述卡包导出的加密备份文件格式。所有业务数据只存在于密文中，文件头仅含非敏感元数据。

## 文件扩展名

`.kabao` — UTF-8 编码的 JSON 文本。

## 结构（版本 1）

```json
{
  "format": "kabao-backup",
  "version": 1,
  "createdAt": 1756000000000,
  "cipher": "aes-256-gcm",
  "kdf": {
    "algo": "argon2id",
    "iterations": 3,
    "memoryKiB": 32768,
    "parallelism": 2,
    "hashLength": 32,
    "salt": "<base64, 16 字节随机盐>"
  },
  "data": "<base64: nonce(12) + ciphertext + tag(16)>"
}
```

### 字段说明

| 字段 | 说明 |
| --- | --- |
| `format` | 固定 `"kabao-backup"`；导入时校验 |
| `version` | 整数格式版本；当前为 `1`。导入程序必须拒绝高于自身支持版本的文件 |
| `createdAt` | 毫秒时间戳（UTC），备份创建时间，非敏感 |
| `cipher` | 当前仅 `aes-256-gcm`（AEAD，每次加密唯一随机 nonce） |
| `kdf.algo` | Argon2id；盐独立随机生成，不与主密码复用任何派生材料 |
| `data` | AES-256-GCM 组合输出：`12B nonce + 密文 + 16B 认证标签` |

### 密文内容（解密后 JSON）

```json
{
  "categories": [ { "id": "...", "cardType": "debit|credit|document", "name": "...",
                    "sortOrder": 0, "createdAt": 0, "updatedAt": 0,
                    "modelVersion": 1 } ],
  "cards": [ { "id": "...", "categoryId": "...", "cardType": "...",
               "cardNumber": "纯数字", "expiryMonth": null, "expiryYear": null,
               "cvv": null, "uShieldExpiryDate": "yyyy/M/d 或 null",
               "note": null, "createdAt": 0, "updatedAt": 0,
               "modelVersion": 1 } ],
  "documents": [ { "id": "...", "categoryId": "...", "holderName": "...",
                   "idNumber": "纯数字", "issuer": "...",
                   "validFrom": "yyyy.MM.dd 或 null",
                   "validTo": "yyyy.MM.dd 或 null",
                   "validityPermanent": true,
                   "createdAt": 0, "updatedAt": 0, "modelVersion": 1 } ]
}
```

`documents` 为可选数组（无证件时不写入）。`validityPermanent` 仅在证件标记为
「长期有效」时出现，此时 `validFrom`/`validTo` 均为 `null`；缺少该字段的旧备份
按非长期有效导入。`idNumber` 始终是无分隔符的连续数字，分组只发生在展示层。

通知不在备份内：它们由提醒规则从卡片数据幂等重建。

## 密钥策略

- 备份使用用户输入的**独立备份密码**经 Argon2id 派生 KEK 加密，与主密码的存储包装互相独立。
- 不保存、不提示主密码本身；忘记备份密码时数据不可恢复（无后门）。

## 导入流程要求

1. **预校验**：解析 `format`/`version`/KDF 参数合法性；失败即中止。
2. **认证解密到内存暂存**：认证标签校验失败不得写入现有库。
3. **用户确认**：展示创建时间与条目数量等非敏感摘要，确认合并策略。
4. **合并规则**：按 UUID 合并；同 ID 冲突时以 `updatedAt` 较新者为准（默认），并计入冲突计数反馈给用户。
5. **原子性**：写入在数据库事务中执行，失败整体回滚。

## 版本迁移

- 增加字段时必须保持旧版本可导入（新字段可选）。
- 破坏性变更必须递增 `version` 并在本文件记录兼容窗口。
