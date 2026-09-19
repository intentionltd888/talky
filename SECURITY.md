# 安全回報 / Security

（English below）

## 這個 app 會連到哪裡

Talky 只有兩種對外連線，其餘全部在你的電腦上：

1. 下載模型：直連 HuggingFace（語音模型 whisper large-v3-turbo、可選的整理模型 Qwen3-4B），下載後以程式內建的 SHA256 比對。
2. 你選的整理服務：只在你選了「用自己的訂閱」或「自填端點」時，把辨識出來的文字送去你自己的帳號。選內建模型或「不整理」就什麼都不出去。

語音引擎與本機整理引擎只綁 `127.0.0.1`，不對外開埠。沒有遙測、沒有帳號系統、沒有自動更新檢查、沒有任何自家伺服器。

## 發現漏洞怎麼回報

請用 GitHub 的私密回報：repo 頁 → **Security** → **Report a vulnerability**。不要開公開 issue 描述可被利用的細節。
我們會在 7 天內回覆。修好後會在 release notes 具名感謝（除非你不想）。

支援的版本：最新的 Release。

---

## What the app talks to

Talky makes exactly two kinds of outbound connection. Everything else stays on your Mac:

1. Model download: direct from HuggingFace (the whisper large-v3-turbo speech model and the optional Qwen3-4B tidying model), verified against a SHA256 compiled into the app.
2. The tidying service you chose: only if you picked "your own subscription" or "your own endpoint", the recognised text is sent to your own account. With the built-in model or "no tidying", nothing leaves.

The speech and local tidying engines bind to `127.0.0.1` only. No telemetry, no account system, no update check, no servers of ours.

## Reporting a vulnerability

Use GitHub private vulnerability reporting: repository page → **Security** → **Report a vulnerability**. Please do not open a public issue with exploitable details.
We reply within 7 days and credit you in the release notes unless you prefer otherwise.

Supported version: the latest Release.
