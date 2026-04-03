# 下載任務 YAML 規格

## 1. YAML 範本

```yaml
targets:
  - localpath: /data/teamA/raw
    exportedlinks:
      - https://mega.nz/file/xxx#key
      - https://mega.nz/file/yyy#key
  - localpath: teamB/video
    exportedlinks:
      - https://mega.nz/file/aaa#key
```

## 2. 欄位定義

### 2.1 根層級

| 欄位 | 型別 | 必填 | 說明 |
| --- | --- | --- | --- |
| `targets` | 陣列[mapping] | 是 | 下載目標清單 |

### 2.2 `targets` 元素

| 欄位 | 型別 | 必填 | 說明 |
| --- | --- | --- | --- |
| `localpath` | 字串 | 是 | 下載目的地路徑 |
| `exportedlinks` | 陣列[string] | 是 | MEGA 公開連結清單 |

### 2.3 允許值

1. `localpath` 可為絕對路徑。
2. `localpath` 可為相對路徑。
3. `localpath` 可為空字串 `""`。
4. `exportedlinks` 可為空陣列。

## 3. 範例

### 3.1 同一路徑多連結

```yaml
targets:
  - localpath: /data/project-a
    exportedlinks:
      - https://mega.nz/file/111#key
      - https://mega.nz/file/222#key
```

### 3.2 空連結清單

```yaml
targets:
  - localpath: /data/project-b
    exportedlinks: []
```
