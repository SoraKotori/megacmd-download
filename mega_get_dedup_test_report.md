# megacmd-download

## 背景

此文件用來釐清批次下載情境下的 `mega-get` 目的地去重行為，作為後續在 K8s Job 設計同步流程的依據。

使用情境：

1. 每次會輸入一批 URL，但可能與過往批次有重複項目。
2. 檔案下載到目標資料夾時（可為本地或掛載路徑），希望只保留一份。
3. 需確認本機快取（不同 `HOME`）是否會影響去重判定。

## 測試目標

1. 驗證 `mega-get` 去重是否僅看檔名，或會做內容判斷。
2. 驗證不同本機快取（不同 `HOME`）下，去重結果是否一致。
3. 驗證核心條件：不同快取、相同 link、相同目的地（依序執行）。
4. 去重範圍定義：以「同一目的地資料夾內」為判定範圍，不以「跨不同目的地資料夾全域單份」為本輪目標。

## 測試條件

1. 使用 MEGAcmd `2.5.1.1`。
2. 使用公開連結（public link）進行下載測試。
3. 本次所有測試皆為依序執行（非並行）。
4. 在本輪測試窗口內，將「相同 link」視為指向固定內容。

## 組合與範圍

可能的測試組合維度如下：

1. 快取：相同 `HOME` / 不同 `HOME`。
2. Link：相同 link / 不同 link。
3. 內容：同內容 / 不同內容。
4. 目的地：相同目的地 / 不同目的地。

分類規則（本文件）：

1. `要驗證`：使用場景核心且高機率會遇到的情境。
2. `未驗證`：未來可能會遇到，或值得延伸探討的情境。
3. `不驗證`：可用常理判斷、驗證價值低或不值得投入成本的情境。

### 16 組合分類表

| ID | Cache | Link | Content | Dest | 分類 | 說明 |
|---|---|---|---|---|---|---|
| C1 | same | same | same | same | 要驗證 | 同目的地依序下載，為去重核心路徑 |
| C2 | same | same | same | diff | 未驗證 | 同內容但不同目的地，未來若要做跨目錄單份策略可再補測 |
| C3 | same | same | diff | same | 不驗證 | 相同 link 但不同內容在本輪假設下不成立 |
| C4 | same | same | diff | diff | 不驗證 | 相同 link 但不同內容在本輪假設下不成立 |
| C5 | same | diff | same | same | 要驗證 | 同目的地依序下載，為去重核心路徑 |
| C6 | same | diff | same | diff | 未驗證 | 不同 link 但同內容且不同目的地，值得評估全域去重策略 |
| C7 | same | diff | diff | same | 要驗證 | 同目的地依序下載，為去重核心路徑 |
| C8 | same | diff | diff | diff | 不驗證 | 不同目的地且內容不同，結果可由常理直接判斷 |
| C9 | diff | same | same | same | 要驗證 | 同目的地依序下載，為去重核心路徑 |
| C10 | diff | same | same | diff | 未驗證 | 不同快取下同內容但不同目的地，若需跨目錄策略可再補測 |
| C11 | diff | same | diff | same | 不驗證 | 相同 link 但不同內容在本輪假設下不成立 |
| C12 | diff | same | diff | diff | 不驗證 | 相同 link 但不同內容在本輪假設下不成立 |
| C13 | diff | diff | same | same | 要驗證 | 同目的地依序下載，為去重核心路徑 |
| C14 | diff | diff | same | diff | 未驗證 | 不同快取且不同 link 但同內容，值得延伸全域去重探討 |
| C15 | diff | diff | diff | same | 要驗證 | 同目的地依序下載，為去重核心路徑 |
| C16 | diff | diff | diff | diff | 不驗證 | 不同目的地且內容不同，結果可由常理直接判斷 |

統計：

1. `要驗證`：6 組
2. `未驗證`：4 組
3. `不驗證`：6 組

補充：當 `Dest=diff` 時，預設不屬於本輪核心去重路徑（除非有延伸價值）。

## 實驗方法

本輪執行識別：`20260403T065432Z`。
所有案例皆為依序執行。
本文不將具體路徑作為主要證據，重點以輸入條件與輸出結果（檔案數、檔名、hash）為準。

1. 清理舊環境：刪除本地與遠端舊測試資料。
2. 建立本輪工作區：使用固定 `run_id` 隔離本輪資料。
3. 建立來源測資：`same_1.bin`/`same_2.bin`（同內容、不同 mtime），`diff_1.bin`/`diff_2.bin`（不同內容）；hash 分別為 `4677942d...c019c615`、`49ca5d81...6c1c172d`、`f4dd4112...84047011`。
4. 上傳與連結準備：上傳至 `sameA/sameB/diffA/diffB`（檔名統一 `foo.bin`），再建立 `LINK_SAME_A`、`LINK_SAME_B`、`LINK_DIFF_A`、`LINK_DIFF_B`。
5. 執行 6 組核心案例：`C1`、`C5`、`C7`、`C9`、`C13`、`C15`（皆為 `Dest=same`）。
6. diff cache 關鍵控制：`C9/C13/C15` 先建立獨立 `HOME` 目錄，再用 `HOME=... mega-get ...` 執行，並確認每個 `HOME` 都有自己的 `.megaCmd`。

## 測試結果（6 組核心實驗）

以下 6 組對應 `要驗證` 分類：`C1`、`C5`、`C7`、`C9`、`C13`、`C15`。

### C1: same cache + same link + same content + same dest

1. 檔案數：`1`
2. 檔名：`foo.bin`
3. sha256：`4677942dfa3e74b5dea7484661a2485bb73ba422eb72d311fdb39372c019c615`

### C5: same cache + diff link + same content + same dest

1. 檔案數：`1`
2. 檔名：`foo.bin`
3. sha256：`4677942dfa3e74b5dea7484661a2485bb73ba422eb72d311fdb39372c019c615`

### C7: same cache + diff link + diff content + same dest

1. 檔案數：`2`
2. 檔名：`foo.bin`、`foo (1).bin`
3. sha256：
- `foo.bin`：`49ca5d81054fdd20572294b9350b605d05e0df91da09a46fb8bde7fd6c1c172d`
- `foo (1).bin`：`f4dd4112a2540430e5a8a7158bcf120f8f2489bffa4d8f6aefa8dcd584047011`

### C9: diff cache + same link + same content + same dest

1. 檔案數：`1`
2. 檔名：`foo.bin`
3. sha256：`4677942dfa3e74b5dea7484661a2485bb73ba422eb72d311fdb39372c019c615`

### C13: diff cache + diff link + same content + same dest

1. 檔案數：`1`
2. 檔名：`foo.bin`
3. sha256：`4677942dfa3e74b5dea7484661a2485bb73ba422eb72d311fdb39372c019c615`

### C15: diff cache + diff link + diff content + same dest

1. 檔案數：`2`
2. 檔名：`foo.bin`、`foo (1).bin`
3. sha256：
- `foo.bin`：`49ca5d81054fdd20572294b9350b605d05e0df91da09a46fb8bde7fd6c1c172d`
- `foo (1).bin`：`f4dd4112a2540430e5a8a7158bcf120f8f2489bffa4d8f6aefa8dcd584047011`

## 結論

1. `mega-get` 的去重不是只看檔名。
2. 同名同內容會視為已存在，不新增副本。
3. 同名不同內容會另存為 ` (NUM)`。
4. 在本次實測中，去重結果不依賴本機快取（不同 `HOME` 結果一致）。
5. 本輪結論僅涵蓋同一目的地資料夾（`Dest=same`）的去重行為；`Dest=diff` 不在本輪結論範圍。

## 邊界

1. 以上為依序執行結果（非並行競態測試）。
