## EA48763 SAR Strategy
version 1.0.0 (Date 2025/02/07)\
`DayBreak.mq5` and `SAR.mq5` must currently be run together.
Profits from this strategy remain volatile.
***
>策略現狀\
>主要獲利來源為`SAR.mq5`(希望)
>趨勢盤會爆虧，目前使用`DayBreak.mq5`作為彌補策略
>目前針對單日VA型態沒有解決辦法
>time filter的有效性正在實測\
>`SAR-Advanced.mq5`目的為了進階策略實驗，目前就是一坨屎
***
This is a to-do list in order of priority.
- [ ] `DayBreak.mq5` 解決觸發停利仍會開啟新倉問題
  - [X] [緊急]open price 的設定有問題，偏離價格太多，嘗試改成設定1:25~1:35(交易所時間)，正在檢查是否改善
  - [ ] 以隨機方式或其他量化決定正反邏輯交易時機
